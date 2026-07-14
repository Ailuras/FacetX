import Foundation

struct LocalGitRepositoryInfo: Equatable {
    let rootPath: String
    let remoteURL: String?
    let fullName: String?
    let branch: String?
}

struct LocalGitCommandResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    var message: String {
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { return error }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalGitBranchState: Equatable, Sendable {
    let current: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let localBranches: [String]
}

struct LocalGitActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let commitCount: Int

    var id: Date { date }
}

/// A commit from the local Git history.
struct LocalGitCommit: Identifiable, Equatable, Sendable {
    let id: String
    var shortSHA: String { String(id.prefix(7)) }
    let message: String
    let authorName: String
    let date: Date
    let refs: String

    var summary: String {
        message.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? shortSHA
    }

    var body: String? {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return nil }
        let text = lines.dropFirst()
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func htmlURL(repoFullName: String?) -> URL? {
        guard let name = repoFullName else { return nil }
        return URL(string: "https://github.com/\(name)/commit/\(id)")
    }
}

/// One actionable index or working-tree change. A path modified in both areas
/// appears twice so stage/unstage and diff selection remain unambiguous.
struct LocalGitStatusEntry: Identifiable, Equatable, Sendable {
    enum Area: String, Equatable, Sendable {
        case staged
        case unstaged
    }

    enum State: String, Equatable, Sendable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case untracked = "?"
        case conflicted = "U"
        case other
    }

    let path: String
    let originalPath: String?
    let state: State
    let area: Area

    var id: String { "\(area.rawValue):\(path)" }
    var staged: Bool { area == .staged }

    var icon: String {
        switch state {
        case .modified: return "pencil.circle.fill"
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed, .copied: return "arrow.triangle.2.circlepath"
        case .untracked: return "questionmark.circle.fill"
        case .conflicted: return "exclamationmark.triangle.fill"
        case .other: return "circle.fill"
        }
    }
}

enum LocalGitRepository {
    static func inspect(path: String) -> LocalGitRepositoryInfo? {
        let startURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        guard let root = gitRoot(startingAt: startURL) else { return nil }
        let remoteURL = originRemoteURL(gitDirectory: gitDirectory(for: root))
        return LocalGitRepositoryInfo(
            rootPath: root.path,
            remoteURL: remoteURL,
            fullName: remoteURL.flatMap(gitHubFullName(from:)),
            branch: currentBranch(gitDirectory: gitDirectory(for: root))
        )
    }

    // MARK: - History and activity

    static func gitLog(rootPath: String,
                       limit: Int = 60,
                       since: Date? = nil,
                       until: Date? = nil) async -> [LocalGitCommit] {
        let separator = "---FACETX-SEP---"
        let format = "%H\u{1f}%B\u{1f}%an\u{1f}%aI\u{1f}%D"
        var arguments = ["log", "--format=\(format)\(separator)", "--decorate=full"]
        if limit > 0 { arguments.append("-\(limit)") }
        if let since { arguments.append("--since=\(gitDateString(since))") }
        if let until { arguments.append("--until=\(gitDateString(until))") }
        let result = await execute(arguments, rootPath: rootPath)
        guard result.succeeded else { return [] }
        return parseCommits(result.stdout, separator: separator)
    }

    static func gitLogForFile(rootPath: String,
                              filePath: String,
                              limit: Int = 10) async -> [LocalGitCommit] {
        let separator = "---FACETX-SEP---"
        let format = "%H\u{1f}%B\u{1f}%an\u{1f}%aI\u{1f}%D"
        let result = await execute(
            ["log", "--follow", "--format=\(format)\(separator)", "-\(limit)", "--", filePath],
            rootPath: rootPath
        )
        guard result.succeeded else { return [] }
        return parseCommits(result.stdout, separator: separator)
    }

    static func fileContent(rootPath: String,
                            commitID: String,
                            filePath: String) async -> String? {
        let result = await execute(["show", "\(commitID):\(filePath)"], rootPath: rootPath)
        return result.succeeded ? result.stdout : nil
    }

    static func activity(rootPath: String,
                         since: Date,
                         calendar: Calendar = .current) async -> [LocalGitActivityDay] {
        let result = await execute(
            ["log", "--since=\(gitDateString(since))", "--format=%aI"],
            rootPath: rootPath
        )
        guard result.succeeded else { return [] }
        var counts: [Date: Int] = [:]
        for line in result.stdout.components(separatedBy: .newlines) {
            guard let date = parseISODate(line.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        return counts.map { LocalGitActivityDay(date: $0.key, commitCount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func commitDiff(rootPath: String, commitID: String) async -> String {
        let result = await execute(
            ["show", "--format=", "--find-renames", "--find-copies", commitID],
            rootPath: rootPath
        )
        return result.succeeded ? result.stdout : result.message
    }

    // MARK: - Working tree

    static func gitStatus(rootPath: String) async -> [LocalGitStatusEntry] {
        let result = await execute(["status", "--short", "--porcelain=v1"], rootPath: rootPath)
        guard result.succeeded else { return [] }
        return parseStatus(result.stdout)
    }

    static func diff(rootPath: String, entry: LocalGitStatusEntry) async -> String {
        let result: LocalGitCommandResult
        if entry.state == .untracked {
            result = await execute(
                ["diff", "--no-index", "--", "/dev/null", entry.path],
                rootPath: rootPath,
                acceptedExitCodes: [0, 1]
            )
        } else if entry.area == .staged {
            result = await execute(["diff", "--cached", "--", entry.path], rootPath: rootPath)
        } else {
            result = await execute(["diff", "--", entry.path], rootPath: rootPath)
        }
        return result.succeeded ? result.stdout : result.message
    }

    static func stage(rootPath: String, path: String) async -> LocalGitCommandResult {
        await execute(["add", "--", path], rootPath: rootPath)
    }

    static func unstage(rootPath: String, path: String) async -> LocalGitCommandResult {
        await execute(["restore", "--staged", "--", path], rootPath: rootPath)
    }

    static func stageAll(rootPath: String) async -> LocalGitCommandResult {
        await execute(["add", "-A"], rootPath: rootPath)
    }

    static func unstageAll(rootPath: String) async -> LocalGitCommandResult {
        await execute(["restore", "--staged", "."], rootPath: rootPath)
    }

    static func commit(rootPath: String, title: String, body: String) async -> LocalGitCommandResult {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            return LocalGitCommandResult(stdout: "", stderr: "Commit title is required.", exitCode: 2)
        }
        var arguments = ["commit", "-m", normalizedTitle]
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedBody.isEmpty { arguments += ["-m", normalizedBody] }
        return await execute(arguments, rootPath: rootPath)
    }

    // MARK: - Branch and remote

    static func branchState(rootPath: String) async -> LocalGitBranchState {
        async let currentResult = execute(["branch", "--show-current"], rootPath: rootPath)
        async let upstreamResult = execute(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            rootPath: rootPath
        )
        async let branchesResult = execute(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads"],
            rootPath: rootPath
        )
        let (currentCommand, upstreamCommand, branchesCommand) = await (
            currentResult, upstreamResult, branchesResult
        )
        let current = nonEmptyLine(currentCommand.stdout)
        let upstream = upstreamCommand.succeeded ? nonEmptyLine(upstreamCommand.stdout) : nil
        let branches = branchesCommand.stdout.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        var ahead = 0
        var behind = 0
        if upstream != nil {
            let counts = await execute(
                ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
                rootPath: rootPath
            )
            let values = counts.stdout.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }
            if values.count == 2 {
                ahead = values[0]
                behind = values[1]
            }
        }
        return LocalGitBranchState(
            current: current,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            localBranches: branches
        )
    }

    static func fetch(rootPath: String) async -> LocalGitCommandResult {
        await execute(["fetch", "--prune"], rootPath: rootPath)
    }

    static func pull(rootPath: String) async -> LocalGitCommandResult {
        await execute(["pull", "--ff-only"], rootPath: rootPath)
    }

    static func push(rootPath: String,
                     branch: String?,
                     hasUpstream: Bool) async -> LocalGitCommandResult {
        if hasUpstream {
            return await execute(["push"], rootPath: rootPath)
        }
        guard let branch, !branch.isEmpty else {
            return LocalGitCommandResult(stdout: "", stderr: "No branch is checked out.", exitCode: 2)
        }
        return await execute(["push", "--set-upstream", "origin", branch], rootPath: rootPath)
    }

    static func switchBranch(rootPath: String, branch: String) async -> LocalGitCommandResult {
        await execute(["switch", branch], rootPath: rootPath)
    }

    static func createBranch(rootPath: String, branch: String) async -> LocalGitCommandResult {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return LocalGitCommandResult(stdout: "", stderr: "Branch name is required.", exitCode: 2)
        }
        return await execute(["switch", "-c", normalized], rootPath: rootPath)
    }

    // MARK: - Parsing

    static func parseStatus(_ raw: String) -> [LocalGitStatusEntry] {
        raw.components(separatedBy: .newlines).flatMap { line -> [LocalGitStatusEntry] in
            guard line.count >= 3 else { return [] }
            let codes = Array(line.prefix(2))
            let rawPath = String(line.dropFirst(3))
            guard !rawPath.isEmpty else { return [] }
            let pathParts = rawPath.components(separatedBy: " -> ")
            let path = unquotePath(pathParts.last ?? rawPath)
            let originalPath = pathParts.count > 1 ? unquotePath(pathParts.dropLast().joined(separator: " -> ")) : nil
            let x = codes[0]
            let y = codes[1]
            if x == "?" { return [.init(path: path, originalPath: nil, state: .untracked, area: .unstaged)] }

            let conflictedPairs: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
            if conflictedPairs.contains(String(codes)) {
                return [.init(path: path, originalPath: originalPath, state: .conflicted, area: .unstaged)]
            }

            var entries: [LocalGitStatusEntry] = []
            if x != " " {
                entries.append(.init(path: path, originalPath: originalPath, state: state(for: x), area: .staged))
            }
            if y != " " {
                entries.append(.init(path: path, originalPath: originalPath, state: state(for: y), area: .unstaged))
            }
            return entries
        }
    }

    private static func parseCommits(_ raw: String, separator: String) -> [LocalGitCommit] {
        raw.components(separatedBy: separator).compactMap { block in
            let fields = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\u{1f}")
            guard fields.count >= 4 else { return nil }
            let sha = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else { return nil }
            let refs = fields.count >= 5
                ? fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let shortRefs = refs.components(separatedBy: ", ").map { ref in
                if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
                if ref.hasPrefix("refs/remotes/") { return String(ref.dropFirst("refs/remotes/".count)) }
                return ref
            }.joined(separator: ", ")
            return LocalGitCommit(
                id: sha,
                message: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                authorName: fields[2].trimmingCharacters(in: .whitespacesAndNewlines),
                date: parseISODate(fields[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? .distantPast,
                refs: shortRefs
            )
        }
    }

    private static func state(for code: Character) -> LocalGitStatusEntry.State {
        switch code {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "U": return .conflicted
        case "?": return .untracked
        default: return .other
        }
    }

    private static func unquotePath(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        let value = String(path.dropFirst().dropLast())
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    // MARK: - Process execution

    private static func execute(_ arguments: [String],
                                rootPath: String,
                                acceptedExitCodes: Set<Int32> = [0]) async -> LocalGitCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = gitExecutableURL()
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
                process.environment = ProcessInfo.processInfo.environment

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let code = process.terminationStatus
                    let normalizedCode: Int32 = acceptedExitCodes.contains(code) ? 0 : code
                    continuation.resume(returning: LocalGitCommandResult(
                        stdout: String(data: outputData, encoding: .utf8) ?? "",
                        stderr: String(data: errorData, encoding: .utf8) ?? "",
                        exitCode: normalizedCode
                    ))
                } catch {
                    continuation.resume(returning: LocalGitCommandResult(
                        stdout: "",
                        stderr: error.localizedDescription,
                        exitCode: -1
                    ))
                }
            }
        }
    }

    private static func gitExecutableURL() -> URL {
        ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
            ?? URL(fileURLWithPath: "/usr/bin/git")
    }

    private static func nonEmptyLine(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func gitDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    // MARK: - File-system inspection

    private static func gitRoot(startingAt url: URL) -> URL? {
        var current = url
        let fileManager = FileManager.default
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func gitDirectory(for root: URL) -> URL {
        let dotGit = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return dotGit
        }
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              contents.hasPrefix("gitdir:") else { return dotGit }
        let rawPath = contents.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: rawPath)
        return url.path.hasPrefix("/") ? url : root.appendingPathComponent(rawPath)
    }

    private static func originRemoteURL(gitDirectory: URL) -> String? {
        let configURL = gitDirectory.appendingPathComponent("config")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        var inOrigin = false
        for rawLine in config.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line == #"[remote "origin"]"#
                continue
            }
            guard inOrigin, line.hasPrefix("url") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { return parts[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    private static func currentBranch(gitDirectory: URL) -> String? {
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix) else { return nil }
        return String(head.dropFirst(prefix.count))
    }

    static func gitHubFullName(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?$"#,
            #"github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges >= 3,
                  let ownerRange = Range(match.range(at: 1), in: trimmed),
                  let repoRange = Range(match.range(at: 2), in: trimmed) else { continue }
            let repo = String(trimmed[repoRange]).replacingOccurrences(of: ".git", with: "")
            return "\(trimmed[ownerRange])/\(repo)"
        }
        return nil
    }
}
