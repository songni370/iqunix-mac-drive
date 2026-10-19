import Foundation

// MARK: - Layout key

public struct KeyPosition: Identifiable, Hashable, Sendable {
    public let id: Int          // matrix index = row * cols + col
    public let row: Int
    public let col: Int
    public let x: Double        // in keyboard units
    public let y: Double
    public let width: Double
    public let height: Double
    public let colorHex: String?

    public init(id: Int, row: Int, col: Int, x: Double, y: Double, width: Double, height: Double, colorHex: String?) {
        self.id = id
        self.row = row
        self.col = col
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
    }
}

public struct LightingOption: Identifiable, Hashable, Sendable {
    public let value: Int
    public let name: String
    public var id: Int { value }

    public init(value: Int, name: String) {
        self.value = value
        self.name = name
    }
}

// MARK: - Lighting

/// Best-effort description of the lighting controls declared by a keyboard
/// definition. VIA keyboards expose lighting through one of:
/// - V2 `lighting` presets (backlight / rgblight / backlight+rgblight)
/// - V3 `menus` with built-in names (`qmk_rgb_matrix`, ...)
/// - explicit custom menu commands (`id_qmk_rgb_matrix_brightness`, ...)
public struct LightingSpec: Sendable, Equatable {
    public var channel: Int
    public var label: String
    public var hasBrightness: Bool
    public var brightnessRange: ClosedRange<Int>
    public var hasEffect: Bool
    public var effects: [LightingOption]
    public var hasSpeed: Bool
    public var speedRange: ClosedRange<Int>
    public var hasColor: Bool

    public init(
        channel: Int = 0,
        label: String = "",
        hasBrightness: Bool = false,
        brightnessRange: ClosedRange<Int> = 0...255,
        hasEffect: Bool = false,
        effects: [LightingOption] = [],
        hasSpeed: Bool = false,
        speedRange: ClosedRange<Int> = 0...4,
        hasColor: Bool = false
    ) {
        self.channel = channel
        self.label = label
        self.hasBrightness = hasBrightness
        self.brightnessRange = brightnessRange
        self.hasEffect = hasEffect
        self.effects = effects
        self.hasSpeed = hasSpeed
        self.speedRange = speedRange
        self.hasColor = hasColor
    }

    public static let none = LightingSpec()

    public var isSupported: Bool {
        channel > 0 && (hasBrightness || hasEffect || hasSpeed || hasColor)
    }
}

public enum DefinitionSource: String, Codable, Sendable {
    case builtinMQ80
    case builtinLibrary
    case userImported

    public var title: String {
        switch self {
        case .builtinMQ80: return "内置 MQ80"
        case .builtinLibrary: return "内置 VIA 定义库"
        case .userImported: return "用户导入"
        }
    }
}

public struct ResolvedDefinition: Sendable {
    public let definition: KeyboardDefinition
    public let source: DefinitionSource
    public let detail: String

    public init(definition: KeyboardDefinition, source: DefinitionSource, detail: String) {
        self.definition = definition
        self.source = source
        self.detail = detail
    }
}

// MARK: - Keyboard definition

public struct KeyboardDefinition: Sendable {
    public let name: String
    public let vendorID: String
    public let productID: String
    public let rows: Int
    public let cols: Int
    public let keys: [KeyPosition]
    public let customKeycodeNames: [String]
    public let customKeycodeTitles: [String]
    public let lighting: LightingSpec
    public let layoutOptionLabels: [String]
    public let hasEncoders: Bool

    // Backwards-compatible convenience used by the UI.
    public var effects: [LightingOption] { lighting.effects }
    public var brightnessRange: ClosedRange<Int> { lighting.brightnessRange }
    public var speedRange: ClosedRange<Int> { lighting.speedRange }
    public var hasColor: Bool { lighting.hasColor }

    public var matrixCount: Int { rows * cols }
    public var hasLayout: Bool { !keys.isEmpty }

    public init(
        name: String,
        vendorID: String,
        productID: String,
        rows: Int,
        cols: Int,
        keys: [KeyPosition],
        customKeycodeNames: [String],
        customKeycodeTitles: [String],
        lighting: LightingSpec,
        layoutOptionLabels: [String],
        hasEncoders: Bool
    ) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.rows = rows
        self.cols = cols
        self.keys = keys
        self.customKeycodeNames = customKeycodeNames
        self.customKeycodeTitles = customKeycodeTitles
        self.lighting = lighting
        self.layoutOptionLabels = layoutOptionLabels
        self.hasEncoders = hasEncoders
    }

    public func matrixIndex(row: Int, col: Int) -> Int? {
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return row * cols + col
    }

    public func key(forMatrixIndex index: Int) -> KeyPosition? {
        keys.first { $0.id == index }
    }

    /// Built-in IQUNIX MQ80 definition (vendored from IQUNIX's official VIA guide).
    public static let mq80: KeyboardDefinition = parse(json: EmbeddedDefinition.json) ?? .placeholder

    public static let placeholder = KeyboardDefinition(
        name: "Unknown Keyboard",
        vendorID: "0x0000",
        productID: "0x0000",
        rows: 6,
        cols: 16,
        keys: [],
        customKeycodeNames: [],
        customKeycodeTitles: [],
        lighting: .none,
        layoutOptionLabels: [],
        hasEncoders: false
    )

    // MARK: - JSON parsing

    public static func parse(json: String) -> KeyboardDefinition? {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return parse(root: root)
    }

    public static func parse(root: [String: Any]) -> KeyboardDefinition? {
        let name = parseName(root["name"]) ?? "VIA Keyboard"
        let vendorID = hexString(root["vendorId"]) ?? "0x0000"
        let productID = hexString(root["productId"]) ?? "0x0000"

        var rows = 6
        var cols = 16
        if let matrix = root["matrix"] as? [String: Any] {
            rows = intValue(matrix["rows"]) ?? rows
            cols = intValue(matrix["cols"]) ?? cols
        }
        guard rows > 0, cols > 0, rows <= 32, cols <= 64 else { return nil }

        var keys: [KeyPosition] = []
        if let layouts = root["layouts"] as? [String: Any],
           let keymapRows = layouts["keymap"] as? [Any] {
            keys = parseKLE(keymapRows: keymapRows, rows: rows, cols: cols)
        }

        var customNames: [String] = []
        var customTitles: [String] = []
        if let customs = root["customKeycodes"] as? [[String: Any]] {
            for custom in customs {
                let short = custom["shortName"] as? String
                let full = custom["name"] as? String
                let title = custom["title"] as? String
                customNames.append(short ?? full ?? "Custom")
                customTitles.append(title ?? full ?? short ?? "Custom")
            }
        }

        var layoutOptionLabels: [String] = []
        if let rawLabels = (root["layouts"] as? [String: Any])?["labels"] as? [Any] {
            for label in rawLabels {
                if let text = label as? String {
                    layoutOptionLabels.append(text)
                } else if let choices = label as? [String], let first = choices.first {
                    layoutOptionLabels.append(first)
                }
            }
        }

        let hasEncoders = (root["encoders"] != nil) ||
            ((root["customFeatures"] as? [Any])?.contains { ($0 as? String) == "rotary-encoder" } ?? false)

        let lighting = parseLighting(root: root)

        let sortedKeys = keys.sorted { a, b in
            if abs(a.y - b.y) > 0.01 { return a.y < b.y }
            return a.x < b.x
        }

        return KeyboardDefinition(
            name: name,
            vendorID: vendorID,
            productID: productID,
            rows: rows,
            cols: cols,
            keys: sortedKeys,
            customKeycodeNames: customNames,
            customKeycodeTitles: customTitles,
            lighting: lighting,
            layoutOptionLabels: layoutOptionLabels,
            hasEncoders: hasEncoders
        )
    }

    private static func parseName(_ any: Any?) -> String? {
        if let text = any as? String { return text }
        if let dict = any as? [String: Any],
           let options = dict["options"] as? [String],
           let first = options.first {
            return first
        }
        return nil
    }

    private static func parseKLE(keymapRows: [Any], rows: Int, cols: Int) -> [KeyPosition] {
        var keys: [KeyPosition] = []
        var seen = Set<Int>()
        for (rowIndex, rowAny) in keymapRows.enumerated() {
            guard let items = rowAny as? [Any] else { continue }
            var x = 0.0
            var y = Double(rowIndex)
            var width = 1.0
            var height = 1.0
            var color: String?
            var decal = false
            for item in items {
                if let dict = item as? [String: Any] {
                    x += numberValue(dict["x"]) ?? 0
                    y += numberValue(dict["y"]) ?? 0
                    if let w = numberValue(dict["w"]) { width = w }
                    if let h = numberValue(dict["h"]) { height = h }
                    if let c = dict["c"] as? String { color = c }
                    if let d = dict["d"] as? Bool { decal = d }
                    continue
                }
                guard let label = item as? String else { continue }
                if decal {
                    x += width
                    width = 1
                    height = 1
                    decal = false
                    continue
                }
                // KLE labels look like "row,col" or "row,col\n\n\noption,value".
                // Only the first line carries the matrix position.
                let firstLine = label.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? label
                let parts = firstLine.split(separator: ",")
                if parts.count >= 2,
                   let row = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let col = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                   row >= 0, row < rows, col >= 0, col < cols {
                    let matrixIndex = row * cols + col
                    // Layout options can reuse the same matrix position for
                    // alternative key shapes; keep the first (default) one only.
                    if seen.insert(matrixIndex).inserted {
                        keys.append(KeyPosition(
                            id: matrixIndex,
                            row: row,
                            col: col,
                            x: x,
                            y: y,
                            width: width,
                            height: height,
                            colorHex: color
                        ))
                    }
                }
                x += width
                width = 1
                height = 1
            }
        }
        return keys
    }

    // MARK: Lighting parsing

    private static func parseLighting(root: [String: Any]) -> LightingSpec {
        // 1) V2 top-level `lighting` field (string preset or custom object).
        if let lighting = root["lighting"],
           let spec = lightingSpec(fromV2: lighting),
           spec.isSupported {
            return spec
        }

        // 2) V3 `menus` / V2 `customMenus` with built-in names or explicit commands.
        var builder = LightingBuilder()
        for key in ["menus", "customMenus"] {
            guard let menus = root[key] as? [Any] else { continue }
            for menu in menus {
                if let name = menu as? String {
                    builder.applyBuiltinPreset(name)
                } else if let dict = menu as? [String: Any] {
                    walkMenu(dict) { node in
                        guard let content = node["content"] as? [Any],
                              let identifier = content.first as? String else { return }
                        builder.applyExplicitCommand(identifier: identifier, dict: node)
                    }
                }
            }
        }
        return builder.spec
    }

    private static func lightingSpec(fromV2 value: Any) -> LightingSpec? {
        var presetName: String?
        var effects: [LightingOption]?
        var supported: [Int]?
        if let name = value as? String {
            presetName = name
        } else if let dict = value as? [String: Any] {
            presetName = dict["extends"] as? String
            let rawEffects = (dict["underglowEffects"] as? [[Any]]) ?? (dict["effects"] as? [[Any]])
            if let raw = rawEffects {
                effects = raw.enumerated().compactMap { index, entry in
                    guard let label = entry.first as? String else { return nil }
                    return LightingOption(value: index, name: label)
                }
            }
            if let raw = dict["supportedLightingValues"] as? [Any] {
                supported = raw.compactMap { intValue($0) }
            }
        }
        guard let preset = presetName else { return nil }
        let values = supported ?? []

        switch preset {
        case "none":
            return LightingSpec.none
        case "qmk_backlight":
            return LightingSpec(
                channel: 1,
                label: "Backlight",
                hasBrightness: values.isEmpty || values.contains(9),
                brightnessRange: 0...255,
                hasEffect: values.isEmpty || values.contains(10),
                effects: effects ?? [LightingOption(value: 0, name: "Off"), LightingOption(value: 1, name: "On")],
                hasSpeed: false,
                speedRange: 0...0,
                hasColor: false
            )
        case "qmk_rgblight", "qmk_backlight_rgblight":
            return LightingSpec(
                channel: 2,
                label: "RGB Light",
                hasBrightness: values.isEmpty || values.contains(128),
                brightnessRange: 0...255,
                hasEffect: values.isEmpty || values.contains(129),
                effects: effects ?? standardRGBLightEffects,
                hasSpeed: values.contains(130),
                speedRange: 0...4,
                hasColor: values.contains(131)
            )
        default:
            // wt_* / vendor presets use custom commands; not supported generically.
            return LightingSpec.none
        }
    }

    private static func walkMenu(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values {
                walkMenu(value, visit: visit)
            }
        } else if let array = node as? [Any] {
            for value in array {
                walkMenu(value, visit: visit)
            }
        }
    }

    // MARK: Value helpers

    private static func numberValue(_ any: Any?) -> Double? {
        if let double = any as? Double { return double }
        if let int = any as? Int { return Double(int) }
        if let number = any as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let double = any as? Double { return Int(double) }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func hexString(_ any: Any?) -> String? {
        if let text = any as? String {
            var value = text.trimmingCharacters(in: .whitespaces)
            if value.lowercased().hasPrefix("0x") { value = String(value.dropFirst(2)) }
            if let number = UInt32(value, radix: 16) {
                return String(format: "0x%04X", number & 0xFFFF)
            }
            return nil
        }
        if let number = any as? NSNumber {
            return String(format: "0x%04X", number.uint32Value & 0xFFFF)
        }
        return nil
    }

    private static let standardRGBLightEffects: [LightingOption] = [
        "All Off", "Solid Color", "Breathing 1", "Breathing 2", "Breathing 3", "Breathing 4",
        "Rainbow Mood 1", "Rainbow Mood 2", "Rainbow Mood 3", "Rainbow Swirl 1", "Rainbow Swirl 2",
        "Rainbow Swirl 3", "Rainbow Swirl 4", "Rainbow Swirl 5", "Rainbow Swirl 6", "Snake 1",
        "Snake 2", "Snake 3", "Snake 4", "Snake 5", "Snake 6", "Knight 1", "Knight 2",
        "Knight 3", "Christmas", "Gradient 1", "Gradient 2", "Gradient 3", "Gradient 4",
        "Gradient 5", "Gradient 6", "Gradient 7", "Gradient 8", "Gradient 9", "Gradient 10",
        "RGB Test", "Alternating",
    ].enumerated().map { LightingOption(value: $0.offset, name: $0.element) }
}

// MARK: - Lighting builder

private struct LightingBuilder {
    var channel = 0
    var label = ""
    var hasBrightness = false
    var brightnessRange: ClosedRange<Int> = 0...255
    var hasEffect = false
    var effects: [LightingOption] = []
    var hasSpeed = false
    var speedRange: ClosedRange<Int> = 0...4
    var hasColor = false

    var spec: LightingSpec {
        guard channel > 0 else { return .none }
        return LightingSpec(
            channel: channel,
            label: label.isEmpty ? "Lighting" : label,
            hasBrightness: hasBrightness,
            brightnessRange: brightnessRange,
            hasEffect: hasEffect,
            effects: effects,
            hasSpeed: hasSpeed,
            speedRange: speedRange,
            hasColor: hasColor
        )
    }

    mutating func upgradeChannel(_ newChannel: Int, label newLabel: String) {
        if newChannel >= channel {
            channel = newChannel
            label = newLabel
        }
    }

    mutating func applyBuiltinPreset(_ name: String) {
        switch name {
        case "qmk_rgb_matrix":
            upgradeChannel(3, label: "RGB Matrix")
            hasBrightness = true
            brightnessRange = 0...255
            hasSpeed = true
            speedRange = 0...4
            hasColor = true
            // Built-in menu doesn't expose a portable effect table here;
            // brightness/speed/color remain editable without touching effect.
            hasEffect = false
            effects = []
        case "qmk_rgblight":
            upgradeChannel(2, label: "RGB Light")
            hasBrightness = true
            brightnessRange = 0...255
            hasEffect = true
            effects = KeyboardDefinition.standardRGBLightEffectsSnapshot
            hasSpeed = true
            speedRange = 0...4
            hasColor = true
        case "qmk_backlight":
            upgradeChannel(1, label: "Backlight")
            hasBrightness = true
            brightnessRange = 0...255
            hasEffect = true
            effects = [LightingOption(value: 0, name: "Off"), LightingOption(value: 1, name: "On")]
        case "qmk_backlight_rgblight":
            upgradeChannel(2, label: "RGB Light")
            hasBrightness = true
            brightnessRange = 0...255
            hasEffect = true
            effects = KeyboardDefinition.standardRGBLightEffectsSnapshot
            hasSpeed = true
            speedRange = 0...4
            hasColor = true
        default:
            break
        }
    }

    mutating func applyExplicitCommand(identifier: String, dict: [String: Any]) {
        let channelPrefixes: [(String, Int, String)] = [
            ("id_qmk_rgb_matrix_", 3, "RGB Matrix"),
            ("id_qmk_rgblight_", 2, "RGB Light"),
            ("id_qmk_backlight_", 1, "Backlight"),
        ]
        guard let match = channelPrefixes.first(where: { identifier.hasPrefix($0.0) }) else { return }
        upgradeChannel(match.1, label: match.2)
        let suffix = String(identifier.dropFirst(match.0.count))

        switch suffix {
        case "brightness":
            hasBrightness = true
            if let range = LightingBuilder.range(from: dict["options"]) { brightnessRange = range }
        case "effect":
            hasEffect = true
            if let options = dict["options"] as? [[Any]] {
                effects = options.compactMap { entry in
                    guard entry.count >= 2,
                          let name = entry[0] as? String,
                          let value = (entry[1] as? NSNumber)?.intValue ?? (entry[1] as? Int) else { return nil }
                    return LightingOption(
                        value: value,
                        name: name.replacingOccurrences(of: "_MODE", with: "").capitalized
                    )
                }
            }
        case "effect_speed":
            hasSpeed = true
            if let range = LightingBuilder.range(from: dict["options"]) { speedRange = range }
        case "color":
            hasColor = true
        default:
            break
        }
    }

    static func range(from any: Any?) -> ClosedRange<Int>? {
        guard let values = any as? [Any], values.count >= 2 else { return nil }
        func int(_ value: Any) -> Int? {
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }
        guard let low = int(values[0]), let high = int(values[1]) else { return nil }
        return low...max(low, high)
    }
}

extension KeyboardDefinition {
    /// Shared RGB Light effect table (used before KeyboardDefinition is initialized).
    static let standardRGBLightEffectsSnapshot: [LightingOption] = [
        "All Off", "Solid Color", "Breathing 1", "Breathing 2", "Breathing 3", "Breathing 4",
        "Rainbow Mood 1", "Rainbow Mood 2", "Rainbow Mood 3", "Rainbow Swirl 1", "Rainbow Swirl 2",
        "Rainbow Swirl 3", "Rainbow Swirl 4", "Rainbow Swirl 5", "Rainbow Swirl 6", "Snake 1",
        "Snake 2", "Snake 3", "Snake 4", "Snake 5", "Snake 6", "Knight 1", "Knight 2",
        "Knight 3", "Christmas", "Gradient 1", "Gradient 2", "Gradient 3", "Gradient 4",
        "Gradient 5", "Gradient 6", "Gradient 7", "Gradient 8", "Gradient 9", "Gradient 10",
        "RGB Test", "Alternating",
    ].enumerated().map { LightingOption(value: $0.offset, name: $0.element) }
}
