import Foundation


@main
struct MQ80CLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            FileHandle.standardError.write(Data(("错误: " + message + "\n").utf8))
            exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "info":
            try info()
        case "devices":
            try listDevices()
        case "import-definition":
            try importDefinition(arguments: rest)
        case "definitions":
            try listDefinitions()
        case "check-definitions":
            try checkDefinitions()
        case "lookup-definition":
            try lookupDefinition(arguments: rest)
        case "dump":
            try dump()
        case "lighting":
            try lighting(arguments: rest)
        case "backup":
            try backup(arguments: rest)
        case "restore":
            try restore(arguments: rest)
        case "read-macros":
            try readMacros()
        case "writeback-test":
            try writebackTest()
        case "setkey":
            try setKey(arguments: rest)
        case "repair":
            try repair()
        case "git-link":
            try gitLink(arguments: rest)
        case "git-clone":
            try gitClone(arguments: rest)
        case "git-status":
            try gitStatus()
        case "git-backup":
            try gitBackup(arguments: rest)
        case "git-push":
            try gitPush()
        case "git-pull":
            try gitPull()
        case "git-unlink":
            try gitUnlink()
        case "set-keycode":
            try setKeycodeRaw(arguments: rest)
        case "read-buffer":
            try readBuffer(arguments: rest)
        case "write-buffer":
            try writeBuffer(arguments: rest)
        case "locate":
            try locate(arguments: rest)
        case "selftest":
            try selftest()
        case "help", "--help", "-h":
            printHelp()
        default:
            printHelp()
            throw VIAError.backupCorrupted("未知命令 \(command)")
        }
    }

    static func printHelp() {
        print("""
        iqunixctl — IQUNIX-DRIVE 命令行工具（通用 VIA 键盘配置）

        用法:
          iqunixctl info                    显示设备与协议信息
          iqunixctl dump [--raw]            读取并显示 4 层键位（默认用键名显示）
          iqunixctl lighting                显示当前灯效
          iqunixctl lighting --brightness 5 --effect 1 --speed 2 --hue 0 --sat 255
                                          设置灯效（写入并保存）
          iqunixctl backup [路径]           读取完整配置并保存备份 JSON
          iqunixctl restore <备份.json> [--yes]
                                          从备份恢复键位/灯效
          iqunixctl read-macros             读取宏缓冲区（只读）
          iqunixctl writeback-test          读取键位后原样写回并校验（安全写测试）
          iqunixctl setkey <layer> <row> <col> <keycode> [--restore]
                                          修改单个键位（调试用）
          iqunixctl read-buffer <byteOffset> <size>   读取动态键位原始字节（调试）
          iqunixctl write-buffer <byteOffset> <hex>   写入原始字节（调试，危险）
          iqunixctl locate <hex>            查找某个键码在 4 层中的位置
          iqunixctl set-keycode <layer> <row> <col> <hexKeycode>  单键写入（0x05，调试）
          iqunixctl repair                 修复因写入边界 bug 导致的层错位
          iqunixctl git-link <路径> [--auto-push]
                                          链接/初始化本地 Git 备份仓库
          iqunixctl git-clone <remote> <路径> [--auto-push]
                                          克隆远程仓库并链接为备份仓库
          iqunixctl git-status             显示 Git 备份仓库状态
          iqunixctl git-backup [--push]    读取键盘配置、写入 Git 仓库并提交（可推送）
          iqunixctl git-push / git-pull    推送 / 拉取远程备份仓库
          iqunixctl git-unlink             解除 Git 备份仓库链接
          iqunixctl selftest                只读自检（设备/键位/灯效/宏）
          iqunixctl help                    显示本帮助
        """)
    }

    // MARK: - Commands

    static func listDevices() throws {
        let devices = VIADiscovery.find()
        if devices.isEmpty {
            print("没有发现可配置的 VIA 键盘（Raw HID 0xFF60/0x61）。")
            return
        }
        for device in devices {
            let definition = DefinitionStore.shared.resolve(device: device)
            let status = definition.map { "定义：\($0.definition.name)（\($0.source.title)）" } ?? "缺少键盘定义"
            print("设备: \(device.displayName)  VID=0x\(String(format: "%04X", device.vendorID)) PID=0x\(String(format: "%04X", device.productID))  位置=0x\(String(format: "%X", device.locationID))  \(status)")
        }
    }

    static func importDefinition(arguments: [String]) throws {
        guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
            throw VIAError.backupCorrupted("用法: iqunixctl import-definition <VIA键盘定义.json>")
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let definition = try DefinitionStore.shared.importDefinition(from: url)
        print("已导入键盘定义：\(definition.name)（VID \(definition.vendorID) / PID \(definition.productID)）")
        print("定义目录：\(DefinitionStore.shared.userDefinitionsDirectory.path)")
    }

    static func listDefinitions() throws {
        DefinitionStore.shared.reload()
        print("内置 VIA 定义：\(DefinitionStore.shared.builtinCount) 个（含 MQ80 内置定义）")
        print("用户导入定义：\(DefinitionStore.shared.userCount) 个")
        print("用户定义目录：\(DefinitionStore.shared.userDefinitionsDirectory.path)")
        if DefinitionStore.shared.bundledDefinitionsDirectory == nil {
            print("警告：没有找到内置定义库，请运行 scripts/gen_via_definitions.py 后重新构建。")
        }
    }

    static func checkDefinitions() throws {
        guard let directory = DefinitionStore.shared.bundledDefinitionsDirectory else {
            throw VIAError.backupCorrupted("没有找到内置定义库")
        }
        let indexURL = directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else {
            throw VIAError.backupCorrupted("无法读取定义库索引")
        }
        var ok = 0
        var failed: [String] = []
        var noLayout: [String] = []
        for entry in entries {
            guard let file = entry["file"] as? String else { continue }
            let url = directory.appendingPathComponent(file)
            guard let jsonData = try? Data(contentsOf: url),
                  let object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
                  let definition = KeyboardDefinition.parse(root: object) else {
                failed.append(file)
                continue
            }
            ok += 1
            if definition.keys.isEmpty { noLayout.append(file) }
        }
        print("内置定义总数: \(entries.count)")
        print("解析成功: \(ok)   失败: \(failed.count)   无布局: \(noLayout.count)")
        for file in failed.prefix(10) { print("  失败: \(file)") }
        for file in noLayout.prefix(10) { print("  无布局: \(file)") }
    }

    static func lookupDefinition(arguments: [String]) throws {
        guard arguments.count >= 2,
              let vid = UInt16(arguments[0].replacingOccurrences(of: "0x", with: ""), radix: 16),
              let pid = UInt16(arguments[1].replacingOccurrences(of: "0x", with: ""), radix: 16) else {
            throw VIAError.backupCorrupted("用法: iqunixctl lookup-definition <vid> <pid>（例如 320F 5055）")
        }
        DefinitionStore.shared.reload()
        guard let resolved = DefinitionStore.shared.resolve(vendorID: Int(vid), productID: Int(pid)) else {
            print("没有匹配的定义")
            return
        }
        let def = resolved.definition
        print("匹配定义: \(def.name)")
        print("来源: \(resolved.source.title)  \(resolved.detail)")
        print("VID/PID: \(def.vendorID) / \(def.productID)")
        print("矩阵: \(def.rows) × \(def.cols)   键位: \(def.keys.count)")
        print("灯效: \(def.lighting.isSupported ? "\(def.lighting.label) · CH\(def.lighting.channel)" : "未声明")")
        print("自定义键: \(def.customKeycodeNames.count) 个")
    }

    static func info() throws {
        let devices = VIADiscovery.find()
        if devices.isEmpty {
            throw VIAError.deviceNotFound
        }
        for device in devices {
            print("设备: \(device.displayName)  VID=0x\(String(format: "%04X", device.vendorID)) PID=0x\(String(format: "%04X", device.productID))  位置=0x\(String(format: "%X", device.locationID))  传输=\(device.transport)")
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        let definition = controller.definition
        let resolvedSource = DefinitionStore.shared.resolve(vendorID: controller.info.vendorID, productID: controller.info.productID)
        print("键盘定义: \(definition.name)  来源：\(resolvedSource?.source.title ?? "未知")\(definition.hasLayout ? "" : "（缺少布局，仅原始矩阵）")")
        if !definition.layoutOptionLabels.isEmpty {
            print("布局选项: \(definition.layoutOptionLabels.count) 组（当前版本按默认布局编辑）")
        }
        print("协议版本: \(controller.info.protocolVersion) (0x\(String(format: "%04X", controller.info.protocolVersion)))")
        print("动态层数: \(controller.info.layerCount)")
        print("灯效数量: \(definition.effects.count)")
        print("自定义键: \(definition.customKeycodeNames.joined(separator: ", "))")
        print("备份目录: \(BackupStore.backupsDirectory.path)")
    }

    static func dump() throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        let keymap = try controller.readKeymap()
        let definition = controller.definition
        printKeymap(keymap, definition: definition, protocolVersion: controller.info.protocolVersion)
    }

    static func printKeymap(_ keymap: Keymap, definition: KeyboardDefinition, protocolVersion: Int) {
        for layer in 0..<keymap.layerCount {
            print("\n===== Layer \(layer) =====")
            var index = 0
            for row in 0..<definition.rows {
                var line = "r\(row):"
                for col in 0..<definition.cols {
                    let value = keymap.value(layer: layer, index: index)
                    let label = KeycodeCatalog.label(
                        for: value,
                        customKeycodeNames: definition.customKeycodeNames,
                        layerCount: keymap.layerCount,
                        protocolVersion: protocolVersion
                    )
                    line += String(format: " %-10@", label as NSString)
                    _ = col
                    index += 1
                }
                print(line)
            }
        }
    }

    static func lighting(arguments: [String]) throws {
        let shouldSet = arguments.contains { $0.hasPrefix("--") && $0 != "--help" }
        if arguments.contains("--help") {
            print("用法: iqunixctl lighting [--brightness 0-9] [--effect N] [--speed 0-4] [--hue 0-255] [--sat 0-255]")
            return
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        var state = try controller.readLighting()
        if shouldSet {
            let options = parseOptions(arguments: arguments)
            if let value = options["brightness"], let int = Int(value) { state.brightness = int }
            if let value = options["effect"], let int = Int(value) { state.effect = int }
            if let value = options["speed"], let int = Int(value) { state.effectSpeed = int }
            if let value = options["hue"], let int = Int(value) { state.hue = int }
            if let value = options["sat"], let int = Int(value) { state.saturation = int }
            try controller.applyLighting(state)
            print("已写入并保存灯效。")
        }
        let result = try controller.readLighting()
        print("亮度: \(result.brightness)")
        print("灯效: \(result.effect)")
        print("速度: \(result.effectSpeed)")
        print("颜色: hue=\(result.hue) sat=\(result.saturation)")
    }

    static func backup(arguments: [String]) throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        let keymap = try controller.readKeymap()
        let lighting = try? controller.readLighting()
        let macros = try? controller.readMacros()
        let backup = KeyboardBackup(controller: controller, keymap: keymap, lighting: lighting, macros: macros)

        let url: URL
        if let path = arguments.first(where: { !$0.hasPrefix("--") }) {
            let expanded = (path as NSString).expandingTildeInPath
            url = URL(fileURLWithPath: expanded)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(backup).write(to: url, options: .atomic)
        } else {
            url = try BackupStore.save(backup)
        }
        print("备份已保存: \(url.path)")
        print("层数: \(keymap.layerCount)  键位: \(keymap.matrixCount)  灯效: \(lighting != nil ? "已包含" : "读取失败")")
    }

    static func restore(arguments: [String]) throws {
        guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
            throw VIAError.backupCorrupted("缺少备份文件路径")
        }
        let confirmed = arguments.contains("--yes")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let backup = try BackupStore.load(url)
        print("准备恢复: \(backup.device.product)  \(backup.device.layerCount) 层  \(backup.keymap.matrixCount) 键  创建于 \(backup.createdAt)")
        if !confirmed {
            print("这是写操作。确认请加 --yes 重新运行。")
            return
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        if let lighting = backup.lighting {
            try controller.applyLighting(lighting)
        }
        try controller.writeKeymap(backup.keymap)
        print("恢复完成并通过回读校验。")
    }

    static func readMacros() throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        guard let macros = try controller.readMacros() else {
            print("设备未返回宏信息。")
            return
        }
        print("宏槽: \(macros.count)  缓冲区: \(macros.bufferSize) 字节")
        print("前 64 字节: \(Hex.string(macros.data.prefix(64)))")
    }

    static func writebackTest() throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        let keymap = try controller.readKeymap()
        print("已读取 \(keymap.layerCount) 层键位，开始原样写回…")
        try controller.writeKeymap(keymap)
        print("写回并回读校验通过 ✅")
    }

    static func setKey(arguments: [String]) throws {
        guard arguments.count >= 4 else {
            throw VIAError.backupCorrupted("用法: iqunixctl setkey <layer> <row> <col> <keycode> [--restore]")
        }
        guard let layer = Int(arguments[0]), let row = Int(arguments[1]), let col = Int(arguments[2]) else {
            throw VIAError.backupCorrupted("layer/row/col 需要是数字")
        }
        let rawKeycode = arguments[3]
        let keycode: UInt16
        if rawKeycode.lowercased().hasPrefix("0x"), let value = UInt16(rawKeycode.dropFirst(2), radix: 16) {
            keycode = value
        } else if let value = UInt16(rawKeycode) {
            keycode = value
        } else {
            throw VIAError.backupCorrupted("无法解析键码 \(rawKeycode)")
        }

        let controller = try VIAController.open()
        defer { controller.close() }
        let definition = controller.definition
        guard let index = definition.matrixIndex(row: row, col: col) else {
            throw VIAError.backupCorrupted("矩阵坐标超出范围")
        }
        var keymap = try controller.readKeymap()
        guard layer >= 0, layer < keymap.layerCount else {
            throw VIAError.backupCorrupted("层数超出范围")
        }
        let original = keymap.value(layer: layer, index: index)
        keymap.setValue(keycode, layer: layer, index: index)
        try controller.writeKeymap(keymap)
        print(String(format: "已写入 L%d r%d c%d: 0x%04X -> 0x%04X", layer, row, col, original, keycode))
        if arguments.contains("--restore") {
            var restored = try controller.readKeymap()
            restored.setValue(original, layer: layer, index: index)
            try controller.writeKeymap(restored)
            print(String(format: "已恢复原值 0x%04X", original))
        }
    }

    static func repair() throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        let current = try controller.readKeymap()
        guard current.layerCount >= 4, current.matrixCount >= 16 else {
            throw VIAError.writeVerificationFailed("当前键盘层数/矩阵不符合 MQ80 修复条件")
        }
        // Recover from the 0x100/0x200/0x300 write-boundary bug:
        // base layer is intact at layer 2; Fn layer is split between layer 0
        // (first 28 bytes) and layer 1 (the rest).
        let base = current.layers[2]
        var fn = base
        for index in 1..<14 { fn[index] = current.layers[0][index] }
        fn[0] = 0x0000
        for index in 15..<base.count { fn[index] = current.layers[1][index] }
        fn[14] = 0x0000
        let repaired = Keymap(layers: [base, fn, base, base])
        try controller.writeKeymap(repaired)
        print("键位已修复并通过回读校验 ✅")
    }

    static func setKeycodeRaw(arguments: [String]) throws {
        guard arguments.count >= 4,
              let layer = Int(arguments[0]), let row = Int(arguments[1]), let col = Int(arguments[2]),
              let keycode = UInt16(arguments[3].hasPrefix("0x") ? String(arguments[3].dropFirst(2)) : arguments[3], radix: 16) else {
            throw VIAError.backupCorrupted("用法: iqunixctl set-keycode <layer> <row> <col> <hexKeycode>")
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        let payload: [UInt8] = [0x05, UInt8(layer), UInt8(row), UInt8(col), UInt8((keycode >> 8) & 0xFF), UInt8(keycode & 0xFF)]
        let response = try controller.connection.request(payload)
        print("set-keycode ->", Hex.string(response.prefix(8)))
    }

    static func readBuffer(arguments: [String]) throws {
        guard arguments.count >= 2, let offset = parseNumber(arguments[0]), let size = Int(arguments[1]), size > 0, size <= 28 else {
            throw VIAError.backupCorrupted("用法: iqunixctl read-buffer <offset> <size<=28>")
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        let response = try controller.connection.request([0x12, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(size)])
        print(String(format: "offset=0x%04X size=%d ->", offset, size), Hex.string(response.prefix(4 + size)))
    }

    static func writeBuffer(arguments: [String]) throws {
        guard arguments.count >= 2, let offset = parseNumber(arguments[0]) else {
            throw VIAError.backupCorrupted("用法: iqunixctl write-buffer <offset> <hex bytes，如 0068>")
        }
        guard let bytes = Hex.bytes(arguments[1]), !bytes.isEmpty, bytes.count <= 28 else {
            throw VIAError.backupCorrupted("无法解析字节或长度超过 28")
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        var payload: [UInt8] = [0x13, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(bytes.count)]
        payload.append(contentsOf: bytes)
        let response = try controller.connection.request(payload)
        print(String(format: "write offset=0x%04X size=%d ->", offset, bytes.count), Hex.string(response.prefix(6)))
    }

    static func locate(arguments: [String]) throws {
        guard let raw = arguments.first, let value = UInt16(raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw, radix: 16) else {
            throw VIAError.backupCorrupted("用法: iqunixctl locate <hex keycode，如 0068>")
        }
        let controller = try VIAController.open()
        defer { controller.close() }
        let keymap = try controller.readKeymap()
        var found = false
        for layer in 0..<keymap.layerCount {
            for index in 0..<keymap.matrixCount where keymap.value(layer: layer, index: index) == value {
                print("L\(layer) index=\(index) (r\(index / controller.definition.cols),c\(index % controller.definition.cols))")
                found = true
            }
        }
        if !found { print("未找到 0x\(String(format: "%04X", value))") }
    }

    static func selftest() throws {
        let controller = try VIAController.open()
        defer { controller.close() }
        print("协议版本: \(controller.info.protocolVersion)")
        let keymap = try controller.readKeymap()
        print("键位读取: \(keymap.layerCount) 层 x \(keymap.matrixCount) 键 ✅")
        let lighting = try controller.readLighting()
        print("灯效读取: \(lighting.brightness)/\(lighting.effect)/\(lighting.effectSpeed)/\(lighting.hue)/\(lighting.saturation) ✅")
        if let macros = try controller.readMacros() {
            print("宏读取: \(macros.count) 槽 / \(macros.bufferSize) 字节 ✅")
        }
        print("只读自检通过 ✅")
    }

    // MARK: - Helpers


    // MARK: - Git backup

    static func loadGitConfigOrThrow() throws -> GitBackupConfig {
        guard let config = GitBackupStore.load() else {
            throw VIAError.backupCorrupted("尚未链接 Git 备份仓库，请先运行 iqunixctl git-link <路径> 或 git-clone <remote> <路径>")
        }
        return config
    }

    static func printGitStatus(_ config: GitBackupConfig, _ status: GitRepoStatus) {
        print("Git 备份仓库: \(status.path)")
        print("分支: \(status.branch)   远程: \(status.remoteURL ?? "（无）")")
        if let short = status.lastCommitShort {
            print("最近提交: \(short) \(status.lastCommitSubject ?? "")")
        } else {
            print("最近提交: （还没有提交）")
        }
        var line = "工作区: \(status.isClean ? "干净" : "\(status.dirtyFileCount) 个未提交文件")"
        if status.backupDirtyFileCount > 0 { line += "（其中备份目录 \(status.backupDirtyFileCount) 个）" }
        if let ahead = status.ahead, let behind = status.behind {
            line += "  领先 \(ahead) / 落后 \(behind)"
        }
        print(line)
        print("备份目录: \(config.backupsDirectory.path)")
    }

    static func gitLink(arguments: [String]) throws {
        guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
            throw VIAError.backupCorrupted("用法: iqunixctl git-link <仓库路径> [--auto-push]")
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let config: GitBackupConfig
        if GitService.isRepository(at: url) {
            config = GitBackupConfig(repoPath: url.path)
            print("链接已有 Git 仓库: \(config.repoPath)")
        } else {
            config = try GitService.initRepository(at: url)
            print("已初始化新的 Git 仓库: \(config.repoPath)")
        }
        var saved = config
        saved.autoPush = arguments.contains("--auto-push")
        try GitBackupStore.save(saved)
        let status = try GitService.status(for: saved)
        printGitStatus(saved, status)
    }

    static func gitClone(arguments: [String]) throws {
        let positional = arguments.filter { !$0.hasPrefix("--") }
        guard positional.count >= 2 else {
            throw VIAError.backupCorrupted("用法: iqunixctl git-clone <remote> <目标路径> [--auto-push]")
        }
        let remote = positional[0]
        let url = URL(fileURLWithPath: (positional[1] as NSString).expandingTildeInPath)
        try GitService.clone(remote: remote, to: url)
        var config = GitBackupConfig(repoPath: url.path)
        config.autoPush = arguments.contains("--auto-push")
        try GitBackupStore.save(config)
        print("已克隆并链接: \(url.path)")
        printGitStatus(config, try GitService.status(for: config))
    }

    static func gitStatus() throws {
        let config = try loadGitConfigOrThrow()
        printGitStatus(config, try GitService.status(for: config))
    }

    static func gitBackup(arguments: [String]) throws {
        let config = try loadGitConfigOrThrow()
        let controller = try VIAController.open()
        defer { controller.close() }
        let keymap = try controller.readKeymap()
        let lighting = try controller.readLighting()
        let macros = try? controller.readMacros()
        let backup = KeyboardBackup(controller: controller, keymap: keymap, lighting: lighting, macros: macros)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Keyboard-\(formatter.string(from: backup.createdAt))"
        let url = try BackupStore.save(backup, name: filename, directory: config.backupsDirectory)
        print("备份已写入: \(url.path)")

        let message = "MQ80 Studio: backup \(filename)"
        let push = arguments.contains("--push") ? true : nil
        let result = try GitService.commitBackups(config, message: message, pushIfConfigured: push)
        print(result.summary)
        if let pushSummary = result.pushSummary, !pushSummary.isEmpty {
            print("推送: \(result.pushed ? "成功" : "失败") \(pushSummary)")
        }
        printGitStatus(config, try GitService.status(for: config))
    }

    static func gitPush() throws {
        let config = try loadGitConfigOrThrow()
        let result = try GitService.push(config)
        guard result.succeeded else {
            throw VIAError.backupCorrupted(result.trimmedStderr.isEmpty ? "推送失败" : result.trimmedStderr)
        }
        print("推送成功。")
    }

    static func gitPull() throws {
        let config = try loadGitConfigOrThrow()
        let result = try GitService.pull(config)
        guard result.succeeded else {
            throw VIAError.backupCorrupted(result.trimmedStderr.isEmpty ? "拉取失败" : result.trimmedStderr)
        }
        print("拉取成功。")
        printGitStatus(config, try GitService.status(for: config))
    }

    static func gitUnlink() throws {
        try GitBackupStore.save(nil)
        print("已解除 Git 备份仓库链接（本地文件不会被删除）。")
    }

    static func parseNumber(_ string: String) -> Int? {
        if string.lowercased().hasPrefix("0x") {
            return Int(string.dropFirst(2), radix: 16)
        }
        return Int(string)
    }

    static func parseOptions(arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    result[key] = arguments[index + 1]
                    index += 2
                    continue
                }
                result[key] = "true"
            }
            index += 1
        }
        return result
    }
}
