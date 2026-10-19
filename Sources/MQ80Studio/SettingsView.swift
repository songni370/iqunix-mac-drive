import SwiftUI
import AppKit

// MARK: - Settings page

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                permissionCard
                definitionsCard
                HStack(alignment: .top, spacing: 14) {
                    deviceCard
                    storageCard
                }
                diagnosticsCard
                aboutCard
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Permission

    private var permissionCard: some View {
        StudioCard(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.permissionDenied ? Studio.warningSoft : Studio.successSoft)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(model.permissionDenied ? Studio.warning : Studio.success)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("输入监控权限")
                            .font(.studio(13, weight: .semibold))
                            .foregroundColor(Studio.ink)
                        permissionTag
                    }
                    Text("IQUNIX-DRIVE 通过 IOKit Raw HID 访问键盘。macOS 要求在「系统设置 → 隐私与安全性 → 输入监控」中授权，未授权时能看到界面但无法连接键盘。")
                        .font(.studio(11.5))
                        .foregroundColor(Studio.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("首次授权后需要完全退出并重新打开 App 才会生效。App 不会记录你的按键，也不会联网。")
                        .font(.studio(10.5))
                        .foregroundColor(Studio.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        model.openInputMonitoringSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Button {
                        model.retryConnection()
                    } label: {
                        Label("重新检测", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    private var permissionTag: some View {
        if model.permissionDenied {
            return StudioTag(text: "未授权", color: Studio.warning, background: Studio.warningSoft, icon: "exclamationmark.triangle")
        }
        if model.isConnected {
            return StudioTag(text: "已授权", color: Studio.success, background: Studio.successSoft, icon: "checkmark")
        }
        return StudioTag(text: "待验证", color: Studio.inkSecondary, background: Studio.panelMuted, icon: "questionmark.circle")
    }

    // MARK: Definition library

    private var definitionsCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("键盘定义")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    StudioTag(text: model.definitionLibrarySummary, mono: true)
                }

                if model.hasResolvedDefinition {
                    VStack(spacing: 8) {
                        infoRow("当前定义", model.definition.name)
                        infoRow("来源", model.definitionSource?.title ?? "—")
                        infoRow("矩阵 / 键位", "\(model.definition.rows) × \(model.definition.cols) / \(model.definition.keys.count) 键")
                        infoRow("灯效控制", model.definition.lighting.isSupported ? "\(model.definition.lighting.label) · CH\(model.definition.lighting.channel)" : "未声明")
                    }
                    if !model.definition.layoutOptionLabels.isEmpty {
                        Text("该定义包含布局选项（\(model.definition.layoutOptionLabels.count) 组，如分体空格/ISO Enter）。当前版本按默认布局显示与编辑，键位写入不受影响。")
                            .font(.studio(10))
                            .foregroundColor(Studio.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.definition.hasEncoders {
                        Text("该键盘带编码器（旋钮）。当前版本暂不支持编码器映射编辑。")
                            .font(.studio(10))
                            .foregroundColor(Studio.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(model.needsDefinition
                         ? "已识别到键盘，但缺少匹配的键盘定义。导入该键盘的 VIA JSON 定义后即可编辑。"
                         : "连接键盘后会自动匹配内置 VIA 定义库（1484 个）或你导入的定义。")
                        .font(.studio(11))
                        .foregroundColor(Studio.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !model.devices.isEmpty {
                    HStack(spacing: 8) {
                        Text("检测到的设备")
                            .font(.studio(10.5))
                            .foregroundColor(Studio.inkTertiary)
                        Picker("", selection: Binding(
                            get: { model.selectedDevice?.id ?? model.devices.first?.id ?? "" },
                            set: { id in
                                if let device = model.devices.first(where: { $0.id == id }) {
                                    model.selectDevice(device)
                                }
                            }
                        )) {
                            ForEach(model.devices) { device in
                                Text(device.displayName).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        importDefinitionPanel()
                    } label: {
                        Label("导入键盘定义…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Button {
                        model.openDefinitionsFolder()
                    } label: {
                        Label("打开定义目录", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Button {
                        model.reloadDefinitionLibrary()
                    } label: {
                        Label("重新加载", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Spacer()
                }

                Text("支持 VIA 协议 9–13 的键盘；内置定义来自 the-via/keyboards（GPL-3.0）。用户导入的定义保存在 Application Support/IQUNIX-DRIVE/Definitions。")
                    .font(.studio(9.5))
                    .foregroundColor(Studio.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func importDefinitionPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择该键盘的 VIA 键盘定义 JSON"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importDefinition(from: url)
    }

    // MARK: Device

    private var deviceCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("设备信息")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    StudioTag(
                        text: model.isConnected ? "在线" : (model.isPresent ? "已插入" : "未连接"),
                        color: model.isConnected ? Studio.success : Studio.inkTertiary,
                        background: model.isConnected ? Studio.successSoft : Studio.panelMuted
                    )
                }

                if let info = model.deviceInfo {
                    VStack(spacing: 8) {
                        infoRow("名称", info.displayName)
                        infoRow("协议版本", "VIA \(info.protocolVersion)")
                        infoRow("可用层数", "\(info.layerCount) 层")
                        infoRow("键位矩阵", "\(info.rows) × \(info.cols)")
                        infoRow("VID / PID", String(format: "0x%04X / 0x%04X", info.vendorID, info.productID))
                        infoRow("连接模式", info.isUSB ? "USB 有线" : "USB")
                        infoRow("键盘定义", model.activeDefinitionName)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("尚未连接键盘")
                            .font(.studio(11.5, weight: .medium))
                            .foregroundColor(Studio.inkSecondary)
                        Text("连接后这里会显示协议版本、层数与矩阵信息。")
                            .font(.studio(10.5))
                            .foregroundColor(Studio.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.studio(10.5))
                .foregroundColor(Studio.inkTertiary)
            Spacer()
            Text(value)
                .font(.studio(11, weight: .medium))
                .foregroundColor(Studio.ink)
                .lineLimit(1)
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("备份目录")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    StudioTag(text: "\(model.backups.count) 个备份", mono: true)
                }

                Text(model.backupDirectory.path)
                    .font(.studioMono(10))
                    .foregroundColor(Studio.inkSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Studio.panelMuted)
                    )

                Text("每次会话的首次写入前自动备份一次；恢复备份前也会自动备份当前配置。所有文件都是可读的 JSON。")
                    .font(.studio(10))
                    .foregroundColor(Studio.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        model.openBackupFolder()
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Diagnostics

    private var diagnosticsCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("诊断日志")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    Text("\(model.log.count) 条")
                        .font(.studioMono(9.5))
                        .foregroundColor(Studio.inkTertiary)
                    Toggle("记录调试日志", isOn: $model.debugLoggingEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.studio(11))
                    Button("清空") {
                        model.clearLog()
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                }

                logConsole

                Text("开启后会记录连接、读取、写入与灯效操作，便于排查协议问题；日志只保存在内存中。")
                    .font(.studio(10))
                    .foregroundColor(Studio.inkTertiary)
            }
        }
    }

    private var logConsole: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0x16181C))

            if model.log.isEmpty {
                Text("暂无日志")
                    .font(.studioMono(10))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.log.reversed())) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(StudioFormat.clock.string(from: entry.date))
                                    .foregroundColor(Studio.brassBright.opacity(0.9))
                                Text(entry.category)
                                    .foregroundColor(Color.white.opacity(0.42))
                                Text(entry.message)
                                    .foregroundColor(Color.white.opacity(0.78))
                                Spacer(minLength: 0)
                            }
                            .font(.studioMono(9.5))
                            .lineLimit(2)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 190)
        .textSelection(.enabled)
    }

    // MARK: About

    private var aboutCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Studio.brassBright, Studio.brass],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Image(systemName: "keyboard")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: 0x201D17))
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("IQUNIX-DRIVE")
                            .font(.studio(15, weight: .semibold))
                            .foregroundColor(Studio.ink)
                        Text("版本 \(AppConstants.appVersion) · 完全离线 · 通用 VIA 键盘配置工具")
                            .font(.studio(10.5))
                            .foregroundColor(Studio.inkTertiary)
                    }
                    Spacer()
                    StudioTag(text: "VIA 11", mono: true)
                }

                Text("一个通用的 macOS 原生 VIA 键盘配置工具：自动识别 VIA Raw HID 键盘并匹配键盘定义，读写键位与灯效。MQ80 使用内置定义与专用写入兼容路径；其他键盘使用内置 VIA 定义库（1,484 个）或导入定义。所有写操作都会回读校验，写入前自动备份；不进行固件升级，也不会跳到 Bootloader。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                StudioDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("IQUNIX MQ80 快捷键（其他键盘以厂商说明为准）")
                        .font(.studio(11, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)

                    shortcutRow(keys: ["Fn", "5"], description: "切换到 USB 有线模式（配置请使用该模式）")
                    shortcutRow(keys: ["Fn", "4"], description: "切换到 2.4G 无线模式")
                    shortcutRow(keys: ["Fn", "B"], description: "显示电池电量")
                }

                StudioDivider()

                HStack(spacing: 16) {
                    Label("本地运行，无网络请求", systemImage: "lock.shield")
                    Label("写入后自动回读校验", systemImage: "checkmark.seal")
                }
                .font(.studio(10))
                .foregroundColor(Studio.inkTertiary)
            }
        }
    }

    private func shortcutRow(keys: [String], description: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Studio.keycapLegend)
                        .padding(.horizontal, 5)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Studio.keycapDefault)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            Text(description)
                .font(.studio(10.5))
                .foregroundColor(Studio.inkSecondary)
            Spacer()
        }
    }
}
