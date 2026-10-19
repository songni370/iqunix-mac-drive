import Foundation

public enum VIAError: Error, LocalizedError {
    case deviceNotFound
    case permissionDenied
    case openFailed(Int32)
    case managerOpenFailed(Int32)
    case timeout(command: UInt8)
    case invalidResponse(command: UInt8, response: [UInt8])
    case unsupportedProtocol(Int)
    case protocolMismatch(expected: UInt8, got: [UInt8])
    case writeVerificationFailed(String)
    case backupCorrupted(String)
    case definitionNotFound(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未找到 IQUNIX MQ80（请用数据线连接，并切到 USB 模式 / Fn+5）"
        case .permissionDenied:
            return "没有 HID 访问权限。请在「系统设置 → 隐私与安全性 → 输入监控」中允许 MQ80 Studio"
        case .openFailed(let code):
            return String(format: "打开键盘失败（IOKit 0x%08X）", UInt32(bitPattern: code))
        case .managerOpenFailed(let code):
            return String(format: "HID 管理器初始化失败（0x%08X）", UInt32(bitPattern: code))
        case .timeout(let command):
            return String(format: "键盘应答超时（命令 0x%02X）", command)
        case .invalidResponse(let command, let response):
            return String(format: "命令 0x%02X 返回异常：%@", command, Hex.string(response))
        case .unsupportedProtocol(let version):
            return String(format: "不支持的 VIA 协议版本 0x%04X（需要 11 或更高）", version)
        case .protocolMismatch(let expected, let got):
            return String(format: "协议应答不匹配：期望 0x%02X，收到 %@", expected, Hex.string(got))
        case .writeVerificationFailed(let detail):
            return "写入校验失败：\(detail)"
        case .backupCorrupted(let detail):
            return "备份文件无效：\(detail)"
        case .definitionNotFound(let name):
            return "已识别到「\(name)」，但缺少这个键盘的 VIA 定义。请在 App 的「设置 → 键盘定义」导入该键盘的 VIA JSON 定义，或运行 iqunixctl import-definition <文件>。"
        case .notConnected:
            return "键盘未连接"
        }
    }
}

public enum Hex {
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func string<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func bytes(_ string: String) -> [UInt8]? {
        let cleaned = string.replacingOccurrences(of: "0x", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: " ", with: " ")
        let parts = cleaned.split(separator: " ").flatMap { token -> [UInt8] in
            var t = String(token)
            if t.count % 2 == 1 { t = "0" + t }
            var result: [UInt8] = []
            var idx = t.startIndex
            while idx < t.endIndex, let next = t.index(idx, offsetBy: 2, limitedBy: t.endIndex) {
                guard let byte = UInt8(t[idx..<next], radix: 16) else { return [] }
                result.append(byte)
                idx = next
            }
            return result
        }
        return parts.isEmpty ? nil : parts
    }
}

public enum AppConstants {
    // Known built-in IQUNIX MQ80 family (its firmware needs a write workaround).
    public static let mq80VendorID = 0x320F
    public static let mq80ProductID = 0x5055
    public static let mq80ReceiverProductID = 0x5088

    // VIA Raw HID interface used by all supported keyboards.
    public static let rawUsagePage = 0xFF60
    public static let rawUsage = 0x61
    public static let reportSize = 32

    public static let appName = "IQUNIX-DRIVE"
    public static let appVersion = "0.2.0"
    public static let backupFormat = 1
}

public struct VIADevice: Sendable, Equatable, Identifiable {
    public let product: String
    public let vendorID: Int
    public let productID: Int
    public let locationID: Int
    public let transport: String

    public init(product: String, vendorID: Int, productID: Int, locationID: Int, transport: String = "USB") {
        self.product = product
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.transport = transport
    }

    public var id: String {
        String(format: "%04X:%04X:%08X", vendorID, productID, locationID)
    }

    public var vendorHex: String { String(format: "0x%04X", vendorID) }
    public var productHex: String { String(format: "0x%04X", productID) }
    public var isMQ80: Bool { vendorID == AppConstants.mq80VendorID }
    public var isMQ80Receiver: Bool {
        isMQ80 && productID == AppConstants.mq80ReceiverProductID
    }

    public var displayName: String {
        if isMQ80Receiver { return "MQ80 2.4G Receiver" }
        if !product.isEmpty { return product }
        return "VIA 键盘 \(vendorHex):\(productHex)"
    }
}
