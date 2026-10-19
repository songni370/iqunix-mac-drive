import Foundation

// MARK: - Config

public struct GitBackupConfig: Codable, Equatable, Sendable {
    public var repoPath: String
    public var backupsSubdirectory: String
    public var autoCommit: Bool
    public var autoPush: Bool

    public init(
        repoPath: String,
        backupsSubdirectory: String = "backups",
        autoCommit: Bool = true,
        autoPush: Bool = false
    ) {
        self.repoPath = repoPath
        self.backupsSubdirectory = backupsSubdirectory
        self.autoCommit = autoCommit
        self.autoPush = autoPush
    }

    public var repoURL: URL {
        URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public var backupsDirectory: URL {
        repoURL.appendingPathComponent(backupsSubdirectory, isDirectory: true)
    }

    public var displayPath: String {
        (repoPath as NSString).expandingTildeInPath
    }
}

public enum GitBackupStore {
    public static var configURL: URL {
        BackupStore.baseDirectory.appendingPathComponent("git-backup.json")
    }

    public static func load() -> GitBackupConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(GitBackupConfig.self, from: data)
    }

    @discardableResult
    public static func save(_ config: GitBackupConfig?) throws -> URL? {
        if let config = config {
            let directory = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: configURL, options: .atomic)
            return configURL
        }
        if FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.removeItem(at: configURL)
        }
        return nil
    }
}

// MARK: - Models

public struct GitRepoStatus: Equatable, Sendable {
    public let path: String
    public let branch: String
    public let remoteURL: String?
    public let lastCommitShort: String?
    public let lastCommitSubject: String?
    public let lastCommitDate: Date?
    public let dirtyFileCount: Int
    public let backupDirtyFileCount: Int
    public let ahead: Int?
    public let behind: Int?

    public var hasRemote: Bool { remoteURL?.isEmpty == false }
    public var isClean: Bool { dirtyFileCount == 0 }

    public init(
        path: String,
        branch: String,
        remoteURL: String?,
        lastCommitShort: String?,
        lastCommitSubject: String?,
        lastCommitDate: Date?,
        dirtyFileCount: Int,
        backupDirtyFileCount: Int,
        ahead: Int?,
        behind: Int?
    ) {
        self.path = path
        self.branch = branch
        self.remoteURL = remoteURL
        self.lastCommitShort = lastCommitShort
        self.lastCommitSubject = lastCommitSubject
        self.lastCommitDate = lastCommitDate
        self.dirtyFileCount = dirtyFileCount
        self.backupDirtyFileCount = backupDirtyFileCount
        self.ahead = ahead
        self.behind = behind
    }
}

public struct GitCommitResult: Sendable {
    public let committed: Bool
    public let shortHash: String?
    public let pushed: Bool
    public let pushSummary: String?
    public let summary: String

    public init(committed: Bool, shortHash: String?, pushed: Bool, pushSummary: String?, summary: String) {
        self.committed = committed
        self.shortHash = shortHash
        self.pushed = pushed
        self.pushSummary = pushSummary
        self.summary = summary
    }
}

public struct GitOutput: Sendable {
    public let arguments: [String]
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
    public var trimmedStdout: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedStderr: String { stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
}

public enum GitError: Error, LocalizedError {
    case gitNotFound
    case notRepository(String)
    case destinationNotEmpty(String)
    case noRemote
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)
    case timedOut(arguments: [String])

    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "系统里找不到 git（/usr/bin/git）。请安装 Xcode Command Line Tools：xcode-select --install"
        case .notRepository(let path):
            return "该目录不是 Git 仓库：\(path)"
        case .destinationNotEmpty(let path):
            return "目标目录不是空目录，无法克隆：\(path)"
        case .noRemote:
            return "这个 Git 仓库没有 remote（origin），无法推送/拉取。请先添加远程仓库：git remote add origin <url>"
        case .commandFailed(let arguments, let exitCode, let stderr):
            let command = (["git"] + arguments).joined(separator: " ")
            let detail = stderr.isEmpty ? "（无错误输出）" : stderr
            return "git 命令失败（exit \(exitCode)）：\(command)\n\(detail)"
        case .timedOut(let arguments):
            return "git 命令超时：\(( ["git"] + arguments).joined(separator: " "))"
        }
    }
}

// MARK: - Service

public enum GitService {
    public static let gitPath = "/usr/bin/git"

    public static func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: gitPath)
    }

    @discardableResult
    public static func run(
        _ arguments: [String],
        in directory: URL? = nil,
        timeout: TimeInterval = 60
    ) throws -> GitOutput {
        guard isAvailable() else { throw GitError.gitNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        if let directory = directory {
            process.currentDirectoryURL = directory
        }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }
        var timedOut = false
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
            _ = semaphore.wait(timeout: .now() + 2)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return GitOutput(
            arguments: arguments,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }

    public static func isRepository(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard let output = try? run(["rev-parse", "--is-inside-work-tree"], in: url) else { return false }
        return output.succeeded && output.trimmedStdout == "true"
    }

    public static func currentBranch(in repo: URL) throws -> String {
        if let result = try? run(["symbolic-ref", "--short", "-q", "HEAD"], in: repo), result.succeeded {
            return result.trimmedStdout
        }
        if let result = try? run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo), result.succeeded, result.trimmedStdout != "HEAD" {
            return result.trimmedStdout
        }
        return "main"
    }

    public static func remoteURL(in repo: URL) -> String? {
        guard let result = try? run(["config", "--get", "remote.origin.url"], in: repo), result.succeeded else {
            return nil
        }
        let remote = result.trimmedStdout
        return remote.isEmpty ? nil : remote
    }

    public static func status(for config: GitBackupConfig) throws -> GitRepoStatus {
        let repo = config.repoURL
        guard isRepository(at: repo) else { throw GitError.notRepository(repo.path) }

        let branch = try currentBranch(in: repo)
        let remote = remoteURL(in: repo)

        var lastShort: String?
        var lastSubject: String?
        var lastDate: Date?
        if let log = try? run(["log", "-1", "--pretty=%h%x1f%s%x1f%cI"], in: repo), log.succeeded, !log.trimmedStdout.isEmpty {
            let parts = log.trimmedStdout.components(separatedBy: "\u{1f}")
            if parts.count >= 1 { lastShort = parts[0] }
            if parts.count >= 2 { lastSubject = parts[1] }
            if parts.count >= 3 {
                lastDate = ISO8601DateFormatter().date(from: parts[2])
            }
        }

        let dirty = (try? run(["status", "--porcelain"], in: repo))?.stdout ?? ""
        let dirtyCount = dirty.split(separator: "\n").count

        let backupStatus = (try? run(["status", "--porcelain", "--", config.backupsSubdirectory], in: repo))?.stdout ?? ""
        let backupDirtyCount = backupStatus.split(separator: "\n").count

        var ahead: Int?
        var behind: Int?
        if remote != nil,
           let countResult = try? run(["rev-list", "--left-right", "--count", "@{u}...HEAD"], in: repo),
           countResult.succeeded {
            let parts = countResult.trimmedStdout.split(separator: "\t").compactMap { Int($0) }
            if parts.count == 2 {
                behind = parts[0]
                ahead = parts[1]
            }
        }

        return GitRepoStatus(
            path: repo.path,
            branch: branch,
            remoteURL: remote,
            lastCommitShort: lastShort,
            lastCommitSubject: lastSubject,
            lastCommitDate: lastDate,
            dirtyFileCount: dirtyCount,
            backupDirtyFileCount: backupDirtyCount,
            ahead: ahead,
            behind: behind
        )
    }

    public static func ensureBackupsDirectory(_ config: GitBackupConfig) throws {
        try FileManager.default.createDirectory(at: config.backupsDirectory, withIntermediateDirectories: true)
    }

    private static func ensureIdentity(in repo: URL) throws {
        let name = try? run(["config", "--get", "user.name"], in: repo)
        let email = try? run(["config", "--get", "user.email"], in: repo)
        let hasName = name?.succeeded == true && !name!.trimmedStdout.isEmpty
        let hasEmail = email?.succeeded == true && !email!.trimmedStdout.isEmpty
        if !hasName {
            _ = try run(["config", "user.name", "MQ80 Studio"], in: repo)
        }
        if !hasEmail {
            _ = try run(["config", "user.email", "iqunix-drive@localhost"], in: repo)
        }
    }

    @discardableResult
    public static func initRepository(at url: URL) throws -> GitBackupConfig {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let result = try run(["init"], in: url)
        guard result.succeeded else {
            throw GitError.commandFailed(arguments: result.arguments, exitCode: result.exitCode, stderr: result.trimmedStderr)
        }
        var config = GitBackupConfig(repoPath: url.path)
        try ensureBackupsDirectory(config)
        let keep = config.backupsDirectory.appendingPathComponent(".gitkeep")
        if !FileManager.default.fileExists(atPath: keep.path) {
            FileManager.default.createFile(atPath: keep.path, contents: Data())
        }
        try ensureIdentity(in: url)
        _ = try? run(["add", "--", config.backupsSubdirectory], in: url)
        _ = try? run(["commit", "-m", "MQ80 Studio: initialize backup repository"], in: url)
        config.autoCommit = true
        config.autoPush = false
        return config
    }

    public static func clone(remote: String, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
            guard contents.isEmpty else { throw GitError.destinationNotEmpty(destination.path) }
        }
        // Local path remotes must be resolved against the caller's cwd before we
        // change git's working directory, otherwise relative paths break.
        var remoteSpec = remote
        let looksLikeURL = remote.contains("://") || remote.hasPrefix("git@") || remote.hasPrefix("ssh")
        if !looksLikeURL {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            remoteSpec = URL(fileURLWithPath: remote, relativeTo: cwd).standardizedFileURL.path
        }
        let result = try run(["clone", remoteSpec, destination.path], in: parent, timeout: 180)
        guard result.succeeded else {
            throw GitError.commandFailed(arguments: result.arguments, exitCode: result.exitCode, stderr: result.trimmedStderr)
        }
    }

    // MARK: Sync

    @discardableResult
    public static func commitBackups(
        _ config: GitBackupConfig,
        message: String,
        pushIfConfigured: Bool? = nil
    ) throws -> GitCommitResult {
        let repo = config.repoURL
        guard isRepository(at: repo) else { throw GitError.notRepository(repo.path) }
        try ensureBackupsDirectory(config)

        let pending = try run(["status", "--porcelain", "--", config.backupsSubdirectory], in: repo)
        guard pending.succeeded else {
            throw GitError.commandFailed(arguments: pending.arguments, exitCode: pending.exitCode, stderr: pending.trimmedStderr)
        }
        if pending.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return GitCommitResult(committed: false, shortHash: nil, pushed: false, pushSummary: nil, summary: "没有新的备份文件需要提交")
        }

        try ensureIdentity(in: repo)
        let add = try run(["add", "--", config.backupsSubdirectory], in: repo)
        guard add.succeeded else {
            throw GitError.commandFailed(arguments: add.arguments, exitCode: add.exitCode, stderr: add.trimmedStderr)
        }

        let commit = try run(["commit", "-m", message, "--", config.backupsSubdirectory], in: repo)
        guard commit.succeeded else {
            throw GitError.commandFailed(arguments: commit.arguments, exitCode: commit.exitCode, stderr: commit.trimmedStderr)
        }
        let hash = (try? run(["rev-parse", "--short", "HEAD"], in: repo))?.trimmedStdout

        let shouldPush = pushIfConfigured ?? config.autoPush
        var pushed = false
        var pushSummary: String?
        if shouldPush {
            let push = try push(config)
            pushed = push.succeeded
            pushSummary = push.succeeded
                ? (push.trimmedStderr.isEmpty ? "推送成功" : push.trimmedStderr)
                : push.trimmedStderr
        }
        return GitCommitResult(
            committed: true,
            shortHash: hash,
            pushed: pushed,
            pushSummary: pushSummary,
            summary: "已提交 \(hash ?? "")"
        )
    }

    @discardableResult
    public static func push(_ config: GitBackupConfig) throws -> GitOutput {
        let repo = config.repoURL
        guard isRepository(at: repo) else { throw GitError.notRepository(repo.path) }
        guard remoteURL(in: repo) != nil else { throw GitError.noRemote }
        let branch = try currentBranch(in: repo)

        var result = try run(["push"], in: repo, timeout: 120)
        if !result.succeeded {
            let message = result.trimmedStderr.lowercased()
            if message.contains("no upstream") || message.contains("set-upstream") || message.contains("has no upstream branch") {
                result = try run(["push", "-u", "origin", branch], in: repo, timeout: 120)
            }
        }
        return result
    }

    @discardableResult
    public static func pull(_ config: GitBackupConfig) throws -> GitOutput {
        let repo = config.repoURL
        guard isRepository(at: repo) else { throw GitError.notRepository(repo.path) }
        guard remoteURL(in: repo) != nil else { throw GitError.noRemote }
        return try run(["pull", "--ff-only"], in: repo, timeout: 120)
    }
}
