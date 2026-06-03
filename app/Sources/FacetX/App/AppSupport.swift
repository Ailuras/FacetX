import Foundation

/// Where FacetX keeps its JSON stores (projects, settings).
enum AppSupport {
    /// The FacetX support directory, created if needed. Development variant
    /// builds set `FacetXApplicationSupportName` in Info.plist so multiple
    /// worktrees do not share JSON state.
    static func directory() -> URL {
        let folderName = Bundle.main.object(forInfoDictionaryKey: "FacetXApplicationSupportName") as? String
        let trimmed = folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let safeFolderName = trimmed.isEmpty ? "FacetX" : trimmed
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(safeFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
