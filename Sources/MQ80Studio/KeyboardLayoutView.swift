import SwiftUI

/// Renders the 84-key KLE layout of the MQ80 inside whatever space it gets.
/// The board scales uniformly; keycaps keep their unit proportions and width modifiers.
struct KeyboardLayoutView: View {
    @EnvironmentObject var model: AppModel

    let layer: Int
    var silhouette: Bool = false
    var interactive: Bool = true
    let selectedKeyID: Int?
    let onSelect: (Int) -> Void

    private var definition: KeyboardDefinition { model.definition }

    var body: some View {
        GeometryReader { geo in
            let keys = definition.keys
            let maxX = max(1, keys.map { $0.x + $0.width }.max() ?? 16)
            let maxY = max(1, keys.map { $0.y + $0.height }.max() ?? 5)
            let inset: CGFloat = silhouette ? 0 : 10
            let availableWidth = max(40, geo.size.width - inset * 2)
            let availableHeight = max(40, geo.size.height - inset * 2)
            let scale = max(10, min(availableWidth / maxX, availableHeight / maxY))
            let boardWidth = maxX * scale
            let boardHeight = maxY * scale
            let gap = max(2.5, scale * 0.09)

            ZStack(alignment: .topLeading) {
                ForEach(keys) { key in
                    keycap(for: key, scale: scale, gap: gap)
                        .frame(
                            width: max(3, key.width * scale - gap),
                            height: max(3, key.height * scale - gap)
                        )
                        .position(
                            x: key.x * scale + key.width * scale / 2,
                            y: key.y * scale + key.height * scale / 2
                        )
                }
            }
            .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .allowsHitTesting(interactive && !silhouette)
    }

    @ViewBuilder
    private func keycap(for key: KeyPosition, scale: CGFloat, gap: CGFloat) -> some View {
        let value = silhouette ? 0 : model.value(layer: layer, index: key.id)
        let isSelected = !silhouette && selectedKeyID == key.id
        let fontSize = max(6.5, min(12, scale * 0.27))
        let displayLabel: String = {
            if silhouette { return "" }
            if value == 0 { return "无" }
            return model.label(for: value)
        }()
        let base: Color = silhouette
            ? Studio.keycapMid.opacity(0.5)
            : Studio.keycapBase(for: key.colorHex)

        KeycapFace(
            label: displayLabel,
            base: base,
            legend: value == 0 ? Studio.keycapLegendDim : Studio.keycapLegend,
            fontSize: fontSize,
            selected: isSelected,
            marked: !silhouette && model.isMarked(layer: layer, index: key.id),
            dimmed: value == 0
        )
        .onTapGesture {
            guard interactive, !silhouette else { return }
            onSelect(key.id)
        }
    }
}

/// A single keycap: graphite face, soft top highlight and a physical bottom lip.
struct KeycapFace: View {
    let label: String
    let base: Color
    var legend: Color = Studio.keycapLegend
    var fontSize: CGFloat = 10
    var selected: Bool = false
    var marked: Bool = false
    var dimmed: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(3, min(9, fontSize * 0.72)), style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(base)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.17),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.06),
                            Color.black.opacity(0.24),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            VStack(spacing: 0) {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundColor(legend)
                        .lineLimit(1)
                        .minimumScaleFactor(0.42)
                        .padding(.horizontal, 3)
                }
            }
        }
        .overlay(alignment: .top) {
            // thin machined highlight along the top edge
            shape
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .mask(
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                )
        }
        .overlay(alignment: .topTrailing) {
            if marked {
                Circle()
                    .fill(Studio.brassBright)
                    .frame(width: max(3.5, fontSize * 0.34), height: max(3.5, fontSize * 0.34))
                    .padding(max(2, fontSize * 0.22))
                    .shadow(color: Studio.brassBright.opacity(0.8), radius: 2)
            }
        }
        .overlay {
            shape.stroke(selected ? Studio.brassBright : Color.black.opacity(0.16), lineWidth: selected ? 2 : 1)
        }
        .shadow(color: Color.black.opacity(selected ? 0.28 : 0.16), radius: selected ? 5 : 1.5, x: 0, y: selected ? 2.5 : 1.5)
        .shadow(color: selected ? Studio.brassBright.opacity(0.45) : Color.clear, radius: 7)
        .scaleEffect(selected ? 1.035 : 1)
        .opacity(dimmed && !selected ? 0.86 : 1)
        .animation(.easeOut(duration: 0.13), value: selected)
    }
}
