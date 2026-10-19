import Foundation

// MARK: - Bundled VIA keyboard definitions

public struct BuiltinDefinitionEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let vendorId: String
    public let productId: String
    public let rows: Int
    public let cols: Int
    public let file: String
}

private struct BuiltinDefinitionIndex: Codable {
    let version: Int
    let generatedAt: String?
    let count: Int
    let entries: [BuiltinDefinitionEntry]
}

/// Resolves a connected keyboard to a VIA keyboard definition.
///
/// Lookup order:
/// 1. user-imported definitions (`~/Library/Application Support/IQUNIX-DRIVE/Definitions`)
/// 2. built-in IQUNIX MQ80 definition (vendored official JSON)
/// 3. the bundled VIA keyboards library (generated from `the-via/keyboards`)
public final class DefinitionStore {
    public static let shared = DefinitionStore()

    public enum StoreError: Error, LocalizedError {
        case invalidDefinition
        case vendorProductMissing
        case noDefinitionsDirectory

        public var errorDescription: String? {
            switch self {
            case .invalidDefinition:
                return "无法解析这个键盘定义 JSON。请确认它是 VIA 的键盘定义（包含 name / vendorId / productId / matrix / layouts）。"
            case .vendorProductMissing:
                return "该键盘定义缺少 vendorId 或 productId，无法自动匹配。"
            case .noDefinitionsDirectory:
                return "没有找到内置 VIA 定义库（VIAKeyboardDefinitions），请先运行 scripts/gen_via_definitions.py 并重新构建。"
            }
        }
    }

    private let lock = NSLock()
    private var index: BuiltinDefinitionIndex?
    private var indexDirectory: URL?
    private var cache: [String: ResolvedDefinition] = [:]
    private var userDefinitions: [String: ResolvedDefinition] = [:]
    private var userFiles: [URL] = []

    public private(set) var builtinCount = 0
    public private(set) var userCount = 0

    private init() {}

    // MARK: Paths

    public static var applicationSupportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let appDir = support.appendingPathComponent("IQUNIX-DRIVE", isDirectory: true)
        // Migrate the pre-generic (MQ80 Studio) data directory once.
        let legacy = support.appendingPathComponent("MQ80Studio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appDir.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: appDir)
        }
        return appDir
    }

    public var userDefinitionsDirectory: URL {
        DefinitionStore.applicationSupportDirectory.appendingPathComponent("Definitions", isDirectory: true)
    }

    public var bundledDefinitionsDirectory: URL? {
        let env = ProcessInfo.processInfo.environment["IQUNIX_DRIVE_DEFINITIONS"]
        var candidates: [URL] = []
        if let env = env {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("VIAKeyboardDefinitions", isDirectory: true))
        }
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDirectory = executable.deletingLastPathComponent()
        candidates.append(executableDirectory.appendingPathComponent("VIAKeyboardDefinitions", isDirectory: true))
        candidates.append(executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources/VIAKeyboardDefinitions", isDirectory: true))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/VIAKeyboardDefinitions", isDirectory: true))

        for candidate in candidates {
            let indexURL = candidate.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: indexURL.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: Loading

    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        index = nil
        indexDirectory = nil
        cache.removeAll()
        userDefinitions.removeAll()
        userFiles.removeAll()
        builtinCount = 0
        userCount = 0
        loadUserDefinitionsLocked()
        loadBuiltinIndexLocked()
    }

    private func ensureLoadedLocked() {
        if index == nil && indexDirectory == nil {
            loadUserDefinitionsLocked()
            loadBuiltinIndexLocked()
        }
    }

    private func loadBuiltinIndexLocked() {
        guard let directory = bundledDefinitionsDirectory else { return }
        let indexURL = directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let parsed = try? JSONDecoder().decode(BuiltinDefinitionIndex.self, from: data) else {
            return
        }
        indexDirectory = directory
        index = parsed
        builtinCount = parsed.entries.count
    }

    private func loadUserDefinitionsLocked() {
        let directory = userDefinitionsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        userFiles = urls.filter { $0.pathExtension.lowercased() == "json" }
        for url in userFiles {
            guard let definition = parseDefinition(at: url) else { continue }
            let key = matchKey(definition.vendorID, definition.productID)
            userDefinitions[key] = ResolvedDefinition(
                definition: definition,
                source: .userImported,
                detail: url.lastPathComponent
            )
        }
        userCount = userDefinitions.count
    }

    // MARK: Resolve

    public func resolve(vendorID: Int, productID: Int) -> ResolvedDefinition? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        let vendorHex = String(format: "0x%04X", vendorID)
        let productHex = String(format: "0x%04X", productID)
        let key = matchKey(vendorHex, productHex)

        if let user = userDefinitions[key] {
            return user
        }
        if vendorID == AppConstants.mq80VendorID && productID == AppConstants.mq80ProductID {
            return ResolvedDefinition(definition: .mq80, source: .builtinMQ80, detail: "IQUNIX MQ80 KB-USB.json")
        }
        if let cached = cache[key] {
            return cached
        }
        guard let index = index, let directory = indexDirectory else { return nil }
        let matches = index.entries.filter {
            $0.vendorId.lowercased() == vendorHex.lowercased() &&
            $0.productId.lowercased() == productHex.lowercased()
        }
        guard let entry = matches.first else { return nil }
        let fileURL = directory.appendingPathComponent(entry.file)
        guard let definition = parseDefinition(at: fileURL) else { return nil }
        let resolved = ResolvedDefinition(
            definition: definition,
            source: .builtinLibrary,
            detail: entry.id
        )
        cache[key] = resolved
        return resolved
    }

    public func resolve(device: VIADevice) -> ResolvedDefinition? {
        resolve(vendorID: device.vendorID, productID: device.productID)
    }

    /// All bundled definitions matching a VID/PID (some keyboards ship variants).
    public func candidates(vendorID: Int, productID: Int) -> [BuiltinDefinitionEntry] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard let index = index else { return [] }
        let vendorHex = String(format: "0x%04X", vendorID)
        let productHex = String(format: "0x%04X", productID)
        return index.entries.filter {
            $0.vendorId.lowercased() == vendorHex.lowercased() &&
            $0.productId.lowercased() == productHex.lowercased()
        }
    }

    // MARK: Import

    @discardableResult
    public func importDefinition(from url: URL) throws -> KeyboardDefinition {
        let data = try Data(contentsOf: url)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let definition = KeyboardDefinition.parse(root: root) else {
            throw StoreError.invalidDefinition
        }
        guard definition.vendorID != "0x0000", definition.productID != "0x0000" else {
            throw StoreError.vendorProductMissing
        }
        let directory = userDefinitionsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = definition.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(definition.vendorID)_\(definition.productID)_\(safeName).json"
        let destination = directory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        reload()
        return definition
    }

    public func openUserDefinitionsDirectory() -> URL {
        let directory = userDefinitionsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Helpers

    private func parseDefinition(at url: URL) -> KeyboardDefinition? {
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return KeyboardDefinition.parse(root: root)
    }

    private func matchKey(_ vendorID: String, _ productID: String) -> String {
        "\(vendorID.uppercased()):\(productID.uppercased())"
    }
}
