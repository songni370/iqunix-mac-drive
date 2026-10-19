import Foundation
import SwiftUI
import AppKit

// MARK: - UI models

enum ConnectionStatus: Equatable {
    case scanning
    case connecting
    case connected
    case permissionDenied
    case needsDefinition
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .scanning: return "等待键盘"
        case .connecting: return "正在连接"
        case .connected: return "已连接"
        case .permissionDenied: return "需要输入监控权限"
        case .needsDefinition: return "需要键盘定义"
        case .failed: return "连接失败"
        }
    }

    var color: Color {
        switch self {
        case .scanning: return Studio.inkTertiary
        case .connecting: return Studio.info
        case .connected: return Studio.success
        case .permissionDenied: return Studio.warning
        case .needsDefinition: return Studio.warning
        case .failed: return Studio.danger
        }
    }
}

struct StudioToast: Identifiable, Equatable {
    enum Kind { case success, info, error }

    let id = UUID()
    let kind: Kind
    let message: String
}

struct StudioAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let message: String
}

struct SelectedKeyDetails {
    let position: KeyPosition
    let index: Int
    let value: UInt16
    let originalValue: UInt16
    let label: String
    let code: String?
    let hex: String
}

// MARK: - AppModel

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var definition: KeyboardDefinition = .placeholder
    @Published private(set) var definitionSource: DefinitionSource?
    @Published private(set) var definitionDetail: String?
    @Published private(set) var devices: [VIADevice] = []
    @Published private(set) var selectedDevice: VIADevice?
    @Published private(set) var needsDefinition = false

    private let hid = HIDWorker()
    private var pollTimer: Timer?
    private var connecting = false
    private var autoConnectSuspended = false
    private var cachedEntries: [KeycodeInfo] = []
    private var cachedEntriesKey = ""
    private var toastClearTask: Task<Void, Never>?

    // Connection
    @Published private(set) var status: ConnectionStatus = .scanning
    @Published private(set) var isPresent = false
    @Published private(set) var discovered: VIADevice?
    @Published private(set) var deviceInfo: DeviceInfo?

    // Keymap editing
    @Published private(set) var originalKeymap: Keymap?
    @Published private(set) var stagedKeymap: Keymap?
    @Published private(set) var selectedLayer = 0
    @Published private(set) var selectedKeyID: Int?
    @Published private(set) var isWriting = false
    @Published private(set) var writeProgress: Double = 0
    @Published private(set) var writeError: String?
    @Published private(set) var isRestoring = false
    @Published private(set) var restoreProgress: Double = 0

    // Lighting
    @Published private(set) var originalLighting: LightingState?
    @Published private(set) var draftLighting: LightingState?
    @Published private(set) var isApplyingLighting = false
    @Published private(set) var lightingError: String?
    @Published private(set) var lightingAppliedAt: Date?

    // Session bookkeeping
    @Published private(set) var autoBackupURL: URL?
    @Published private(set) var isBackingUp = false
    @Published private(set) var backups: [BackupFile] = []

    // Git backup repository
    @Published private(set) var gitConfig: GitBackupConfig?
    @Published private(set) var gitStatus: GitRepoStatus?
    @Published private(set) var gitBusy = false
    @Published private(set) var gitError: String?
    @Published private(set) var gitMessage: String?
    private let gitQueue = DispatchQueue(label: "studio.mq80.git", qos: .utility)
    @Published var debugLoggingEnabled = true
    @Published private(set) var log: [LogEntry] = []

    // Transient UI
    @Published var alert: StudioAlert?
    @Published var toast: StudioToast?

    // MARK: Lifecycle

    func start() {
        guard pollTimer == nil else { return }
        record("应用", "IQUNIX-DRIVE \(AppConstants.appVersion) 启动")
        DefinitionStore.shared.reload()
        gitConfig = GitBackupStore.load()
        refreshBackups()
        if gitConfig != nil {
            refreshGitStatus()
        }
        // 安全预览模式（UI 走查/截图用）：不枚举、不打开真实设备。
        if ProcessInfo.processInfo.environment["MQ80STUDIO_SAFE_PREVIEW"] == "1" {
            record("应用", "安全预览模式：跳过设备检测")
            return
        }
        pollDevices()
        let timer = Timer(timeInterval: 2.0, target: self, selector: #selector(pollTick), userInfo: nil, repeats: true)
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    @objc private func pollTick() {
        pollDevices()
    }

    // MARK: Derived state

    var isConnected: Bool { status == .connected && deviceInfo != nil }

    var permissionDenied: Bool {
        if case .permissionDenied = status { return true }
        return false
    }

    var layerCount: Int {
        max(1, deviceInfo?.layerCount ?? 4)
    }

    var layerNumbers: [Int] { Array(0..<max(4, layerCount)) }

    func layerName(_ layer: Int) -> String {
        switch layer {
        case 0: return "基础"
        case 1: return "Fn"
        default: return "Layer \(layer)"
        }
    }

    var deviceName: String {
        deviceInfo?.displayName ?? selectedDevice?.displayName ?? discovered?.displayName ?? "VIA 键盘"
    }

    var activeDefinitionName: String {
        hasResolvedDefinition ? definition.name : "未匹配键盘定义"
    }

    var keycodeEntries: [KeycodeInfo] {
        let count = layerCount
        let protocolVersion = deviceInfo?.protocolVersion ?? 11
        let key = "\(definition.name)|\(protocolVersion)|\(count)"
        if cachedEntriesKey != key {
            cachedEntries = KeycodeCatalog.entries(
                protocolVersion: protocolVersion,
                customKeycodeNames: definition.customKeycodeNames,
                customKeycodeTitles: definition.customKeycodeTitles,
                layerCount: count
            )
            cachedEntriesKey = key
        }
        return cachedEntries
    }

    var hasResolvedDefinition: Bool { definitionSource != nil }
    var definitionLibrarySummary: String {
        "内置 \(DefinitionStore.shared.builtinCount) 个 · 用户导入 \(DefinitionStore.shared.userCount) 个"
    }

    /// All discovered VIA-capable keyboards (for the device picker).
    var availableDevices: [VIADevice] { devices }

    var unsavedChanges: [KeyChange] {
        guard let staged = stagedKeymap, let original = originalKeymap else { return [] }
        return staged.differences(comparedTo: original)
    }

    var unsavedCount: Int { unsavedChanges.count }

    var lightingDirty: Bool {
        guard let draft = draftLighting, let original = originalLighting else { return false }
        return draft != original
    }

    func label(for value: UInt16) -> String {
        KeycodeCatalog.label(for: value, customKeycodeNames: definition.customKeycodeNames, layerCount: layerCount, protocolVersion: deviceInfo?.protocolVersion ?? 11)
    }

    func value(layer: Int, index: Int) -> UInt16 {
        stagedKeymap?.value(layer: layer, index: index) ?? 0
    }

    func originalValue(layer: Int, index: Int) -> UInt16 {
        originalKeymap?.value(layer: layer, index: index) ?? 0
    }

    /// Fn / higher layers: mark keys that differ from the base layer.
    func isMarked(layer: Int, index: Int) -> Bool {
        guard layer > 0 else { return false }
        let value = self.value(layer: layer, index: index)
        guard value != 0 else { return false }
        return value != self.value(layer: 0, index: index)
    }

    var selectedKeyDetails: SelectedKeyDetails? {
        guard let id = selectedKeyID,
              let position = definition.key(forMatrixIndex: id),
              stagedKeymap != nil else { return nil }
        let value = self.value(layer: selectedLayer, index: id)
        let original = originalValue(layer: selectedLayer, index: id)
        let info = KeycodeCatalog.info(for: value, customKeycodeNames: definition.customKeycodeNames, protocolVersion: deviceInfo?.protocolVersion ?? 11)
        return SelectedKeyDetails(
            position: position,
            index: id,
            value: value,
            originalValue: original,
            label: label(for: value),
            code: info?.code,
            hex: StudioFormat.hex(value)
        )
    }

    // MARK: Discovery / connection

    private func pollDevices() {
        guard !connecting else { return }
        guard !isWriting, !isApplyingLighting, !isRestoring, !isBackingUp else { return }
        hid.discover { [weak self] devices in
            guard let self = self else { return }
            self.handleDiscovery(devices)
        }
    }

    private func handleDiscovery(_ devices: [VIADevice]) {
        self.devices = devices
        if !connecting {
            isPresent = !devices.isEmpty
        }
        if devices.isEmpty {
            selectedDevice = nil
            if isConnected || connecting || needsDefinition {
                teardownConnection(reason: "键盘已断开")
            } else if status != .permissionDenied {
                status = .scanning
            }
            return
        }

        // Keep the current selection if still plugged in, otherwise prefer a
        // device we can resolve a definition for, then fall back to the first.
        let preferred = devices.first { $0 == selectedDevice }
            ?? devices.first { DefinitionStore.shared.resolve(device: $0) != nil }
            ?? devices.first
        selectedDevice = preferred
        if !connecting {
            discovered = preferred
        }

        guard !isConnected, !connecting, !autoConnectSuspended, !needsDefinition else { return }
        connect()
    }

    private func connect() {
        guard !connecting else { return }
        guard let device = selectedDevice ?? discovered else { return }
        guard let resolved = DefinitionStore.shared.resolve(device: device) else {
            connecting = false
            needsDefinition = true
            autoConnectSuspended = false
            status = .needsDefinition
            record("连接", "发现 \(device.displayName)，但缺少键盘定义，等待导入")
            return
        }

        definition = resolved.definition
        definitionSource = resolved.source
        definitionDetail = resolved.detail
        needsDefinition = false
        connecting = true
        status = .connecting
        record("连接", "正在打开 \(device.displayName) · 定义：\(resolved.definition.name)（\(resolved.source.title)）…")
        hid.connect(device: device, definition: resolved.definition) { [weak self] result in
            guard let self = self else { return }
            self.connecting = false
            switch result {
            case .success(let snapshot):
                self.apply(snapshot: snapshot)
            case .failure(let error):
                self.handleConnectFailure(error)
            }
        }
    }

    private func apply(snapshot: ConnectionSnapshot) {
        connecting = false
        autoConnectSuspended = false
        needsDefinition = false
        status = .connected
        isPresent = true
        deviceInfo = snapshot.info
        originalKeymap = snapshot.keymap
        stagedKeymap = snapshot.keymap
        originalLighting = snapshot.lighting
        draftLighting = snapshot.lighting
        lightingAppliedAt = nil
        writeError = nil
        writeProgress = 0
        lightingError = nil
        autoBackupURL = nil
        if selectedLayer >= snapshot.info.layerCount { selectedLayer = 0 }
        if let selected = selectedKeyID, definition.key(forMatrixIndex: selected) == nil { selectedKeyID = nil }
        record(
            "连接",
            "已连接 \(snapshot.info.displayName) · VIA \(snapshot.info.protocolVersion) · "
                + "\(snapshot.info.layerCount) 层 · \(snapshot.info.rows)×\(snapshot.info.cols) 矩阵"
        )
        showToast(.success, "已连接 \(definition.name)")
        refreshBackups()
    }

    private func handleConnectFailure(_ error: Error) {
        if case VIAError.definitionNotFound = error {
            needsDefinition = true
            autoConnectSuspended = false
            status = .needsDefinition
            record("连接", "缺少键盘定义，等待导入")
            return
        }
        autoConnectSuspended = true
        if let viaError = error as? VIAError {
            switch viaError {
            case .permissionDenied:
                status = .permissionDenied
                record("连接", "没有输入监控权限，等待用户授权")
            case .deviceNotFound:
                status = .scanning
                autoConnectSuspended = false
                record("连接", "设备暂时不可打开，稍后重试")
            default:
                status = .failed(errorText(error))
                record("连接", "连接失败：\(errorText(error))")
            }
        } else {
            status = .failed(errorText(error))
            record("连接", "连接失败：\(errorText(error))")
        }
    }

    private func teardownConnection(reason: String) {
        hid.disconnect()
        connecting = false
        status = .scanning
        needsDefinition = false
        deviceInfo = nil
        originalKeymap = nil
        stagedKeymap = nil
        selectedKeyID = nil
        originalLighting = nil
        draftLighting = nil
        lightingAppliedAt = nil
        writeError = nil
        lightingError = nil
        writeProgress = 0
        autoBackupURL = nil
        definition = .placeholder
        definitionSource = nil
        definitionDetail = nil
        record("连接", reason)
    }

    func retryConnection() {
        autoConnectSuspended = false
        writeError = nil
        if needsDefinition {
            DefinitionStore.shared.reload()
            connect()
            return
        }
        if isConnected {
            hid.disconnect()
            teardownConnection(reason: "手动断开连接")
            autoConnectSuspended = true
            showToast(.info, "已断开连接")
            return
        }
        if isPresent {
            connect()
        } else {
            status = .scanning
            pollDevices()
            showToast(.info, "正在重新检测键盘…")
        }
    }

    func disconnectManually() {
        autoConnectSuspended = true
        hid.disconnect()
        teardownConnection(reason: "手动断开连接")
        showToast(.info, "已断开连接")
    }

    // MARK: Editing

    func selectLayer(_ layer: Int) {
        guard layer >= 0, layer < layerCount else { return }
        selectedLayer = layer
        record("编辑", "切换到 \(layerName(layer)) 层")
    }

    func selectKey(_ index: Int?) {
        selectedKeyID = index
    }

    func setKeycode(_ value: UInt16) {
        guard let id = selectedKeyID else { return }
        setKeycode(value, layer: selectedLayer, index: id)
    }

    func setKeycode(_ value: UInt16, layer: Int, index: Int) {
        guard var staged = stagedKeymap else { return }
        guard layer >= 0, layer < staged.layers.count, index >= 0, index < staged.layers[layer].count else { return }
        guard staged.layers[layer][index] != value else { return }
        staged.layers[layer][index] = value
        stagedKeymap = staged
        let position = definition.key(forMatrixIndex: index)
        let location = position.map { "R\($0.row) C\($0.col)" } ?? "#\(index)"
        record("编辑", "\(layerName(layer)) 层 \(location)：\(label(for: value))")
    }

    func restoreSelectedKey() {
        guard let id = selectedKeyID else { return }
        setKeycode(originalValue(layer: selectedLayer, index: id), layer: selectedLayer, index: id)
        showToast(.info, "已恢复此键的原始键码（尚未写入）")
    }

    func discardChanges() {
        stagedKeymap = originalKeymap
        writeError = nil
        writeProgress = 0
        showToast(.info, "已放弃未保存的修改")
    }

    func resetCurrentLayer() {
        guard var staged = stagedKeymap, let original = originalKeymap else { return }
        guard selectedLayer < staged.layers.count else { return }
        let count = min(staged.layers[selectedLayer].count, original.layers.count > selectedLayer ? original.layers[selectedLayer].count : 0)
        guard count > 0 else { return }
        var changed = 0
        for index in 0..<count where staged.layers[selectedLayer][index] != original.layers[selectedLayer][index] {
            staged.layers[selectedLayer][index] = original.layers[selectedLayer][index]
            changed += 1
        }
        stagedKeymap = staged
        showToast(.info, changed > 0 ? "已重置\(layerName(selectedLayer))层（尚未写入）" : "\(layerName(selectedLayer))层没有需要重置的修改")
    }

    // MARK: Writing keymap

    func writeStagedKeymap() {
        guard isConnected else {
            showToast(.error, "键盘未连接，无法写入")
            return
        }
        guard let staged = stagedKeymap else { return }
        guard unsavedCount > 0 else {
            showToast(.info, "没有需要写入的修改")
            return
        }
        writeError = nil
        isWriting = true
        writeProgress = 0
        _ = ensureAutoBackup(reason: "写入键位前")
        record("写入", "开始写入 \(layerCount) 层键位，共 \(unsavedCount) 处修改")
        hid.writeKeymap(staged, progress: { [weak self] value in
            self?.writeProgress = value
        }, completion: { [weak self] result in
            guard let self = self else { return }
            self.isWriting = false
            switch result {
            case .success(let readBack):
                self.originalKeymap = readBack
                self.stagedKeymap = readBack
                self.writeProgress = 1
                self.writeError = nil
                self.record("写入", "写入完成并通过回读校验")
                self.showToast(.success, "已写入键盘并通过回读校验")
                self.refreshBackups()
            case .failure(let error):
                self.writeProgress = 0
                self.writeError = self.errorText(error)
                self.record("写入", "写入失败：\(self.errorText(error))")
                self.showToast(.error, "写入失败，可以重试")
                if self.isConnectionLoss(error) {
                    self.teardownConnection(reason: "写入时连接中断")
                }
            }
        })
    }

    func retryWrite() {
        writeStagedKeymap()
    }

    func dismissWriteError() {
        writeError = nil
    }

    // MARK: Lighting

    func updateDraftLighting(_ transform: (inout LightingState) -> Void) {
        guard var draft = draftLighting else { return }
        transform(&draft)
        draftLighting = draft
    }

    func setDraftLighting(_ state: LightingState) {
        draftLighting = state
    }

    func applyDraftLighting() {
        guard isConnected else {
            showToast(.error, "键盘未连接，无法应用灯效")
            return
        }
        guard let draft = draftLighting else { return }
        guard definition.lighting.isSupported else {
            showToast(.info, "这个键盘的定义没有声明可用的灯效控制")
            return
        }
        lightingError = nil
        isApplyingLighting = true
        _ = ensureAutoBackup(reason: "应用灯效前")
        record("灯效", "应用亮度 \(draft.brightness) / 效果 \(draft.effect) / 速度 \(draft.effectSpeed) / H\(draft.hue) S\(draft.saturation)")
        hid.applyLighting(draft) { [weak self] result in
            guard let self = self else { return }
            self.isApplyingLighting = false
            switch result {
            case .success(let readBack):
                self.originalLighting = readBack
                self.draftLighting = readBack
                self.lightingError = nil
                self.lightingAppliedAt = Date()
                self.record("灯效", "应用成功，回读一致")
                self.showToast(.success, "灯效已写入并通过回读校验")
            case .failure(let error):
                self.lightingError = self.errorText(error)
                self.record("灯效", "应用失败：\(self.errorText(error))")
                self.showToast(.error, "灯效写入失败")
                if self.isConnectionLoss(error) {
                    self.teardownConnection(reason: "应用灯效时连接中断")
                }
            }
        }
    }

    func reloadLighting() {
        guard isConnected else { return }
        isApplyingLighting = true
        lightingError = nil
        hid.readLighting { [weak self] result in
            guard let self = self else { return }
            self.isApplyingLighting = false
            switch result {
            case .success(let state):
                self.originalLighting = state
                self.draftLighting = state
                self.lightingAppliedAt = nil
                self.record("灯效", "已从键盘重新读取灯效")
                self.showToast(.info, "已重新读取灯效")
            case .failure(let error):
                self.lightingError = self.errorText(error)
                self.showToast(.error, "读取灯效失败")
            }
        }
    }

    func revertLighting() {
        draftLighting = originalLighting
        lightingError = nil
        showToast(.info, "已恢复为读取时的灯效")
    }

    // MARK: Backup

    /// Where backups are written: the linked Git repository's `backups/`
    /// directory, or the local App Support directory when no repo is linked.
    var backupDirectory: URL {
        gitConfig?.backupsDirectory ?? BackupStore.backupsDirectory
    }

    var isGitLinked: Bool { gitConfig != nil }

    func refreshBackups() {
        backups = BackupStore.list(directory: backupDirectory)
    }

    func openBackupFolder() {
        try? BackupStore.ensureDirectory(backupDirectory)
        NSWorkspace.shared.open(backupDirectory)
    }

    func openInputMonitoringSettings() {
        let raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    func createBackupNow() {
        guard isConnected else {
            showToast(.error, "键盘未连接，无法读取配置")
            return
        }
        isBackingUp = true
        record("备份", "开始读取完整配置并备份")
        hid.createBackup(directory: backupDirectory) { [weak self] result in
            guard let self = self else { return }
            self.isBackingUp = false
            switch result {
            case .success(let url):
                self.refreshBackups()
                self.record("备份", "已保存备份 \(url.lastPathComponent)")
                if self.gitConfig != nil {
                    self.gitCommitAfterBackup(reason: "手动备份", force: true)
                } else {
                    self.showToast(.success, "已保存备份 \(url.lastPathComponent)")
                }
            case .failure(let error):
                self.record("备份", "备份失败：\(self.errorText(error))")
                self.alert = StudioAlert(title: "备份失败", message: self.errorText(error))
            }
        }
    }

    func deleteBackup(_ file: BackupFile) {
        do {
            try BackupStore.delete(file.url)
            refreshBackups()
            record("备份", "已删除 \(file.name)")
            showToast(.info, "已删除 \(file.name)")
        } catch {
            alert = StudioAlert(title: "删除失败", message: errorText(error))
        }
    }

    func beginRestore(_ backup: KeyboardBackup) {
        guard isConnected else {
            alert = StudioAlert(title: "无法恢复", message: "请先连接键盘，再恢复备份。")
            return
        }
        isRestoring = true
        restoreProgress = 0
        _ = ensureAutoBackup(reason: "恢复备份前")
        record("恢复", "开始从备份恢复：\(backup.keymap.layerCount) 层键位")
        hid.restore(backup, progress: { [weak self] value in
            self?.restoreProgress = value
        }, completion: { [weak self] result in
            guard let self = self else { return }
            self.isRestoring = false
            self.restoreProgress = 0
            switch result {
            case .success(let snapshot):
                self.deviceInfo = snapshot.info
                self.originalKeymap = snapshot.keymap
                self.stagedKeymap = snapshot.keymap
                self.originalLighting = snapshot.lighting
                self.draftLighting = snapshot.lighting
                self.writeError = nil
                self.lightingError = nil
                self.record("恢复", "恢复完成并通过回读校验")
                self.showToast(.success, "已从备份恢复并通过回读校验")
                self.refreshBackups()
            case .failure(let error):
                self.record("恢复", "恢复失败：\(self.errorText(error))")
                self.alert = StudioAlert(title: "恢复失败", message: self.errorText(error))
                if self.isConnectionLoss(error) {
                    self.teardownConnection(reason: "恢复时连接中断")
                }
            }
        })
    }

    /// One automatic backup per connected session, taken before the first write.
    @discardableResult
    func ensureAutoBackup(reason: String) -> URL? {
        if let url = autoBackupURL { return url }
        guard let info = deviceInfo, let keymap = originalKeymap else { return nil }
        let device = BackupDevice(
            product: info.product,
            vendorID: info.vendorID,
            productID: info.productID,
            protocolVersion: info.protocolVersion,
            layerCount: info.layerCount,
            rows: info.rows,
            cols: info.cols
        )
        let backup = KeyboardBackup(device: device, keymap: keymap, lighting: originalLighting, macrosBase64: nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Auto-\(formatter.string(from: Date()))"
        do {
            let url = try BackupStore.save(backup, name: name, directory: backupDirectory)
            autoBackupURL = url
            record("备份", "\(reason)自动备份：\(url.lastPathComponent)")
            refreshBackups()
            if gitConfig?.autoCommit == true {
                gitCommitAfterBackup(reason: reason, silent: true)
            }
            return url
        } catch {
            record("备份", "自动备份失败（继续操作）：\(errorText(error))")
            return nil
        }
    }

    // MARK: Git backup repository

    func refreshGitStatus() {
        guard let config = gitConfig else {
            gitStatus = nil
            return
        }
        gitBusy = true
        gitQueue.async {
            let result = Result { try GitService.status(for: config) }
            DispatchQueue.main.async {
                self.gitBusy = false
                switch result {
                case .success(let status):
                    self.gitStatus = status
                    self.gitError = nil
                case .failure(let error):
                    self.gitError = self.errorText(error)
                }
            }
        }
    }

    /// Link an existing Git repository (or initialize one if the folder is not a repo yet).
    func linkGitRepository(at url: URL) {
        guard !gitBusy else { return }
        gitBusy = true
        gitError = nil
        gitMessage = nil
        let localBackups = backups
        gitQueue.async {
            do {
                let config: GitBackupConfig
                if GitService.isRepository(at: url) {
                    config = GitBackupConfig(repoPath: url.path)
                } else {
                    config = try GitService.initRepository(at: url)
                }
                try GitService.ensureBackupsDirectory(config)
                var migrated = 0
                for file in localBackups {
                    let destination = config.backupsDirectory.appendingPathComponent(file.url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destination.path),
                       (try? FileManager.default.copyItem(at: file.url, to: destination)) != nil {
                        migrated += 1
                    }
                }
                try GitBackupStore.save(config)
                let message = "MQ80 Studio: link backup repository" + (migrated > 0 ? " (+\(migrated) existing backups)" : "")
                let commit = try GitService.commitBackups(config, message: message)
                let status = try GitService.status(for: config)
                DispatchQueue.main.async {
                    self.gitConfig = config
                    self.gitStatus = status
                    self.gitBusy = false
                    self.refreshBackups()
                    self.record("Git", "已链接 Git 仓库 \(config.repoPath)")
                    self.gitMessage = commit.committed
                        ? "已链接，并提交了 \(migrated) 个历史备份"
                        : "已链接 Git 备份仓库"
                    self.showToast(.success, "Git 备份仓库已链接")
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitBusy = false
                    let text = self.errorText(error)
                    self.gitError = text
                    self.alert = StudioAlert(title: "链接 Git 仓库失败", message: text)
                }
            }
        }
    }

    func cloneGitRepository(remote: String, to destination: URL) {
        guard !gitBusy else { return }
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = StudioAlert(title: "仓库地址为空", message: "请输入远程仓库地址，例如 git@github.com:you/mq80-backups.git")
            return
        }
        gitBusy = true
        gitError = nil
        gitMessage = nil
        gitQueue.async {
            do {
                try GitService.clone(remote: trimmed, to: destination)
                var config = GitBackupConfig(repoPath: destination.path)
                config.autoCommit = true
                config.autoPush = false
                try GitService.ensureBackupsDirectory(config)
                try GitBackupStore.save(config)
                let status = try GitService.status(for: config)
                DispatchQueue.main.async {
                    self.gitConfig = config
                    self.gitStatus = status
                    self.gitBusy = false
                    self.refreshBackups()
                    self.record("Git", "已克隆并链接 \(trimmed)")
                    self.gitMessage = "已克隆并链接远程备份仓库"
                    self.showToast(.success, "Git 备份仓库已克隆并链接")
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitBusy = false
                    let text = self.errorText(error)
                    self.gitError = text
                    self.alert = StudioAlert(title: "克隆 Git 仓库失败", message: text)
                }
            }
        }
    }

    func unlinkGitRepository() {
        do {
            try GitBackupStore.save(nil)
        } catch {
            alert = StudioAlert(title: "解除链接失败", message: errorText(error))
            return
        }
        gitConfig = nil
        gitStatus = nil
        gitError = nil
        gitMessage = nil
        refreshBackups()
        record("Git", "已解除 Git 备份仓库链接（文件保留）")
        showToast(.info, "已解除 Git 链接，备份切回本地目录")
    }

    func setGitAutoCommit(_ enabled: Bool) {
        guard var config = gitConfig else { return }
        config.autoCommit = enabled
        do {
            try GitBackupStore.save(config)
            gitConfig = config
        } catch {
            alert = StudioAlert(title: "保存设置失败", message: errorText(error))
        }
    }

    func setGitAutoPush(_ enabled: Bool) {
        guard var config = gitConfig else { return }
        config.autoPush = enabled
        do {
            try GitBackupStore.save(config)
            gitConfig = config
        } catch {
            alert = StudioAlert(title: "保存设置失败", message: errorText(error))
        }
    }

    func pushGitRemote() {
        guard let config = gitConfig, !gitBusy else { return }
        gitBusy = true
        gitError = nil
        gitQueue.async {
            do {
                let result = try GitService.push(config)
                let status = try? GitService.status(for: config)
                DispatchQueue.main.async {
                    self.gitBusy = false
                    if result.succeeded {
                        self.gitMessage = "推送成功"
                        self.record("Git", "推送成功")
                        self.showToast(.success, "已推送到远程仓库")
                    } else {
                        self.gitError = result.trimmedStderr.isEmpty ? "推送失败" : result.trimmedStderr
                        self.showToast(.error, "推送失败，请检查远程/凭据")
                    }
                    if let status = status { self.gitStatus = status }
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitBusy = false
                    self.gitError = self.errorText(error)
                    self.showToast(.error, "推送失败")
                }
            }
        }
    }

    func pullGitRemote() {
        guard let config = gitConfig, !gitBusy else { return }
        gitBusy = true
        gitError = nil
        gitQueue.async {
            do {
                let result = try GitService.pull(config)
                DispatchQueue.main.async {
                    self.gitBusy = false
                    if result.succeeded {
                        self.refreshBackups()
                        self.gitMessage = "已从远程拉取"
                        self.record("Git", "拉取成功")
                        self.showToast(.success, "已从远程仓库拉取备份")
                        self.refreshGitStatus()
                    } else {
                        self.gitError = result.trimmedStderr.isEmpty ? "拉取失败" : result.trimmedStderr
                        self.showToast(.error, "拉取失败，请检查远程/凭据")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitBusy = false
                    self.gitError = self.errorText(error)
                    self.showToast(.error, "拉取失败")
                }
            }
        }
    }

    private func gitCommitAfterBackup(reason: String, force: Bool = false, silent: Bool = false) {
        guard let config = gitConfig else { return }
        if !force && !config.autoCommit { return }
        let message = "MQ80 Studio: backup (\(reason))"
        gitQueue.async {
            do {
                let result = try GitService.commitBackups(config, message: message)
                let status = try? GitService.status(for: config)
                DispatchQueue.main.async {
                    if let status = status { self.gitStatus = status }
                    self.gitError = nil
                    self.gitMessage = result.summary
                    self.record("Git", result.summary)
                    if let pushSummary = result.pushSummary {
                        self.record("Git", "推送：\(result.pushed ? "成功" : "失败") \(pushSummary)")
                    }
                    if !silent {
                        if result.committed {
                            self.showToast(.success, result.pushed ? "已提交并推送到 Git 仓库" : "已提交到 Git 仓库")
                        } else {
                            self.showToast(.info, "Git 仓库没有新的备份变更")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let text = self.errorText(error)
                    self.gitError = text
                    self.record("Git", "自动提交失败：\(text)")
                    if !silent {
                        self.showToast(.error, "Git 提交失败，请查看备份页错误信息")
                    }
                }
            }
        }
    }

    // MARK: Keyboard definitions

    func importDefinition(from url: URL) {
        do {
            let imported = try DefinitionStore.shared.importDefinition(from: url)
            record("定义", "已导入 \(imported.name)（\(imported.vendorID)/\(imported.productID)）")
            if let device = selectedDevice,
               imported.vendorID.lowercased() == device.vendorHex.lowercased(),
               imported.productID.lowercased() == device.productHex.lowercased() {
                needsDefinition = false
                autoConnectSuspended = false
                connect()
            } else {
                showToast(.success, "已导入 \(imported.name)；连接匹配的键盘后会自动使用")
            }
        } catch {
            alert = StudioAlert(title: "导入键盘定义失败", message: errorText(error))
        }
    }

    func reloadDefinitionLibrary() {
        DefinitionStore.shared.reload()
        showToast(.info, "已重新加载字典库：\(definitionLibrarySummary)")
        if needsDefinition {
            connect()
        }
    }

    func openDefinitionsFolder() {
        NSWorkspace.shared.open(DefinitionStore.shared.openUserDefinitionsDirectory())
    }

    func selectDevice(_ device: VIADevice) {
        guard device != selectedDevice || !isConnected else { return }
        if isConnected || connecting {
            hid.disconnect()
            teardownConnection(reason: "切换设备")
        }
        selectedDevice = device
        discovered = device
        needsDefinition = false
        autoConnectSuspended = false
        connect()
    }

    // MARK: Diagnostics

    func record(_ category: String, _ message: String) {
        guard debugLoggingEnabled else { return }
        log.append(LogEntry(date: Date(), category: category, message: message))
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    func showToast(_ kind: StudioToast.Kind, _ message: String) {
        let toast = StudioToast(kind: kind, message: message)
        self.toast = toast
        toastClearTask?.cancel()
        toastClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
    }

    // MARK: Helpers

    func errorText(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private func isConnectionLoss(_ error: Error) -> Bool {
        guard let mqError = error as? VIAError else { return false }
        switch mqError {
        case .notConnected, .deviceNotFound:
            return true
        default:
            return false
        }
    }
}
