import Foundation

struct LocalGitRepositoryInfo: Equatable {
    let rootPath: String
    let remoteURL: String?
    let fullName: String?
    let branch: String?
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
