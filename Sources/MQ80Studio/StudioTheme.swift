import SwiftUI
import AppKit

// MARK: - Macro-free state wrapper
//
// 当前 CLT 的 macOS 27 SDK 把 `@State` 变成了宏（依赖未随 CLT 安装的 SwiftUIMacros
// 插件），裸 swiftc 无法展开。这里包装仍然存在的 `SwiftUI.State` 属性包装器，
// 保持与 @State 相同的语义，同时让 `scripts/build.sh` 在只有 CLT 的环境下可直接编译。

@propertyWrapper
struct StudioState<Value>: DynamicProperty {
    private var storage: SwiftUI.State<Value>

    init(wrappedValue: Value) {
        storage = SwiftUI.State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        storage.projectedValue
    }
}

// MARK: - Navigation

enum StudioSection: String, CaseIterable, Identifiable {
    case keyboard
    case lighting
    case backups
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: return "键盘映射"
        case .lighting: return "灯效"
        case .backups: return "备份"
        case .settings: return "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .keyboard: return "选择层，点击键帽修改键码"
        case .lighting: return "调整亮度、动画与颜色，确认后写入"
        case .backups: return "整套配置的备份、导出与恢复"
        case .settings: return "权限、诊断日志与设备信息"
        }
    }

    var icon: String {
        switch self {
        case .keyboard: return "keyboard"
        case .lighting: return "light.max"
        case .backups: return "externaldrive.badge.timemachine"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Palette
//
// "Machined aluminium + graphite keycaps"：深色侧栏、冷瓷色内容底、黄铜强调色。
// 所有颜色都是刻意的选择：黄铜对应键盘配重/铭牌，石墨对应键帽，冷瓷底比暖米色更克制。

enum Studio {
    // Surfaces
    static let canvas = Color(hex: 0xEDEFF2)
    static let canvasTop = Color(hex: 0xF3F5F7)
    static let panel = Color(hex: 0xFFFFFF)
    static let panelMuted = Color(hex: 0xF5F7F9)
    static let hairline = Color(hex: 0xDBDFE4)
    static let hairlineStrong = Color(hex: 0xC8CDD4)

    // Ink
    static let ink = Color(hex: 0x1F2329)
    static let inkSecondary = Color(hex: 0x69707A)
    static let inkTertiary = Color(hex: 0x9AA1AA)

    // Sidebar
    static let sidebarTop = Color(hex: 0x1C1F24)
    static let sidebarBottom = Color(hex: 0x101216)
    static let sidebarText = Color(hex: 0xE8E6E1)
    static let sidebarMuted = Color(hex: 0x8C929B)
    static let sidebarLine = Color(hex: 0x2C3037)

    // Accents
    static let brass = Color(hex: 0xB5892F)
    static let brassBright = Color(hex: 0xD3A94F)
    static let brassSoft = Color(hex: 0xF6EDD9)
    static let success = Color(hex: 0x2E7F5E)
    static let successSoft = Color(hex: 0xE4F2EB)
    static let danger = Color(hex: 0xB34A39)
    static let dangerSoft = Color(hex: 0xF8E7E3)
    static let info = Color(hex: 0x3C6E9D)
    static let infoSoft = Color(hex: 0xE5EEF6)
    static let warning = Color(hex: 0xB4701F)
    static let warningSoft = Color(hex: 0xFAEEDB)

    // Keycaps (definition colors -> graphite tones)
    static let keycapDefault = Color(hex: 0x3E434A)
    static let keycapDark = Color(hex: 0x2A2E34)
    static let keycapMid = Color(hex: 0x363B42)
    static let keycapLight = Color(hex: 0x474D55)
    static let keycapLegend = Color(hex: 0xF1F2F4)
    static let keycapLegendDim = Color(hex: 0xB9BEC5)

    static func keycapBase(for hex: String?) -> Color {
        switch hex {
        case "#777777": return keycapDark
        case "#aaaaaa": return keycapMid
        case "#cccccc": return keycapLight
        default: return keycapDefault
        }
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

extension Font {
    static func studio(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func studioMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Formatting

enum StudioFormat {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func hex(_ value: UInt16) -> String {
        String(format: "0x%04X", value)
    }

    static func bytes(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - Building blocks

struct StudioCard<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = 16
    var elevated: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Studio.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Studio.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(elevated ? 0.06 : 0), radius: 12, x: 0, y: 5)
    }
}

struct StudioDivider: View {
    var body: some View {
        Rectangle()
            .fill(Studio.hairline)
            .frame(height: 1)
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var glowing: Bool = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(color.opacity(glowing ? 0.35 : 0), lineWidth: glowing ? 4 : 0)
            )
    }
}

struct StudioTag: View {
    let text: String
    var color: Color = Studio.inkSecondary
    var background: Color = Studio.panelMuted
    var mono: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(mono ? .studioMono(10, weight: .medium) : .studio(10.5, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(background)
        )
    }
}

// MARK: - Button styles

struct BrassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.studio(12.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Studio.brassBright, Studio.brass],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Studio.brass.opacity(isEnabled ? 0.32 : 0), radius: 6, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.86 : (isEnabled ? 1 : 0.38))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var destructive: Bool = false
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.studio(compact ? 11.5 : 12.5, weight: .medium))
            .foregroundColor(destructive ? Studio.danger : Studio.ink)
            .padding(.horizontal, compact ? 10 : 13)
            .frame(height: compact ? 26 : 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Studio.panelMuted : Studio.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(destructive ? Studio.danger.opacity(0.32) : Studio.hairlineStrong, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct SubtleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.studio(11.5, weight: .medium))
            .foregroundColor(configuration.isPressed ? Studio.ink : Studio.inkSecondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Studio.panelMuted : Color.clear)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Studio.inkSecondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Studio.panelMuted : Studio.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Studio.hairline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Search field

struct StudioSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Studio.inkTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.studio(12))
                .foregroundColor(Studio.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Studio.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Studio.panelMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Studio.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Inline banners

struct StudioBanner: View {
    enum Tone {
        case permission
        case error
        case info

        var color: Color {
            switch self {
            case .permission: return Studio.warning
            case .error: return Studio.danger
            case .info: return Studio.info
            }
        }

        var background: Color {
            switch self {
            case .permission: return Studio.warningSoft
            case .error: return Studio.dangerSoft
            case .info: return Studio.infoSoft
            }
        }

        var icon: String {
            switch self {
            case .permission: return "hand.raised.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    let message: String
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tone.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.studio(12.5, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text(message)
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let secondaryTitle = secondaryTitle, let secondaryAction = secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
                if let primaryTitle = primaryTitle, let primaryAction = primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tone.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
    }
}
