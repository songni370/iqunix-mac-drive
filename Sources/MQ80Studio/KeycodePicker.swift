import SwiftUI

/// Keycode browser sheet: search, category groups, keycap-shaped buttons.
struct KeycodePicker: View {
    @EnvironmentObject var model: AppModel

    let currentValue: UInt16
    let onPick: (UInt16) -> Void
    let onCancel: () -> Void

    @StudioState private var query = ""

    private var results: [KeycodeInfo] {
        KeycodeCatalog.search(query, entries: model.keycodeEntries)
    }

    private var groupedResults: [(category: KeycodeCategory, items: [KeycodeInfo])] {
        KeycodeCategory.allCases.compactMap { category in
            let items = results.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            StudioDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    clearRow
                    ForEach(groupedResults.indices, id: \.self) { index in
                        let group = groupedResults[index]
                        categorySection(group.category, items: group.items)
                    }
                    if results.isEmpty {
                        emptySearch
                    }
                }
                .padding(18)
            }
            StudioDivider()
            footer
        }
        .frame(width: 660, height: 600)
        .background(Studio.canvas)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("选择键码")
                    .font(.studio(17, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("当前：\(model.label(for: currentValue))  \(StudioFormat.hex(currentValue))")
                    .font(.studio(11))
                    .foregroundColor(Studio.inkSecondary)
            }
            Spacer()
            StudioTag(text: "\(results.count) 个键码", mono: true)
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            StudioSearchField(placeholder: "搜索键名或键码，例如 A、Enter、0x0028", text: $query)
            Button("无（KC_NO）") {
                onPick(KeycodeCatalog.kcNo)
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: Content

    private var clearRow: some View {
        Button {
            onPick(KeycodeCatalog.kcNo)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "nosign")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Studio.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text("无（KC_NO）")
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.ink)
                    Text("清除这个按键，使其不发送任何键码")
                        .font(.studio(10))
                        .foregroundColor(Studio.inkTertiary)
                }
                Spacer()
                Text("0x0000")
                    .font(.studioMono(9))
                    .foregroundColor(Studio.inkTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Studio.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Studio.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func categorySection(_ category: KeycodeCategory, items: [KeycodeInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(category.title)
                    .font(.studio(11.5, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("\(items.count)")
                    .font(.studioMono(8.5, weight: .semibold))
                    .foregroundColor(Studio.inkTertiary)
                Rectangle()
                    .fill(Studio.hairline)
                    .frame(height: 1)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92, maximum: 132), spacing: 7)],
                spacing: 7
            ) {
                ForEach(items) { info in
                    keycodeButton(info)
                }
            }
        }
    }

    private func keycodeButton(_ info: KeycodeInfo) -> some View {
        let selected = info.value == currentValue
        return Button {
            onPick(info.value)
        } label: {
            VStack(spacing: 1) {
                Text(info.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Studio.keycapLegend)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(String(format: "0x%04X", info.value))
                    .font(.studioMono(7.5))
                    .foregroundColor(Studio.keycapLegendDim)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Studio.keycapLight, Studio.keycapDefault],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Studio.brassBright : Color.black.opacity(0.2), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(selected ? 0.28 : 0.14), radius: selected ? 4 : 1.5, x: 0, y: 1.5)
        }
        .buttonStyle(.plain)
    }

    private var emptySearch: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Studio.inkTertiary)
            Text("没有匹配的键码")
                .font(.studio(12, weight: .semibold))
                .foregroundColor(Studio.inkSecondary)
            Text("试试搜索英文键名（Enter、F5）或十六进制值（0x0028）。")
                .font(.studio(10.5))
                .foregroundColor(Studio.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("键码标签仅用于显示；写入的是 VIA 协议数值。")
                .font(.studio(10))
                .foregroundColor(Studio.inkTertiary)
            Spacer()
            Text("\(results.count) 个结果")
                .font(.studioMono(9.5))
                .foregroundColor(Studio.inkTertiary)
            Button("取消") {
                onCancel()
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Studio.panelMuted)
    }
}
