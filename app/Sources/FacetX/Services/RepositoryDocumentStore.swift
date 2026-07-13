import Foundation

struct RepositoryDocument: Identifiable, Equatable, Sendable {
    let relativePath: String
    let url: URL
    let modifiedAt: Date?
    let isReadme: Bool

    var id: String { relativePath }

    var title: String {
        if isReadme { return "README" }
        return url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

enum RepositoryDocumentStore {
    enum StoreError: LocalizedError {
        case missingRepository
        case invalidPath

        var errorDescription: String? {
            switch self {
            case .missingRepository: return "The project has no local Git repository."
            case .invalidPath: return "Documents must be README.md or a top-level Markdown file in .facetx."
            }
        }
    }

    static func repositoryURL(path: String?) throws -> URL {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw StoreError.missingRepository
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    static func list(repositoryPath: String?) throws -> [RepositoryDocument] {
        let root = try repositoryURL(path: repositoryPath)
        var documents: [RepositoryDocument] = []

        let readmeURL = root.appendingPathComponent("README.md")
        if FileManager.default.fileExists(atPath: readmeURL.path) {
            documents.append(document(relativePath: "README.md", root: root))
        }

        let docsURL = root.appendingPathComponent(".facetx", isDirectory: true)
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: docsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            documents.append(contentsOf: urls
                .filter { $0.pathExtension.lowercased() == "md" && $0.deletingLastPathComponent() == docsURL }
                .map { document(relativePath: ".facetx/\($0.lastPathComponent)", root: root) }
                .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) })
        }
        return documents
    }

    static func read(repositoryPath: String?, relativePath: String) throws -> String {
        try String(contentsOf: url(repositoryPath: repositoryPath, relativePath: relativePath), encoding: .utf8)
    }

    static func save(repositoryPath: String?, relativePath: String, body: String) throws {
        let target = try url(repositoryPath: repositoryPath, relativePath: relativePath)
        if relativePath != "README.md" {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try body.write(to: target, atomically: true, encoding: .utf8)
    }

    static func create(repositoryPath: String?, title: String, body: String = "") throws -> RepositoryDocument {
        let root = try repositoryURL(path: repositoryPath)
        let docsURL = root.appendingPathComponent(".facetx", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        let base = slug(title).isEmpty ? "new-doc" : slug(title)
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: docsURL.appendingPathComponent("\(candidate).md").path) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        let relativePath = ".facetx/\(candidate).md"
        let content = body.isEmpty ? "# \(title.trimmingCharacters(in: .whitespacesAndNewlines))\n\n" : body
        try save(repositoryPath: repositoryPath, relativePath: relativePath, body: content)
        return document(relativePath: relativePath, root: root)
    }

    static func exists(repositoryPath: String?, relativePath: String) -> Bool {
        guard let target = try? url(repositoryPath: repositoryPath, relativePath: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    static func url(repositoryPath: String?, relativePath: String) throws -> URL {
        guard isValid(relativePath: relativePath) else { throw StoreError.invalidPath }
        let root = try repositoryURL(path: repositoryPath)
        let target = root.appendingPathComponent(relativePath).standardizedFileURL
        guard target.path == root.appendingPathComponent(relativePath).standardizedFileURL.path,
              target.path.hasPrefix(root.path + "/") else {
            throw StoreError.invalidPath
        }
        return target
    }

    static func isValid(relativePath: String) -> Bool {
        if relativePath == "README.md" { return true }
        guard !relativePath.hasPrefix("/"), !relativePath.contains("..") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && components[0] == ".facetx"
            && components[1].lowercased().hasSuffix(".md")
            && components[1].count > 3
    }

    private static func document(relativePath: String, root: URL) -> RepositoryDocument {
        let url = root.appendingPathComponent(relativePath)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return RepositoryDocument(
            relativePath: relativePath,
            url: url,
            modifiedAt: values?.contentModificationDate,
            isReadme: relativePath == "README.md"
        )
    }

    private static func slug(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet.alphanumerics
        let pieces = lowered.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(pieces)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
