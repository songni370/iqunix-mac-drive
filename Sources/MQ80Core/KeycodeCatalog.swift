import Foundation

public enum KeycodeCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case basic
    case modifiers
    case function
    case navigation
    case keypad
    case media
    case mouse
    case lighting
    case layer
    case custom
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .basic: return "基础"
        case .modifiers: return "修饰键"
        case .function: return "功能键"
        case .navigation: return "导航"
        case .keypad: return "数字键盘"
        case .media: return "媒体/系统"
        case .mouse: return "鼠标"
        case .lighting: return "灯效键"
        case .layer: return "层功能"
        case .custom: return "MQ80 自定义"
        case .other: return "其他"
        }
    }
}

public struct KeycodeInfo: Identifiable, Hashable, Sendable {
    public let value: UInt16
    public let code: String
    public let label: String
    public let category: KeycodeCategory

    public var id: UInt16 { value }

    public init(value: UInt16, code: String, label: String, category: KeycodeCategory) {
        self.value = value
        self.code = code
        self.label = label
        self.category = category
    }
}

public enum KeycodeCatalog {
    /// Raw matrix value used when a position is not populated.
    public static let kcNo: UInt16 = 0x0000
    /// Transparent keycode, passes through to the layer below.
    public static let kcTransparent: UInt16 = 0x0001
    /// Base value of QMK custom keycodes depends on the VIA protocol / QMK
    /// keycodes generation: protocol 11 uses 0x7F00, protocol 12+ uses 0x7E00.
    public static func customKeycodeBase(protocolVersion: Int) -> UInt16 {
        protocolVersion >= 12 ? 0x7E00 : 0x7F00
    }

    /// The keycode table matching the keyboard's VIA protocol version.
    public static func base(protocolVersion: Int) -> [KeycodeInfo] {
        switch protocolVersion {
        case 11:
            return base
        case 12:
            return baseV12
        case 13...:
            return baseV13
        default:
            return base
        }
    }

    public static func entries(
        protocolVersion: Int = 11,
        customKeycodeNames: [String],
        customKeycodeTitles: [String] = [],
        layerCount: Int
    ) -> [KeycodeInfo] {
        var result = base(protocolVersion: protocolVersion)
        let customBase = customKeycodeBase(protocolVersion: protocolVersion)
        let layerRange = 0..<max(1, min(layerCount, 8))
        for layer in layerRange {
            result.append(KeycodeInfo(value: UInt16(0x5200 + layer), code: "TO(\(layer))", label: "TO(\(layer))", category: .layer))
            result.append(KeycodeInfo(value: UInt16(0x5220 + layer), code: "MO(\(layer))", label: "MO(\(layer))", category: .layer))
            result.append(KeycodeInfo(value: UInt16(0x5240 + layer), code: "DF(\(layer))", label: "DF(\(layer))", category: .layer))
            result.append(KeycodeInfo(value: UInt16(0x5260 + layer), code: "TG(\(layer))", label: "TG(\(layer))", category: .layer))
            result.append(KeycodeInfo(value: UInt16(0x5280 + layer), code: "OSL(\(layer))", label: "OSL(\(layer))", category: .layer))
            result.append(KeycodeInfo(value: UInt16(0x52C0 + layer), code: "TT(\(layer))", label: "TT(\(layer))", category: .layer))
        }
        for (index, name) in customKeycodeNames.enumerated() where index < 256 {
            let title = index < customKeycodeTitles.count ? customKeycodeTitles[index] : name
            result.append(KeycodeInfo(
                value: customBase + UInt16(index),
                code: "MQ80_\(index)",
                label: name,
                category: .custom
            ))
            _ = title
        }
        // De-duplicate by value, preferring later (layer/custom) entries.
        var byValue: [UInt16: KeycodeInfo] = [:]
        for info in result { byValue[info.value] = info }
        return byValue.values.sorted { a, b in
            let orderA = KeycodeCategory.allCases.firstIndex(of: a.category) ?? 99
            let orderB = KeycodeCategory.allCases.firstIndex(of: b.category) ?? 99
            if orderA != orderB { return orderA < orderB }
            if a.label.lowercased() != b.label.lowercased() { return a.label.lowercased() < b.label.lowercased() }
            return a.value < b.value
        }
    }

    public static func info(for value: UInt16, customKeycodeNames: [String], protocolVersion: Int = 11) -> KeycodeInfo? {
        if let baseInfo = base(protocolVersion: protocolVersion).first(where: { $0.value == value }) {
            return baseInfo
        }
        if let layerInfo = layerKeyInfo(value) {
            return layerInfo
        }
        let customBase = customKeycodeBase(protocolVersion: protocolVersion)
        if value >= customBase, value < customBase + 0x100 {
            let index = Int(value - customBase)
            if index < customKeycodeNames.count {
                return KeycodeInfo(value: value, code: "MQ80_\(index)", label: customKeycodeNames[index], category: .custom)
            }
            return KeycodeInfo(value: value, code: "MQ80_\(index)", label: "Custom \(index)", category: .custom)
        }
        return nil
    }

    public static func label(for value: UInt16, customKeycodeNames: [String], layerCount: Int = 4, protocolVersion: Int = 11) -> String {
        if let info = info(for: value, customKeycodeNames: customKeycodeNames, protocolVersion: protocolVersion) {
            return info.label
        }
        return String(format: "0x%04X", value)
    }

    public static func search(_ query: String, entries: [KeycodeInfo]) -> [KeycodeInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.label.lowercased().contains(trimmed) ||
            $0.code.lowercased().contains(trimmed) ||
            String(format: "0x%04X", $0.value).lowercased().contains(trimmed)
        }
    }

    private static func layerKeyInfo(_ value: UInt16) -> KeycodeInfo? {
        let layerOperations: [(base: UInt16, prefix: String)] = [
            (0x5200, "TO"),
            (0x5220, "MO"),
            (0x5240, "DF"),
            (0x5260, "TG"),
            (0x5280, "OSL"),
            (0x52C0, "TT"),
        ]
        for operation in layerOperations where value >= operation.base && value < operation.base + 0x20 {
            let layer = Int(value - operation.base)
            return KeycodeInfo(
                value: value,
                code: "\(operation.prefix)(\(layer))",
                label: "\(operation.prefix)(\(layer))",
                category: .layer
            )
        }
        return nil
    }
}
