import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum BackupAlert: Identifiable {
    case restore(KeyboardBackup, URL)
    case delete(BackupFile)
    case failed(String)
    case unlinkGit

    var id: String {
        switch self {
        case .restore(_, let url): return "restore-\(url.path)"
        case .delete(let file): return "delete-\(file.url.path)"
        case .failed(let message): return "failed-\(message)"
        case .unlinkGit: return "unlink-git"
        }
    }
}

// MARK: - Backup page

struct BackupView: View {
    @EnvironmentObject var model: AppModel
    @StudioState private var pendingAlert: BackupAlert?
    @StudioState private var showCloneSheet = false
    @StudioState private var cloneRemote = ""
    @StudioState private var cloneDestination: URL?

    private var lastBackupDate: Date? {
        model.backups.first?.createdAt
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                actionBar
                gitCard
                pathCard
                if model.isRestoring {
                    restoreBanner
                }
                if model.backups.isEmpty {
                    emptyCard
                } else {
                    backupList
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.refreshBackups()
        }
        .alert(item: $pendingAlert) { item in
            alert(for: item)
        }
        .sheet(isPresented: $showCloneSheet) {
            cloneSheet
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置备份")
                    .font(.studio(13, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text(descriptionLine)
                    .font(.studio(10.5))
                    .foregroundColor(Studio.inkSecondary)
            }
            Spacer()
            Button {
                importBackup()
            } label: {
                Label("导入…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                model.createBackupNow()
            } label: {
                Label(model.isBackingUp ? "正在备份…" : "立即备份", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(BrassButtonStyle())
            .disabled(!model.isConnected || model.isBackingUp)

            Button {
                model.refreshBackups()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    private var descriptionLine: String {
        var parts = ["共 \(model.backups.count) 个备份"]
        if let date = lastBackupDate {
            parts.append("最近 \(StudioFormat.dateTime.string(from: date))")
        }
        parts.append("首次写入前会自动备份")
        if let status = model.gitStatus {
            parts.append("Git \(status.branch)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Path card

    private var pathCard: some View {
        StudioCard(padding: 13, elevated: false) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Studio.brass)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isGitLinked ? "备份目录（Git 仓库）" : "自动备份目录")
                        .font(.studio(10, weight: .semibold))
                        .foregroundColor(Studio.inkTertiary)
                    Text(model.backupDirectory.path)
                        .font(.studioMono(10))
                        .foregroundColor(Studio.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 10)
                Button("在 Finder 中显示") {
                    model.openBackupFolder()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
    }

    private var restoreBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Studio.info)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在恢复配置…")
                    .font(.studio(12, weight: .semibold))
                    .foregroundColor(Studio.ink)
                ProgressView(value: model.restoreProgress)
                    .progressViewStyle(.linear)
                    .tint(Studio.info)
                    .frame(maxWidth: 320)
            }
            Spacer()
            Text("\(Int(model.restoreProgress * 100))%")
                .font(.studioMono(11, weight: .semibold))
                .foregroundColor(Studio.info)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Studio.infoSoft)
        )
    }

    // MARK: List

    private var backupList: some View {
        StudioCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("备份文件")
                        .font(.studio(11, weight: .semibold))
                        .foregroundColor(Studio.inkSecondary)
                    Spacer()
                    Text("恢复前会二次确认，并自动备份当前配置")
                        .font(.studio(9.5))
                        .foregroundColor(Studio.inkTertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)

                StudioDivider()

                ForEach(model.backups.indices, id: \.self) { index in
                    let file = model.backups[index]
                    BackupRow(
                        file: file,
                        onRestore: {
                            do {
                                let backup = try BackupStore.load(file.url)
                                pendingAlert = .restore(backup, file.url)
                            } catch {
                                pendingAlert = .failed(model.errorText(error))
                            }
                        },
                        onExport: { export(file) },
                        onDelete: { pendingAlert = .delete(file) }
                    )
                    if index < model.backups.count - 1 {
                        Rectangle()
                            .fill(Studio.hairline)
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        StudioCard(padding: 30) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Studio.panelMuted)
                        .frame(width: 54, height: 54)
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(Studio.inkTertiary)
                }
                Text("还没有备份")
                    .font(.studio(16, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Text("连接键盘后点「立即备份」保存完整配置；写入键位或应用灯效前也会自动生成一份备份。")
                    .font(.studio(11.5))
                    .foregroundColor(Studio.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 46)
        }
    }

    // MARK: Git card

    private var gitCard: some View {
        StudioCard(padding: 16, elevated: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.isGitLinked ? Studio.infoSoft : Studio.panelMuted)
                            .frame(width: 28, height: 28)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(model.isGitLinked ? Studio.info : Studio.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Git 备份仓库")
                            .font(.studio(12.5, weight: .semibold))
                            .foregroundColor(Studio.ink)
                        Text(model.isGitLinked
                             ? "备份会自动提交版本，可推送到你自己的远程仓库"
                             : "链接你自己的 Git 仓库，让备份拥有版本历史并跨机器同步")
                            .font(.studio(10.5))
                            .foregroundColor(Studio.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    StudioTag(
                        text: model.isGitLinked ? "已链接" : "未链接",
                        color: model.isGitLinked ? Studio.success : Studio.inkTertiary,
                        background: model.isGitLinked ? Studio.successSoft : Studio.panelMuted
                    )
                    if model.isGitLinked {
                        Button {
                            model.refreshGitStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(IconButtonStyle())
                        .disabled(model.gitBusy)
                    }
                }

                if let config = model.gitConfig {
                    gitLinkedContent(config)
                } else {
                    gitUnlinkedContent
                }

                if let error = model.gitError {
                    Text(error)
                        .font(.studioMono(9.5))
                        .foregroundColor(Studio.danger)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let message = model.gitMessage {
                    Text(message)
                        .font(.studio(10))
                        .foregroundColor(Studio.inkTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var gitUnlinkedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持三种方式：链接已有本地仓库、把普通文件夹初始化为仓库，或直接克隆你的远程仓库（GitHub / Gitee / 自建均可）。链接后所有备份都会写进仓库的 backups/ 目录。")
                .font(.studio(10.5))
                .foregroundColor(Studio.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    chooseGitRepo()
                } label: {
                    Label("选择本地仓库…", systemImage: "folder")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    chooseGitRepo()
                } label: {
                    Label("新建仓库…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    showCloneSheet = true
                } label: {
                    Label("克隆远程仓库…", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            .disabled(model.gitBusy || !GitService.isAvailable())

            Text("推送/拉取使用本机已有的 SSH key 或 git credential helper；App 不会保存你的密码。")
                .font(.studio(9.5))
                .foregroundColor(Studio.inkTertiary)
        }
    }

    private func gitLinkedContent(_ config: GitBackupConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Studio.brass)
                Text(config.displayPath)
                    .font(.studioMono(10))
                    .foregroundColor(Studio.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.open(config.repoURL)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }

            HStack(spacing: 22) {
                gitMeta("分支", model.gitStatus?.branch ?? "—")
                gitMeta("远程", model.gitStatus?.remoteURL ?? "未配置 origin")
                gitMeta("最近提交", gitLastCommitText)
            }

            HStack(spacing: 10) {
                Toggle("自动提交", isOn: Binding(
                    get: { model.gitConfig?.autoCommit ?? true },
                    set: { model.setGitAutoCommit($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.studio(10.5))

                Toggle("自动推送", isOn: Binding(
                    get: { model.gitConfig?.autoPush ?? false },
                    set: { model.setGitAutoPush($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.studio(10.5))

                Text(gitWorktreeText)
                    .font(.studio(9.5))
                    .foregroundColor(Studio.inkTertiary)

                Spacer()

                Button {
                    model.createBackupNow()
                } label: {
                    Label("备份并提交", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(!model.isConnected || model.isBackingUp)

                Button {
                    model.pushGitRemote()
                } label: {
                    Label("推送", systemImage: "arrow.up.circle")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(model.gitBusy || model.gitStatus?.hasRemote != true)

                Button {
                    model.pullGitRemote()
                } label: {
                    Label("拉取", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(model.gitBusy || model.gitStatus?.hasRemote != true)

                Button {
                    pendingAlert = .unlinkGit
                } label: {
                    Label("解除链接", systemImage: "link.badge.minus")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(model.gitBusy)
            }
        }
    }

    private func gitMeta(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.studio(9, weight: .semibold))
                .foregroundColor(Studio.inkTertiary)
            Text(value)
                .font(.studioMono(10))
                .foregroundColor(Studio.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var gitLastCommitText: String {
        guard let status = model.gitStatus else { return "读取中…" }
        guard let short = status.lastCommitShort else { return "还没有提交" }
        return "\(short) \(status.lastCommitSubject ?? "")"
    }

    private var gitWorktreeText: String {
        guard let status = model.gitStatus, !model.gitBusy else { return "" }
        var text = status.isClean ? "工作区干净" : "\(status.dirtyFileCount) 个未提交文件"
        if let ahead = status.ahead, let behind = status.behind, ahead > 0 || behind > 0 {
            text += " · 领先 \(ahead) / 落后 \(behind)"
        }
        return text
    }

    private var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("克隆远程备份仓库")
                    .font(.studio(15, weight: .semibold))
                    .foregroundColor(Studio.ink)
                Spacer()
                Button {
                    showCloneSheet = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }
            Text("支持 HTTPS 或 SSH 地址。私有仓库请先在本机配好 SSH key 或 git credential helper。")
                .font(.studio(10.5))
                .foregroundColor(Studio.inkSecondary)
            TextField("git@github.com:you/mq80-backups.git", text: $cloneRemote)
                .textFieldStyle(.roundedBorder)
                .font(.studioMono(11))
            HStack(spacing: 8) {
                Text("保存到")
                    .font(.studio(10.5))
                    .foregroundColor(Studio.inkSecondary)
                Text(cloneDestination?.path ?? "请选择一个空目录")
                    .font(.studioMono(10))
                    .foregroundColor(cloneDestination == nil ? Studio.inkTertiary : Studio.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("选择目录…") {
                    chooseCloneDestination()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            HStack {
                Spacer()
                Button("取消") {
                    showCloneSheet = false
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    guard let destination = cloneDestination else { return }
                    showCloneSheet = false
                    model.cloneGitRepository(remote: cloneRemote, to: destination)
                } label: {
                    Label("克隆并链接", systemImage: "arrow.down.circle")
                }
                .buttonStyle(BrassButtonStyle())
                .disabled(cloneRemote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloneDestination == nil)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    // MARK: Git panels

    private func chooseGitRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择你的 Git 备份仓库目录（不是 Git 仓库也可以，会自动初始化）"
        panel.prompt = "链接"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.linkGitRepository(at: url)
    }

    private func chooseCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择用于存放克隆仓库的空目录（可在面板中新建文件夹）"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cloneDestination = url
    }

    // MARK: Alerts

    private func alert(for item: BackupAlert) -> Alert {
        switch item {
        case .restore(let backup, let url):
            return Alert(
                title: Text("从备份恢复？"),
                message: Text(
                    "即将把「\(url.lastPathComponent)」的 \(backup.keymap.layerCount) 层键位"
                        + (backup.lighting == nil ? "" : "与灯效")
                        + "写入键盘。\n\n当前配置会先自动备份一次，写入完成后会自动回读校验。"
                ),
                primaryButton: .destructive(Text("恢复")) {
                    model.beginRestore(backup)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case .delete(let file):
            return Alert(
                title: Text("删除备份？"),
                message: Text("将永久删除「\(file.name)」及其 JSON 文件，无法撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    model.deleteBackup(file)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case .failed(let message):
            return Alert(
                title: Text("操作失败"),
                message: Text(message),
                dismissButton: .default(Text("好"))
            )
        case .unlinkGit:
            return Alert(
                title: Text("解除 Git 仓库链接？"),
                message: Text("App 会切回本地备份目录；Git 仓库中的备份文件不会被删除。"),
                primaryButton: .destructive(Text("解除链接")) {
                    model.unlinkGitRepository()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: Panels

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择 MQ80 备份 JSON 文件"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try BackupStore.load(url)
            pendingAlert = .restore(backup, url)
        } catch {
            pendingAlert = .failed(model.errorText(error))
        }
    }

    private func export(_ file: BackupFile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(file.name).json"
        panel.message = "导出备份副本"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file.url, to: destination)
            model.showToast(.success, "已导出 \(destination.lastPathComponent)")
        } catch {
            pendingAlert = .failed(model.errorText(error))
        }
    }
}

// MARK: - Backup row

struct BackupRow: View {
    let file: BackupFile
    let onRestore: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @StudioState private var hovered = false

    private var isAutomatic: Bool {
        file.name.hasPrefix("Auto-")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isAutomatic ? Studio.brassSoft : Studio.panelMuted)
                Image(systemName: isAutomatic ? "clock.arrow.circlepath" : "externaldrive.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAutomatic ? Studio.brass : Studio.inkSecondary)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.studio(12, weight: .semibold))
                        .foregroundColor(Studio.ink)
                        .lineLimit(1)
                    if isAutomatic {
                        StudioTag(text: "自动", color: Studio.brass, background: Studio.brassSoft)
                    }
                }
                HStack(spacing: 8) {
                    Text(StudioFormat.dateTime.string(from: file.createdAt))
                    Text("·")
                    Text(file.summary)
                }
                .font(.studio(10))
                .foregroundColor(Studio.inkTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button("恢复") {
                    onRestore()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))

                Button("导出") {
                    onExport()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle(size: 26))
            }
            .opacity(hovered ? 1 : 0.72)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .contentShape(Rectangle())
        .background(hovered ? Studio.panelMuted : Color.clear)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovered = value }
        }
    }
}
