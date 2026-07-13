import Foundation

struct LocalGitRepositoryInfo: Equatable {
    let rootPath: String
    let remoteURL: String?
    let fullName: String?
    let branch: String?
}

/// A commit from the local git history.
struct LocalGitCommit: Identifiable, Equatable {
    let id: String          // full SHA
    var shortSHA: String { String(id.prefix(7)) }
    let message: String
    let authorName: String
    let date: Date
    let refs: String        // e.g. "HEAD -> main, origin/main"

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

    /// GitHub URL, derived if a fullName is provided.
    func htmlURL(repoFullName: String?) -> URL? {
        guard let name = repoFullName else { return nil }
        return URL(string: "https://github.com/\(name)/commit/\(id)")
    }
}

/// A file entry from `git status --short`.
struct LocalGitStatusEntry: Identifiable, Equatable {
    enum State: String, Equatable {
        case modified   = "M"
        case added      = "A"
        case deleted    = "D"
        case renamed    = "R"
        case untracked  = "?"
        case other
    }

    let id: String          // the file path (unique per status output)
    let path: String
    let state: State
    let staged: Bool        // true when the change is in the index

    var icon: String {
        switch state {
        case .modified:   return "pencil.circle.fill"
        case .added:      return "plus.circle.fill"
        case .deleted:    return "minus.circle.fill"
        case .renamed:    return "arrow.triangle.2.circlepath"
        case .untracked:  return "questionmark.circle.fill"
        case .other:      return "circle.fill"
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

    // ── git log ──────────────────────────────────────────────────────────────

    /// Fetch the most recent commits from the local repository.
    /// Returns an empty array (never throws) so callers can treat nil as
    /// "no repo" and an empty array as "repo found but git unavailable/empty".
    static func gitLog(rootPath: String, limit: Int = 60) async -> [LocalGitCommit] {
        // separator that won't appear in normal commit messages
        let sep = "---FACETX-SEP---"
        // format: sha\x1fsubject+body\x1fauthor\x1fiso-date\x1frefs
        let fmt = "%H\u{1f}%B\u{1f}%an\u{1f}%aI\u{1f}%D"
        let args = ["log", "--format=\(fmt)\(sep)", "-\(limit)", "--decorate=full"]
        guard let raw = await run("git", args: args, cwd: rootPath) else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return raw
            .components(separatedBy: sep)
            .compactMap { block -> LocalGitCommit? in
                let fields = block.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\u{1f}")
                guard fields.count >= 4 else { return nil }
                let sha  = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sha.isEmpty else { return nil }
                let msg  = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let auth = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let dateStr = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let refs = fields.count >= 5
                    ? fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let date = iso.date(from: dateStr) ?? Date.distantPast
                // Shorten refs: strip leading "refs/heads/" / "refs/remotes/"
                let shortRefs = refs
                    .components(separatedBy: ", ")
                    .map { r in
                        r.hasPrefix("refs/heads/") ? String(r.dropFirst("refs/heads/".count))
                            : r.hasPrefix("refs/remotes/") ? String(r.dropFirst("refs/remotes/".count))
                            : r
                    }
                    .joined(separator: ", ")
                return LocalGitCommit(id: sha, message: msg, authorName: auth,
                                     date: date, refs: shortRefs)
            }
    }

    // ── git status ───────────────────────────────────────────────────────────

    /// Fetch the working-tree and index status.
    static func gitStatus(rootPath: String) async -> [LocalGitStatusEntry] {
        guard let raw = await run("git", args: ["status", "--short", "--porcelain"],
                                  cwd: rootPath) else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line -> LocalGitStatusEntry? in
            guard line.count >= 3 else { return nil }
            let xy   = Array(line.prefix(2))
            let path = String(line.dropFirst(3))
            guard !path.isEmpty else { return nil }
            // xy[0] = index state, xy[1] = worktree state
            let indexCode   = String(xy[0])
            let worktreeCode = String(xy[1])
            let staged = indexCode != " " && indexCode != "?"
            let code = staged ? indexCode : worktreeCode
            let state: LocalGitStatusEntry.State
            switch code {
            case "M": state = .modified
            case "A": state = .added
            case "D": state = .deleted
            case "R": state = .renamed
            case "?": state = .untracked
            default:  state = .other
            }
            return LocalGitStatusEntry(id: path, path: path, state: state, staged: staged)
        }
    }

    // ── Process runner ───────────────────────────────────────────────────────

    /// Run a command in `cwd` and return its stdout, or nil on failure.
    static func run(_ command: String, args: [String], cwd: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                // Prefer the git that ships with Xcode CLT; fall back to /usr/bin/git
                let gitPaths = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
                process.executableURL = gitPaths
                    .map(URL.init(fileURLWithPath:))
                    .first { FileManager.default.fileExists(atPath: $0.path) }
                    ?? URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
                process.environment = ProcessInfo.processInfo.environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()    // discard stderr

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // ── File-system git inspection (unchanged) ───────────────────────────────

    private static func gitRoot(startingAt url: URL) -> URL? {
        var current = url
        let fileManager = FileManager.default
        while true {
            let gitURL = current.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitURL.path) {
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
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return dotGit
        }
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              contents.hasPrefix("gitdir:") else {
            return dotGit
        }
        let rawPath = contents
            .dropFirst("gitdir:".count)
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
            if parts.count == 2 {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func currentBranch(gitDirectory: URL) -> String? {
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
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
