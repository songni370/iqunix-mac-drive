import SwiftUI
import AppKit

// MARK: - Keyboard page

struct KeyboardView: View {
    @EnvironmentObject var model: AppModel
    @StudioState private var showKeycodePicker = false

    var body: some View {
        VStack(spacing: 14) {
            if model.isConnected {
                header
                if let error = model.writeError {
                    StudioBanner(
                        tone: .error,
                        title: "写入失败",
                        message: error,
                        primaryTitle: "重试写入",
                        primaryAction: { model.retryWrite() },
                        secondaryTitle: "关闭",
                        secondaryAction: { model.dismissWriteError() }
                    )
                }
                HStack(alignment: .top, spacing: 14) {
                    layoutCard
                    KeyInspectorCard(showPicker: $showKeycodePicker)
                        .frame(width: 300)
                }
                deviceStrip
            } else {
                KeyboardEmptyState()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showKeycodePicker) {
            KeycodePicker(
                currentValue: model.selectedKeyDetails?.value ?? 0,
                onPick: { value in
                    model.setKeycode(value)
                    showKeycodePicker = false
                },
                onCancel: { showKeycodePicker = false }
            )
            .environmentObject(model)
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["MQ80STUDIO_OPEN_PICKER"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showKeycodePicker = true
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            LayerSegmentedControl()
            if model.unsavedCount > 0 {
                StudioTag(
                    text: "未保存修改 \(model.unsavedCount) 处",
                    color: Studio.warning,
                    background: Studio.warningSoft,
                    icon: "pencil"
                )
            }
            Spacer(minLength: 8)
            Button("放弃修改") {
                model.discardChanges()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.unsavedCount == 0 || model.isWriting)

            Button {
                model.writeStagedKeymap()
            } label: {
                Label(model.isWriting ? "正在写入…" : "写入键盘", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(BrassButtonStyle())
            .disabled(model.unsavedCount == 0 || model.isWriting)
        }
    }

    // MARK: Layout card

    private var layoutCard: some View {
        StudioCard(padding: 12) {
            VStack(spacing: 0) {
                KeyboardLayoutView(
                    layer: model.selectedLayer,
                    selectedKeyID: model.selectedKeyID,
                    onSelect: { id in model.selectKey(id) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 10) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Studio.inkTertiary)
                    Text("点击键帽查看与修改键码")
                        .font(.studio(10.5))
                        .foregroundColor(Studio.inkTertiary)
                    if model.selectedLayer > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Studio.brassBright)
                                .frame(width: 5, height: 5)
                            Text("与基础层不同")
                                .font(.studio(10.5))
                                .foregroundColor(Studio.inkTertiary)
                        }
                        .padding(.leading, 4)
                    }
                    Spacer()
                    Button {
                        model.resetCurrentLayer()
                    } label: {
                        Label("重置本层", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.isWriting {
                HStack(spacing: 12) {
                    ProgressView(value: model.writeProgress)
                        .progressViewStyle(.linear)
                        .tint(Studio.brassBright)
                        .frame(width: 170)
                    Text("正在写入键盘 \(Int(model.writeProgress * 100))%")
                        .font(.studioMono(10.5, weight: .semibold))
                        .foregroundColor(Studio.sidebarText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0x24282E))
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                )
                .padding(.bottom, 56)
                .transition(.opacity)
            }
        }
    }

    // MARK: Device strip

    private var deviceStrip: some View {
        StudioCard(padding: 0, elevated: false) {
            HStack(spacing: 0) {
                DeviceMetric(icon: "number", title: "协议版本", value: "VIA \(model.deviceInfo?.protocolVersion ?? 0)")
                stripDivider
                DeviceMetric(icon: "square.stack.3d.up", title: "可用层数", value: "\(model.layerCount) 层")
                stripDivider
                DeviceMetric(
                    icon: "square.grid.3x3",
                    title: "键位矩阵",
                    value: "\(model.deviceInfo?.rows ?? 0) × \(model.deviceInfo?.cols ?? 0)"
                )
                stripDivider
                DeviceMetric(
                    icon: "bolt.horizontal",
                    title: "连接模式",
                    value: (model.deviceInfo?.isUSB ?? false) ? "USB 有线" : "2.4G 接收器"
                )
            }
            .frame(height: 56)
        }
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Studio.hairline)
            .frame(width: 1, height: 28)
    }
}

// MARK: - Layer segmented control

struct LayerSegmentedControl: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.layerNumbers, id: \.self) { layer in
                layerButton(layer)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Studio.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Studio.hairline, lineWidth: 1)
        )
    }

    private func layerButton(_ layer: Int) -> some View {
        let selected = model.selectedLayer == layer
        let changed = model.unsavedChanges.contains { $0.layer == layer }
        return Button {
            model.selectLayer(layer)
        } label: {
            HStack(spacing: 5) {
                Text(model.layerName(layer))
                    .font(.studio(12, weight: selected ? .semibold : .medium))
                if changed {
                    Circle()
                        .fill(selected ? Color.white.opacity(0.9) : Studio.brass)
                        .frame(width: 4.5, height: 4.5)
                }
            }
            .foregroundColor(selected ? .white : Studio.inkSecondary)
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        selected
                            ? LinearGradient(
                                colors: [Studio.brassBright, Studio.brass],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device metric

struct DeviceMetric: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Studio.brass)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.studio(9.5, weight: .medium))
                    .foregroundColor(Studio.inkTertiary)
                Text(value)
                    .font(.studio(11.5, weight: .semibold))
                    .foregroundColor(Studio.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Inspector

struct KeyInspectorCard: View {
    @EnvironmentObject var model: AppModel
    @Binding var showPicker: Bool

    var body: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("按键检查器")
                        .font(.studio(11.5, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    if let details = model.selectedKeyDetails {
                        StudioTag(text: "R\(details.position.row) C\(details.position.col)", mono: true)
                    }
                }

                if let details = model.selectedKeyDetails {
                    inspectorBody(details)
                } else {
                    emptyInspector
                }

                Spacer(minLength: 6)
                StudioDivider()
                HStack {
                    Button {
                        model.resetCurrentLayer()
                    } label: {
                        Label("整层重置", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(model.unsavedCount == 0)
                    Spacer()
                    Text(model.layerName(model.selectedLayer))
                        .font(.studioMono(9.5, weight: .semibold))
                        .foregroundColor(Studio.inkTertiary)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func inspectorBody(_ details: SelectedKeyDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                KeycapFace(
                    label: details.value == 0 ? "无" : details.label,
                    base: Studio.keycapBase(for: details.position.colorHex),
                    legend: details.value == 0 ? Studio.keycapLegendDim : Studio.keycapLegend,
                    fontSize: 15,
                    selected: true
                )
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(details.value == 0 ? "未分配" : details.label)
                        .font(.studio(17, weight: .semibold))
                        .foregroundColor(Studio.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(details.code ?? "KC_NO")
                        .font(.studioMono(10.5))
                        .foregroundColor(Studio.inkSecondary)
                    StudioTag(text: details.hex, mono: true)
                }
            }

            StudioDivider()

            VStack(spacing: 9) {
                infoRow("矩阵位置", "行 \(details.position.row) · 列 \(details.position.col)")
                infoRow("矩阵索引", "#\(details.index)")
                infoRow("当前键码", "\(details.label)  \(details.hex)")
                infoRow("原键码", "\(model.label(for: details.originalValue))  \(StudioFormat.hex(details.originalValue))")
            }

            VStack(spacing: 8) {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Spacer()
                        Label("更改键码…", systemImage: "square.grid.2x2")
                        Spacer()
                    }
                }
                .buttonStyle(BrassButtonStyle())

                Button {
                    model.restoreSelectedKey()
                } label: {
                    HStack {
                        Spacer()
                        Label("恢复此键", systemImage: "arrow.counterclockwise")
                        Spacer()
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(details.value == details.originalValue)
            }
        }
    }

    private var emptyInspector: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Studio.panelMuted)
                    .frame(width: 66, height: 66)
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Studio.inkTertiary)
            }
            Text("选择一个按键")
                .font(.studio(13, weight: .semibold))
                .foregroundColor(Studio.ink)
            Text("点击左侧键盘上的键帽，可以查看矩阵位置并更改它在这一层的键码。")
                .font(.studio(11))
                .foregroundColor(Studio.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.studio(10.5, weight: .medium))
                .foregroundColor(Studio.inkTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.studio(11, weight: .medium))
                .foregroundColor(Studio.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Empty state

struct KeyboardEmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            KeyboardLayoutView(
                layer: 0,
                silhouette: true,
                interactive: false,
                selectedKeyID: nil,
                onSelect: { _ in }
            )
            .opacity(0.55)
            .padding(26)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(model.needsDefinition ? Studio.infoSoft : Studio.brassSoft)
                        .frame(width: 54, height: 54)
                    Image(systemName: model.needsDefinition ? "doc.badge.gearshape" : "keyboard")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundColor(model.needsDefinition ? Studio.info : Studio.brass)
                }

                if model.needsDefinition {
                    needsDefinitionContent
                } else {
                    waitingContent
                }
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 30)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Studio.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Studio.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Waiting for a keyboard

    private var waitingContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text("连接你的键盘")
                    .font(.studio(22, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text(model.isPresent ? "已检测到键盘，正在建立连接。" : "用数据线连接任意支持 VIA 的键盘，自动识别后会读取配置。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)

            VStack(spacing: 10) {
                ConnectionStep(number: 1, text: "用 USB 数据线连接键盘与 Mac")
                ConnectionStep(number: 2, text: "切换到有线模式（IQUNIX MQ80：Fn + 5；其他键盘按厂商说明）")
                ConnectionStep(number: 3, text: "首次运行在「输入监控」中授权，然后重新打开 App")
                ConnectionStep(number: 4, text: "自动识别 VIA Raw HID 配置接口，并按内置定义库匹配键盘")
            }
            .padding(.top, 2)

            HStack(spacing: 9) {
                Button {
                    model.retryConnection()
                } label: {
                    Label("重新检测", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(BrassButtonStyle())

                Button("打开输入监控设置") {
                    model.openInputMonitoringSettings()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 2)

            HStack(spacing: 6) {
                StatusDot(color: model.status.color, size: 6)
                Text("当前状态：\(model.status.title)")
                    .font(.studio(10.5))
                    .foregroundColor(Studio.inkTertiary)
            }
        }
    }

    // MARK: Needs a definition

    private var needsDefinitionContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                Text("需要这个键盘的定义")
                    .font(.studio(20, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("已识别到 \(model.selectedDevice?.displayName ?? "VIA 键盘")（\(model.selectedDevice?.vendorHex ?? "") / \(model.selectedDevice?.productHex ?? "")），但内置定义库没有匹配项。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("解决办法")
                    .font(.studio(10.5, weight: .semibold))
                    .foregroundColor(Studio.inkTertiary)
                Text("导入该键盘的 VIA JSON 定义（厂商提供，或在 VIA 键盘库中找到）。导入后会自动连接到当前键盘。")
                    .font(.studio(11))
                    .foregroundColor(Studio.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("内置定义库：\(model.definitionLibrarySummary)")
                    .font(.studioMono(10))
                    .foregroundColor(Studio.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Studio.panelMuted)
            )

            HStack(spacing: 9) {
                Button {
                    importDefinitionPanel()
                } label: {
                    Label("导入键盘定义…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(BrassButtonStyle())

                Button("打开定义目录") {
                    model.openDefinitionsFolder()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    model.reloadDefinitionLibrary()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .help("重新加载定义库")
            }

            HStack(spacing: 6) {
                StatusDot(color: model.status.color, size: 6)
                Text("当前状态：\(model.status.title)")
                    .font(.studio(10.5))
                    .foregroundColor(Studio.inkTertiary)
            }
        }
    }

    private func importDefinitionPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择这个键盘的 VIA 键盘定义 JSON"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importDefinition(from: url)
    }
}

struct ConnectionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.studioMono(9.5, weight: .bold))
                .foregroundColor(Studio.brass)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Studio.brassSoft)
                )
            Text(text)
                .font(.studio(11.5))
                .foregroundColor(Studio.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
