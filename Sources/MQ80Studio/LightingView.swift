import SwiftUI

// MARK: - Lighting page

struct LightingView: View {
    @EnvironmentObject var model: AppModel

    private var definition: KeyboardDefinition { model.definition }

    private var draft: LightingState {
        model.draftLighting ?? .zero
    }

    private var currentColor: Color {
        Color(
            hue: Double(draft.hue) / 255.0,
            saturation: Double(draft.saturation) / 255.0,
            brightness: 1.0
        )
    }

    private var effectIntensity: Double {
        if draft.effect == 0 { return 0.0 }
        return max(0.18, Double(draft.brightness) / Double(max(1, definition.brightnessRange.upperBound)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if model.isConnected, model.draftLighting != nil, definition.lighting.isSupported {
                    statusRow
                    if let error = model.lightingError {
                        StudioBanner(
                            tone: .error,
                            title: "灯效写入失败",
                            message: error,
                            primaryTitle: "重试",
                            primaryAction: { model.applyDraftLighting() }
                        )
                    }
                    HStack(alignment: .top, spacing: 14) {
                        previewCard
                        controlsCard.frame(width: 350)
                    }
                } else if model.isConnected, model.draftLighting != nil {
                    LightingUnsupportedState()
                } else {
                    LightingEmptyState()
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 8) {
            if model.lightingDirty {
                StudioTag(text: "有未应用的调整", color: Studio.warning, background: Studio.warningSoft, icon: "pencil")
            } else {
                StudioTag(text: "与键盘一致", color: Studio.success, background: Studio.successSoft, icon: "checkmark")
            }
            if let appliedAt = model.lightingAppliedAt, !model.lightingDirty {
                Text("上次写入 \(StudioFormat.clock.string(from: appliedAt)) · 已回读校验")
                    .font(.studio(10.5))
                    .foregroundColor(Studio.inkTertiary)
            }
            Spacer()
            Text("拖动只改本地预览，点「应用到键盘」才写入")
                .font(.studio(10.5))
                .foregroundColor(Studio.inkTertiary)
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        StudioCard(padding: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x15171B), Color(hex: 0x24282E)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(currentColor)
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .opacity(draft.effect == 0 ? 0.06 : 0.18 + effectIntensity * 0.22)
                    .offset(y: -30)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("灯光预览")
                                .font(.studio(11, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.55))
                            Text(effectTitle)
                                .font(.studio(20, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        Spacer()
                        Text("\(draft.brightness) / \(definition.brightnessRange.upperBound)")
                            .font(.studioMono(13, weight: .semibold))
                            .foregroundColor(Studio.brassBright)
                    }

                    LightingBoardPreview(
                        definition: definition,
                        color: currentColor,
                        intensity: draft.effect == 0 ? 0.05 : 0.20 + effectIntensity * 0.80
                    )
                    .frame(height: 132)

                    HStack(spacing: 18) {
                        previewMetric("亮度", "\(draft.brightness)")
                        previewMetric("速度", "\(draft.effectSpeed)")
                        previewMetric("色相", "\(draft.hue)")
                        previewMetric("饱和", "\(draft.saturation)")
                        Spacer()
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(currentColor)
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: currentColor.opacity(0.8), radius: 6)
                    }
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 392)
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.studio(9.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.42))
            Text(value)
                .font(.studioMono(12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.86))
        }
    }

    // MARK: Controls

    private var controlsCard: some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("灯效控制")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    StudioTag(text: "\(definition.lighting.label) · CH\(definition.lighting.channel)", mono: true)
                }

                if definition.lighting.hasBrightness {
                    StudioSliderRow(
                        title: "亮度",
                        valueText: "\(draft.brightness)",
                        value: brightnessBinding,
                        range: Double(definition.brightnessRange.lowerBound)...Double(definition.brightnessRange.upperBound),
                        tint: Studio.brass
                    )
                }

                if definition.lighting.hasEffect {
                StudioDivider()

                VStack(spacing: 6) {
                    HStack {
                        Text("灯效")
                            .font(.studio(11.5, weight: .medium))
                            .foregroundColor(Studio.inkSecondary)
                        Spacer()
                        Picker("", selection: effectBinding) {
                            ForEach(definition.effects) { option in
                                Text("\(effectName(option.value)) · \(option.value)").tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 170)
                    }
                    Text("固件提供 \(definition.effects.count) 种灯效，名称以实际显示为准。")
                        .font(.studio(9.5))
                        .foregroundColor(Studio.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                if definition.lighting.hasSpeed {
                StudioDivider()

                StudioSliderRow(
                    title: "速度",
                    valueText: "\(draft.effectSpeed)",
                    value: speedBinding,
                    range: Double(definition.speedRange.lowerBound)...Double(definition.speedRange.upperBound),
                    tint: Studio.info,
                    disabled: draft.effect == 0
                )
                }

                if definition.hasColor {
                    StudioDivider()
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("颜色")
                                .font(.studio(11.5, weight: .medium))
                                .foregroundColor(Studio.inkSecondary)
                            Spacer()
                            Text("H \(draft.hue) · S \(draft.saturation)")
                                .font(.studioMono(10))
                                .foregroundColor(Studio.inkTertiary)
                        }

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: (0...10).map {
                                        Color(hue: Double($0) / 10.0, saturation: 0.85, brightness: 0.95)
                                    },
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 7)

                        StudioSliderRow(
                            title: "色相",
                            valueText: "\(draft.hue)",
                            value: hueBinding,
                            range: 0...255,
                            tint: currentColor,
                            showTitle: false
                        )

                        StudioSliderRow(
                            title: "饱和度",
                            valueText: "\(draft.saturation)",
                            value: saturationBinding,
                            range: 0...255,
                            tint: currentColor,
                            showTitle: false
                        )
                    }
                }

                StudioDivider()

                HStack(spacing: 8) {
                    Button {
                        model.reloadLighting()
                    } label: {
                        Label("重新读取", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(model.isApplyingLighting)

                    Button("恢复读取时的灯效") {
                        model.revertLighting()
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(!model.lightingDirty || model.isApplyingLighting)

                    Spacer()
                }

                Button {
                    model.applyDraftLighting()
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        if model.isApplyingLighting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(model.isApplyingLighting ? "正在写入…" : "应用到键盘")
                            .font(.studio(12.5, weight: .semibold))
                        Spacer()
                    }
                }
                .buttonStyle(BrassButtonStyle())
                .disabled(model.isApplyingLighting)

                if let appliedAt = model.lightingAppliedAt, !model.lightingDirty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Studio.success)
                        Text("已写入并回读校验通过 · \(StudioFormat.clock.string(from: appliedAt))")
                            .font(.studio(10))
                            .foregroundColor(Studio.success)
                    }
                }
            }
        }
    }

    // MARK: Bindings

    private var brightnessBinding: Binding<Double> {
        sliderBinding(\.brightness)
    }

    private var speedBinding: Binding<Double> {
        sliderBinding(\.effectSpeed)
    }

    private var hueBinding: Binding<Double> {
        sliderBinding(\.hue)
    }

    private var saturationBinding: Binding<Double> {
        sliderBinding(\.saturation)
    }

    private func sliderBinding(_ keyPath: WritableKeyPath<LightingState, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.draftLighting?[keyPath: keyPath] ?? 0) },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                model.updateDraftLighting { state in
                    state[keyPath: keyPath] = rounded
                }
            }
        )
    }

    private var effectBinding: Binding<Int> {
        Binding(
            get: { model.draftLighting?.effect ?? 0 },
            set: { newValue in
                model.updateDraftLighting { state in state.effect = newValue }
            }
        )
    }

    // MARK: Effect names

    private var effectTitle: String {
        effectName(draft.effect)
    }

    private func effectName(_ effect: Int) -> String {
        let chinese = [
            "关闭", "波浪", "彩云", "漩涡", "混色", "呼吸", "常亮", "渐暗", "石纹",
            "激光", "星空", "花绽", "穿梭", "波浪条", "流星", "雨滴", "扫描", "触发彩", "中心扩散",
        ]
        if effect >= 0, effect < chinese.count {
            return chinese[effect]
        }
        return definition.effects.first(where: { $0.value == effect })?.name ?? "效果 \(effect)"
    }
}

// MARK: - Slider row

struct StudioSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint: Color = Studio.brass
    var disabled: Bool = false
    var showTitle: Bool = true

    var body: some View {
        VStack(spacing: 5) {
            if showTitle {
                HStack {
                    Text(title)
                        .font(.studio(11.5, weight: .medium))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    Text(valueText)
                        .font(.studioMono(10.5, weight: .semibold))
                        .foregroundColor(Studio.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Studio.panelMuted))
                }
            }
            Slider(value: $value, in: range, step: 1)
                .tint(tint)
                .controlSize(.small)
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
        }
    }
}

// MARK: - Board preview

struct LightingBoardPreview: View {
    let definition: KeyboardDefinition
    let color: Color
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            let keys = definition.keys
            let maxX = max(1, keys.map { $0.x + $0.width }.max() ?? 16)
            let maxY = max(1, keys.map { $0.y + $0.height }.max() ?? 5)
            let scale = max(4, min(geo.size.width / maxX, geo.size.height / maxY))

            ZStack(alignment: .topLeading) {
                ForEach(keys) { key in
                    RoundedRectangle(cornerRadius: max(1.2, scale * 0.07), style: .continuous)
                        .fill(color.opacity(intensity))
                        .frame(
                            width: max(1.5, key.width * scale - max(1.4, scale * 0.10)),
                            height: max(1.5, key.height * scale - max(1.4, scale * 0.10))
                        )
                        .shadow(color: color.opacity(intensity * 0.55), radius: max(1, scale * 0.08))
                        .position(
                            x: key.x * scale + key.width * scale / 2,
                            y: key.y * scale + key.height * scale / 2
                        )
                }
            }
            .frame(width: maxX * scale, height: maxY * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Empty state

struct LightingEmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        StudioCard(padding: 30) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Studio.brassSoft)
                        .frame(width: 54, height: 54)
                    Image(systemName: "light.max")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(Studio.brass)
                }
                Text("连接键盘后调整灯效")
                    .font(.studio(18, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("灯效页面会直接读取键盘的 RGB Matrix 通道（亮度 / 灯效 / 速度 / 颜色），修改后点「应用到键盘」才会写入并回读校验。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
                Button {
                    model.retryConnection()
                } label: {
                    Label("重新检测键盘", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(BrassButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lighting unsupported

struct LightingUnsupportedState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        StudioCard(padding: 30) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Studio.panelMuted)
                        .frame(width: 54, height: 54)
                    Image(systemName: "lightbulb.slash")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(Studio.inkTertiary)
                }
                Text("这个键盘的定义没有声明灯效控制")
                    .font(.studio(16, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("键盘已连接（\(model.definition.name)），但它的 VIA 定义里没有可识别的灯效菜单。键位映射仍可正常编辑。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }
}
