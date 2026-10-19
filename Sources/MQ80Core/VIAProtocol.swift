import Foundation

// MARK: - Models

public struct DeviceInfo: Codable, Equatable, Sendable {
    public let product: String
    public let vendorID: Int
    public let productID: Int
    public let protocolVersion: Int
    public let layerCount: Int
    public let rows: Int
    public let cols: Int

    public var displayName: String {
        if productID == AppConstants.mq80ReceiverProductID { return "MQ80 2.4G Receiver" }
        return product.isEmpty ? "VIA Keyboard" : product
    }

    public var isUSB: Bool {
        productID == AppConstants.mq80ProductID || productID == AppConstants.mq80ReceiverProductID
    }
}

public struct KeyChange: Sendable, Equatable {
    public let layer: Int
    public let index: Int
    public let from: UInt16
    public let to: UInt16

    public init(layer: Int, index: Int, from: UInt16, to: UInt16) {
        self.layer = layer
        self.index = index
        self.from = from
        self.to = to
    }
}

public struct Keymap: Codable, Equatable, Sendable {
    public var layers: [[UInt16]]

    public init(layers: [[UInt16]]) {
        self.layers = layers
    }

    public var layerCount: Int { layers.count }
    public var matrixCount: Int { layers.first?.count ?? 0 }

    public func value(layer: Int, index: Int) -> UInt16 {
        guard layer >= 0, layer < layers.count, index >= 0, index < layers[layer].count else { return 0 }
        return layers[layer][index]
    }

    public mutating func setValue(_ value: UInt16, layer: Int, index: Int) {
        guard layer >= 0, layer < layers.count, index >= 0, index < layers[layer].count else { return }
        layers[layer][index] = value
    }

    public func differences(comparedTo other: Keymap) -> [KeyChange] {
        var changes: [KeyChange] = []
        let layerTotal = min(layers.count, other.layers.count)
        for layer in 0..<layerTotal {
            let count = min(layers[layer].count, other.layers[layer].count)
            for index in 0..<count where layers[layer][index] != other.layers[layer][index] {
                changes.append(KeyChange(layer: layer, index: index, from: other.layers[layer][index], to: layers[layer][index]))
            }
        }
        return changes
    }
}

public struct LightingState: Codable, Equatable, Sendable {
    public var brightness: Int
    public var effect: Int
    public var effectSpeed: Int
    public var hue: Int
    public var saturation: Int

    public init(brightness: Int, effect: Int, effectSpeed: Int, hue: Int, saturation: Int) {
        self.brightness = brightness
        self.effect = effect
        self.effectSpeed = effectSpeed
        self.hue = hue
        self.saturation = saturation
    }

    public static let zero = LightingState(brightness: 0, effect: 0, effectSpeed: 0, hue: 0, saturation: 0)
}

public struct MacrosBlob: Sendable, Codable, Equatable {
    public let count: Int
    public let bufferSize: Int
    public let data: Data

    public init(count: Int, bufferSize: Int, data: Data) {
        self.count = count
        self.bufferSize = bufferSize
        self.data = data
    }
}

// MARK: - VIA protocol

public final class VIAController {
    public let connection: VIAConnection
    public let definition: KeyboardDefinition
    public let info: DeviceInfo

    private let layerBytes: Int
    private let layerCount: Int
    /// IQUNIX MQ80 firmware has a buffer-write bug; other VIA keyboards use the
    /// standard 0x13 buffer write (much faster than the per-key fallback).
    private let needsPerKeyWrite: Bool

    public init(connection: VIAConnection, definition: KeyboardDefinition) throws {
        self.connection = connection
        self.definition = definition
        self.needsPerKeyWrite = connection.discovered.isMQ80

        let version = try Self.readProtocolVersion(connection: connection)
        guard version >= 9 else { throw VIAError.unsupportedProtocol(version) }

        let layerCount = try Self.readLayerCount(connection: connection)
        let safeLayerCount = max(1, min(layerCount, 8))
        self.layerCount = safeLayerCount
        self.layerBytes = definition.rows * definition.cols * 2
        self.info = DeviceInfo(
            product: connection.discovered.product,
            vendorID: connection.discovered.vendorID,
            productID: connection.discovered.productID,
            protocolVersion: version,
            layerCount: safeLayerCount,
            rows: definition.rows,
            cols: definition.cols
        )
    }

    public static func open(device: VIADevice? = nil, definition: KeyboardDefinition? = nil) throws -> VIAController {
        let connection = try VIAConnection(device: device)
        let resolved = definition
            ?? DefinitionStore.shared.resolve(device: connection.discovered)?.definition
        guard let resolved = resolved else {
            connection.close()
            throw VIAError.definitionNotFound(connection.discovered.displayName)
        }
        do {
            return try VIAController(connection: connection, definition: resolved)
        } catch {
            connection.close()
            throw error
        }
    }

    public func close() {
        connection.close()
    }

    // MARK: Basic commands

    private func command(_ payload: [UInt8], minimumResponseLength: Int = 2) throws -> [UInt8] {
        let response = try connection.request(payload)
        guard response.count >= minimumResponseLength else {
            throw VIAError.invalidResponse(command: payload[0], response: response)
        }
        return response
    }

    private static func readProtocolVersion(connection: VIAConnection) throws -> Int {
        let response = try connection.request([0x01])
        guard response.count >= 3, response[0] == 0x01 else {
            throw VIAError.protocolMismatch(expected: 0x01, got: response)
        }
        return (Int(response[1]) << 8) | Int(response[2])
    }

    private static func readLayerCount(connection: VIAConnection) throws -> Int {
        let response = try connection.request([0x11])
        guard response.count >= 2, response[0] == 0x11 else {
            throw VIAError.protocolMismatch(expected: 0x11, got: response)
        }
        return max(1, Int(response[1]))
    }

    // MARK: Keymap

    public func readKeymap() throws -> Keymap {
        // Read one layer at a time with chunks that never cross a layer boundary.
        // (The firmware returns 0xFF for the part of a read buffer that crosses it.)
        var layers: [[UInt16]] = []
        for layer in 0..<layerCount {
            let base = layer * layerBytes
            var raw = [UInt8]()
            raw.reserveCapacity(layerBytes)
            var offset = 0
            while offset < layerBytes {
                let size = min(28, layerBytes - offset)
                let absolute = base + offset
                let payload: [UInt8] = [0x12, UInt8((absolute >> 8) & 0xFF), UInt8(absolute & 0xFF), UInt8(size)]
                let response = try command(payload)
                guard response[0] == 0x12 else {
                    throw VIAError.protocolMismatch(expected: 0x12, got: response)
                }
                let dataLength = min(size, max(0, response.count - 4))
                raw.append(contentsOf: response[4..<(4 + dataLength)])
                offset += size
            }
            var keycodes = [UInt16]()
            keycodes.reserveCapacity(definition.rows * definition.cols)
            var index = 0
            while index + 1 < raw.count {
                keycodes.append((UInt16(raw[index]) << 8) | UInt16(raw[index + 1]))
                index += 2
            }
            layers.append(keycodes)
        }
        return Keymap(layers: layers)
    }

    public func writeKeymap(_ keymap: Keymap, verify: Bool = true, progress: ((Double) -> Void)? = nil) throws {
        if needsPerKeyWrite {
            try writeKeymapPerKey(keymap, progress: progress)
        } else {
            try writeKeymapBuffer(keymap, progress: progress)
        }
        progress?(1.0)
        if verify {
            let readBack = try readKeymap()
            if readBack.layers != keymap.layers {
                let changes = readBack.differences(comparedTo: keymap)
                let detail = changes.prefix(5)
                    .map { "L\($0.layer)#\($0.index) 期望 0x\(String(format: "%04X", $0.to)) 实际 0x\(String(format: "%04X", $0.from))" }
                    .joined(separator: "；")
                throw VIAError.writeVerificationFailed(detail.isEmpty ? "键位回读不一致" : detail)
            }
        }
    }

    /// Standard VIA path: write the flattened dynamic keymap with 0x13 in
    /// continuous 28-byte chunks (this is what the official VIA frontend does).
    private func writeKeymapBuffer(_ keymap: Keymap, progress: ((Double) -> Void)?) throws {
        var raw = [UInt8]()
        raw.reserveCapacity(layerCount * layerBytes)
        for layer in 0..<layerCount {
            let values = keymap.layers.count > layer ? keymap.layers[layer] : []
            for index in 0..<(definition.rows * definition.cols) {
                let value: UInt16 = index < values.count ? values[index] : 0
                raw.append(UInt8((value >> 8) & 0xFF))
                raw.append(UInt8(value & 0xFF))
            }
        }
        var offset = 0
        let total = raw.count
        while offset < total {
            let size = min(28, total - offset)
            var payload: [UInt8] = [0x13, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(size)]
            payload.append(contentsOf: raw[offset..<(offset + size)])
            let response = try command(payload)
            guard response[0] == 0x13 else {
                throw VIAError.protocolMismatch(expected: 0x13, got: response)
            }
            offset += size
            if let progress = progress, offset % 112 == 0 {
                progress(Double(offset) / Double(max(1, total)))
            }
        }
    }

    /// IQUNIX MQ80 firmware: 0x13 fails on layer boundaries / crossing chunks,
    /// so write one key at a time with 0x05 (verified-working on all layers).
    private func writeKeymapPerKey(_ keymap: Keymap, progress: ((Double) -> Void)?) throws {
        let total = layerCount * definition.rows * definition.cols
        var written = 0
        for layer in 0..<layerCount {
            let values = keymap.layers.count > layer ? keymap.layers[layer] : []
            for index in 0..<(definition.rows * definition.cols) {
                let value: UInt16 = index < values.count ? values[index] : 0
                let row = index / definition.cols
                let col = index % definition.cols
                let payload: [UInt8] = [
                    0x05, UInt8(layer), UInt8(row), UInt8(col),
                    UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
                ]
                let response = try command(payload)
                guard response[0] == 0x05 else {
                    throw VIAError.protocolMismatch(expected: 0x05, got: response)
                }
                written += 1
                if let progress = progress, written % 32 == 0 {
                    progress(Double(written) / Double(total))
                }
            }
        }
    }

    // MARK: Lighting (per-definition channel / values)

    public var lightingSpec: LightingSpec { definition.lighting }

    public func readLighting() throws -> LightingState {
        let spec = definition.lighting
        guard spec.isSupported else { return .zero }
        let channel = UInt8(spec.channel)
        var state = LightingState.zero

        if spec.hasBrightness {
            state.brightness = Int(try customGet(channel: channel, valueID: 1).first ?? 0)
        }
        if spec.hasEffect {
            state.effect = Int(try customGet(channel: channel, valueID: 2).first ?? 0)
        }
        if spec.hasSpeed {
            state.effectSpeed = Int(try customGet(channel: channel, valueID: 3).first ?? 0)
        }
        if spec.hasColor {
            let color = try customGet(channel: channel, valueID: 4)
            state.hue = Int(color.first ?? 0)
            state.saturation = Int(color.count > 1 ? color[1] : 0)
        }
        return state
    }

    public func applyLighting(_ state: LightingState, verify: Bool = true) throws {
        let spec = definition.lighting
        guard spec.isSupported else { return }
        let channel = UInt8(spec.channel)

        if spec.hasBrightness {
            try customSet(channel: channel, valueID: 1, values: [UInt8(clamping: state.brightness)])
        }
        if spec.hasEffect {
            try customSet(channel: channel, valueID: 2, values: [UInt8(clamping: state.effect)])
        }
        if spec.hasSpeed {
            try customSet(channel: channel, valueID: 3, values: [UInt8(clamping: state.effectSpeed)])
        }
        if spec.hasColor {
            try customSet(channel: channel, valueID: 4, values: [UInt8(clamping: state.hue), UInt8(clamping: state.saturation)])
        }
        try customSave(channel: channel)

        if verify {
            let readBack = try readLighting()
            if !lightingMatches(readBack, state, spec: spec) {
                throw VIAError.writeVerificationFailed(
                    "灯效回读不一致：期望 \(state.brightness)/\(state.effect)/\(state.effectSpeed)/\(state.hue)/\(state.saturation)，" +
                    "实际 \(readBack.brightness)/\(readBack.effect)/\(readBack.effectSpeed)/\(readBack.hue)/\(readBack.saturation)"
                )
            }
        }
    }

    private func lightingMatches(_ lhs: LightingState, _ rhs: LightingState, spec: LightingSpec) -> Bool {
        if spec.hasBrightness && lhs.brightness != rhs.brightness { return false }
        if spec.hasEffect && lhs.effect != rhs.effect { return false }
        if spec.hasSpeed && lhs.effectSpeed != rhs.effectSpeed { return false }
        if spec.hasColor && (lhs.hue != rhs.hue || lhs.saturation != rhs.saturation) { return false }
        return true
    }

    private func customGet(channel: UInt8, valueID: UInt8) throws -> [UInt8] {
        let response = try command([0x08, channel, valueID, 0x00], minimumResponseLength: 4)
        guard response[0] == 0x08 else {
            throw VIAError.protocolMismatch(expected: 0x08, got: response)
        }
        return Array(response[3...])
    }

    private func customSet(channel: UInt8, valueID: UInt8, values: [UInt8]) throws {
        let payload: [UInt8] = [0x07, channel, valueID] + values
        let response = try command(payload)
        guard response[0] == 0x07 else {
            throw VIAError.protocolMismatch(expected: 0x07, got: response)
        }
    }

    private func customSave(channel: UInt8) throws {
        let response = try command([0x09, channel])
        guard response[0] == 0x09 else {
            throw VIAError.protocolMismatch(expected: 0x09, got: response)
        }
    }

    // MARK: Macros (read-only for now)

    public func readMacros() throws -> MacrosBlob? {
        let countResponse = try command([0x0C])
        guard countResponse[0] == 0x0C else { return nil }
        let count = Int(countResponse[1])

        let sizeResponse = try command([0x0D])
        guard sizeResponse[0] == 0x0D, sizeResponse.count >= 3 else { return nil }
        let bufferSize = (Int(sizeResponse[1]) << 8) | Int(sizeResponse[2])
        guard bufferSize > 0, bufferSize <= 4096 else { return nil }

        var data = Data()
        var offset = 0
        while offset < bufferSize {
            let size = min(28, bufferSize - offset)
            let response = try command([0x0E, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(size)], minimumResponseLength: 4)
            guard response[0] == 0x0E else { break }
            let available = min(size, max(0, response.count - 4))
            data.append(contentsOf: response[4..<(4 + available)])
            offset += size
        }
        return MacrosBlob(count: count, bufferSize: bufferSize, data: data)
    }
}

// MARK: - Convenience

public enum VIAService {
    public static func isPresent() -> Bool {
        !VIADiscovery.find().isEmpty
    }

    public static func withController<T>(
        device: VIADevice? = nil,
        definition: KeyboardDefinition? = nil,
        _ body: (VIAController) throws -> T
    ) throws -> T {
        let controller = try VIAController.open(device: device, definition: definition)
        defer { controller.close() }
        return try body(controller)
    }
}
