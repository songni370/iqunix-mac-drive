import Foundation

public struct BackupDevice: Codable, Sendable, Equatable {
    public let product: String
    public let vendorID: Int
    public let productID: Int
    public let protocolVersion: Int
    public let layerCount: Int
    public let rows: Int
    public let cols: Int

    public init(product: String, vendorID: Int, productID: Int, protocolVersion: Int, layerCount: Int, rows: Int, cols: Int) {
        self.product = product
        self.vendorID = vendorID
        self.productID = productID
        self.protocolVersion = protocolVersion
        self.layerCount = layerCount
        self.rows = rows
        self.cols = cols
    }
}

public struct KeyboardBackup: Codable, Sendable {
    public let format: Int
    public let createdAt: Date
    public let appVersion: String
    public let device: BackupDevice
    public let keymap: Keymap
    public let lighting: LightingState?
    public let macrosBase64: String?

    public init(
        format: Int = AppConstants.backupFormat,
        createdAt: Date = Date(),
        appVersion: String = AppConstants.appVersion,
        device: BackupDevice,
        keymap: Keymap,
        lighting: LightingState?,
        macrosBase64: String?
    ) {
        self.format = format
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.device = device
        self.keymap = keymap
        self.lighting = lighting
        self.macrosBase64 = macrosBase64
    }

    public init(controller: VIAController, keymap: Keymap, lighting: LightingState?, macros: MacrosBlob?) {
        self.init(
            device: BackupDevice(
                product: controller.info.product,
                vendorID: controller.info.vendorID,
                productID: controller.info.productID,
                protocolVersion: controller.info.protocolVersion,
                layerCount: controller.info.layerCount,
                rows: controller.info.rows,
                cols: controller.info.cols
            ),
            keymap: keymap,
            lighting: lighting,
            macrosBase64: macros?.data.base64EncodedString()
        )
    }
}

public struct BackupFile: Identifiable, Sendable {
    public let url: URL
    public let createdAt: Date
    public let summary: String

    public var id: URL { url }
    public var name: String { url.deletingPathExtension().lastPathComponent }
}

public enum BackupStore {
    public static var baseDirectory: URL {
        DefinitionStore.applicationSupportDirectory
    }

    public static var backupsDirectory: URL {
        baseDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        try ensureDirectory(nil)
    }

    /// Ensure a backup directory exists. Pass `nil` for the default App Support directory.
    public static func ensureDirectory(_ directory: URL? = nil) throws {
        let target = directory ?? backupsDirectory
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @discardableResult
    public static func save(_ backup: KeyboardBackup, name: String? = nil, directory: URL? = nil) throws -> URL {
        let targetDirectory = directory ?? backupsDirectory
        try ensureDirectory(targetDirectory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let generated = "Keyboard-\(formatter.string(from: backup.createdAt))"
        let filename = "\(name ?? generated).json"
        let url = targetDirectory.appendingPathComponent(filename)
        let data = try encoder().encode(backup)
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func list(directory: URL? = nil) -> [BackupFile] {
        let targetDirectory = directory ?? backupsDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> BackupFile? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let date = values?.contentModificationDate ?? Date.distantPast
                guard let backup = try? load(url) else { return nil }
                let summary = "\(backup.device.product) · \(backup.device.layerCount) 层 · \(backup.keymap.matrixCount) 键"
                return BackupFile(url: url, createdAt: date, summary: summary)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public static func load(_ url: URL) throws -> KeyboardBackup {
        do {
            let data = try Data(contentsOf: url)
            let backup = try decoder().decode(KeyboardBackup.self, from: data)
            guard backup.format == AppConstants.backupFormat else {
                throw VIAError.backupCorrupted("未知格式版本 \(backup.format)")
            }
            return backup
        } catch let error as VIAError {
            throw error
        } catch {
            throw VIAError.backupCorrupted(error.localizedDescription)
        }
    }

    public static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
