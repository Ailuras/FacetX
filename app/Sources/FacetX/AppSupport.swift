import Foundation

/// Where FacetX keeps its JSON stores (projects, settings).
enum AppSupport {
    /// The FacetX support directory (`Application Support/FacetX/`), created if
    /// needed.
    static func directory() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FacetX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
