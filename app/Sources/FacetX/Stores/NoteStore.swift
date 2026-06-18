import Foundation

/// Reads and writes a project's note markdown files.
///
/// Each note is a plain `.md` file named by its anchor item's stable `facetID`,
/// stored under `<project dataDirectory>/Notes/`. The event anchor in EventKit
/// supplies the note's title and date; this store owns the body text. The app
/// is not sandboxed, so paths are used directly.
@MainActor
final class NoteStore {
    static let shared = NoteStore()
    private init() {}

    private let folderName = "Notes"

    func notesDirectory(dataDirectory: String) -> URL {
        URL(fileURLWithPath: dataDirectory).appendingPathComponent(folderName, isDirectory: true)
    }

    func noteURL(dataDirectory: String, facetID: String) -> URL {
        notesDirectory(dataDirectory: dataDirectory).appendingPathComponent("\(facetID).md")
    }

    func exists(dataDirectory: String, facetID: String) -> Bool {
        FileManager.default.fileExists(atPath: noteURL(dataDirectory: dataDirectory, facetID: facetID).path)
    }

    func body(dataDirectory: String, facetID: String) -> String {
        (try? String(contentsOf: noteURL(dataDirectory: dataDirectory, facetID: facetID), encoding: .utf8)) ?? ""
    }

    @discardableResult
    func save(dataDirectory: String, facetID: String, body: String) -> Bool {
        let dir = notesDirectory(dataDirectory: dataDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: noteURL(dataDirectory: dataDirectory, facetID: facetID), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func delete(dataDirectory: String, facetID: String) {
        try? FileManager.default.removeItem(at: noteURL(dataDirectory: dataDirectory, facetID: facetID))
    }
}
