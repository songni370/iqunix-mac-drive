import SwiftUI
import AppKit

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @StudioState private var section: StudioSection = RootView.initialSection

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section)
            VStack(spacing: 0) {
                TopBarView(section: section)
                connectionBanners
                page
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Studio.canvas)
        }
        .frame(minWidth: 1060, minHeight: 720)
        .background(Studio.canvas)
        .ignoresSafeArea()
        .onAppear {
            model.start()
            // QA hook: auto-select a matrix position for screenshot / UI smoke tests.
            if let raw = ProcessInfo.processInfo.environment["MQ80STUDIO_SELECT_KEY"], let index = Int(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    model.selectKey(index)
                }
            }
        }
        .overlay(alignment: .top) {
            toastView
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    static var initialSection: StudioSection {
        switch ProcessInfo.processInfo.environment["MQ80STUDIO_SECTION"] {
        case "lighting": return .lighting
        case "backups": return .backups
        case "settings": return .settings
        default: return .keyboard
        }
    }

    // MARK: Page

    @ViewBuilder
    private var page: some View {
        switch section {
        case .keyboard:
            KeyboardView()
        case .lighting:
            LightingView()
        case .backups:
            BackupView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: Banners

    @ViewBuilder
    private var connectionBanners: some View {
        if case .permissionDenied = model.status {
            StudioBanner(
                tone: .permission,
                title: "需要「输入监控」权限",
                message: "macOS 要求 App 获得输入监控权限才能访问键盘的 Raw HID 接口。请在系统设置中勾选 IQUNIX-DRIVE，然后完全退出并重新打开 App。",
                primaryTitle: "打开输入监控设置",
                primaryAction: { model.openInputMonitoringSettings() },
                secondaryTitle: "已授权，重新检测",
                secondaryAction: { model.retryConnection() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        } else if model.needsDefinition {
            StudioBanner(
                tone: .info,
                title: "已识别到可配置键盘，但缺少它的定义",
                message: "\(model.selectedDevice?.displayName ?? "键盘") 已通过 VIA Raw HID 识别（\(model.selectedDevice?.vendorHex ?? "")/\(model.selectedDevice?.productHex ?? "")）。导入该键盘的 VIA JSON 定义，或等待内置定义库匹配。",
                primaryTitle: "导入键盘定义…",
                primaryAction: { importDefinitionPanel() },
                secondaryTitle: "打开定义目录",
                secondaryAction: { model.openDefinitionsFolder() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        } else if case .failed(let message) = model.status {
            StudioBanner(
                tone: .error,
                title: "无法连接键盘",
                message: message,
                primaryTitle: "重试连接",
                primaryAction: { model.retryConnection() },
                secondaryTitle: "打开输入监控设置",
                secondaryAction: { model.openInputMonitoringSettings() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            HStack(spacing: 9) {
                Image(systemName: toastIcon(toast.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(toastColor(toast.kind))
                Text(toast.message)
                    .font(.studio(12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.94))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: 0x23272D))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
            .padding(.top, 78)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.18), value: model.toast)
        }
    }

    private func importDefinitionPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择这个键盘的 VIA 键盘定义 JSON（包含 vendorId / productId / matrix / layouts）"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importDefinition(from: url)
    }

    private func toastIcon(_ kind: StudioToast.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func toastColor(_ kind: StudioToast.Kind) -> Color {
        switch kind {
        case .success: return Studio.brassBright
        case .info: return Color(hex: 0x7FB2E0)
        case .error: return Color(hex: 0xE69282)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Binding var section: StudioSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            nav
            Spacer(minLength: 14)
            connectionCard
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .frame(width: 226)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Studio.sidebarTop, Studio.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.30))
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Studio.brassBright, Studio.brass],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: 0x1E1A13))
            }
            .frame(width: 35, height: 35)
            .shadow(color: Studio.brass.opacity(0.35), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text("IQUNIX")
                    .font(.studioMono(15, weight: .bold))
                    .foregroundColor(Studio.sidebarText)
                Text("DRIVE")
                    .font(.studio(8, weight: .semibold))
                    .kerning(2.6)
                    .foregroundColor(Studio.brassBright)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 26)
    }

    private var nav: some View {
        VStack(spacing: 4) {
            ForEach(StudioSection.allCases) { item in
                SidebarItem(
                    section: item,
                    selected: section == item,
                    action: { section = item }
                )
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                StatusDot(color: model.status.color, size: 6)
                Text(model.status.title)
                    .font(.studio(10.5, weight: .semibold))
                    .foregroundColor(Studio.sidebarText)
                Spacer(minLength: 4)
                if model.isConnected {
                    Text("USB")
                        .font(.studioMono(7.5, weight: .bold))
                        .foregroundColor(Studio.brassBright)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
            Text(connectionDetail)
                .font(.studio(9.5))
                .foregroundColor(Studio.sidebarMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var connectionDetail: String {
        if let info = model.deviceInfo {
            return "\(info.displayName) · VIA \(info.protocolVersion) · \(info.layerCount) 层"
        }
        if model.permissionDenied {
            return "在系统设置中授予输入监控权限"
        }
        if model.isPresent {
            return "检测到设备，正在建立连接…"
        }
        return "用数据线连接，按 Fn + 5 切到 USB 模式"
    }

    private var footer: some View {
        Text("v\(AppConstants.appVersion) · 本地离线")
            .font(.studio(9))
            .foregroundColor(Studio.sidebarMuted.opacity(0.75))
            .padding(.horizontal, 6)
            .padding(.top, 12)
    }
}

struct SidebarItem: View {
    let section: StudioSection
    let selected: Bool
    let action: () -> Void

    @StudioState private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            selected
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Studio.brassBright, Studio.brass],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                : AnyShapeStyle(Color.white.opacity(hovered ? 0.09 : 0.05))
                        )
                    Image(systemName: section.icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(selected ? Color(hex: 0x1E1A13) : Studio.sidebarMuted)
                }
                .frame(width: 25, height: 25)

                Text(section.title)
                    .font(.studio(12.5, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? Studio.sidebarText : Studio.sidebarMuted)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.075) : (hovered ? Color.white.opacity(0.035) : Color.clear))
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Studio.brassBright)
                        .frame(width: 3, height: 16)
                        .offset(x: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.1)) { hovered = value }
        }
    }
}

// MARK: - Top bar

struct TopBarView: View {
    @EnvironmentObject var model: AppModel
    let section: StudioSection

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.studio(19, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text(section.subtitle)
                    .font(.studio(11))
                    .foregroundColor(Studio.inkSecondary)
            }

            Spacer(minLength: 12)

            statusPill

            if model.isConnected {
                Button {
                    model.disconnectManually()
                } label: {
                    Label("断开", systemImage: "xmark.circle")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            } else {
                Button {
                    model.retryConnection()
                } label: {
                    Label("重新检测", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(model.status == .connecting)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(Studio.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Studio.hairline)
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            if model.status == .connecting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 8, height: 8)
            } else {
                StatusDot(color: model.status.color, size: 6.5)
            }

            Text(model.status.title)
                .font(.studio(11, weight: .medium))
                .foregroundColor(Studio.inkSecondary)

            if let info = model.deviceInfo {
                Text("VIA \(info.protocolVersion)")
                    .font(.studioMono(8.5, weight: .semibold))
                    .foregroundColor(Studio.brass)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Studio.brassSoft))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Capsule().fill(Studio.panel))
        .overlay(Capsule().stroke(Studio.hairline, lineWidth: 1))
    }
}

// MARK: - Window configuration

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 1060, height: 720)
            window.backgroundColor = NSColor(Studio.canvas)
            window.tabbingMode = .disallowed
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
