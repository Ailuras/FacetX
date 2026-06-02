import Foundation

/// A single commit from the GitHub API.
public struct GitHubCommit: Identifiable, Sendable {
    public let id: String          // full SHA
    public let shortSHA: String    // first 7 chars
    public let message: String
    public let authorName: String
    public let date: Date
    public let htmlURL: URL
}

/// Thin wrapper around the GitHub REST API. Nonisolated so it can be used
/// safely from background contexts without tripping Swift 6 isolation checks.
final class GitHubService {

    struct APIError: Error {
        let statusCode: Int
        let message: String
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: – Commits

    /// Fetch the most recent commits for a repository.
    /// - Parameters:
    ///   - repo: "owner/repo" format.
    ///   - token: GitHub Personal Access Token (may be nil for public repos).
    ///   - perPage: number of commits to retrieve (max 100).
    func fetchCommits(repo: String, token: String?, perPage: Int = 30) async throws -> [GitHubCommit] {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/commits?per_page=\(perPage)") else {
            throw APIError(statusCode: 0, message: "Invalid repository format.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "Unexpected response type.")
        }

        guard http.statusCode == 200 else {
            throw APIError(statusCode: http.statusCode,
                           message: errorMessage(statusCode: http.statusCode, data: data))
        }

        let raw = try decoder.decode([RawCommit].self, from: data)
        return raw.compactMap { commit in
            guard let url = URL(string: commit.html_url) else { return nil }
            let sha = commit.sha
            let short = String(sha.prefix(7))
            let message = commit.commit.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = commit.commit.author.name
            // Parse ISO-8601 date manually because the top-level decoder uses iso8601
            // but the commit JSON nests the date string.
            let date = ISO8601DateFormatter().date(from: commit.commit.author.date) ?? Date()
            return GitHubCommit(id: sha, shortSHA: short, message: message,
                                authorName: author, date: date, htmlURL: url)
        }
    }

    // MARK: – Token validation

    /// Validate a PAT by hitting /user. Returns the login username on success,
    /// or throws on failure.
    func validateToken(_ token: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw APIError(statusCode: 0, message: "Bad URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "Unexpected response type.")
        }
        guard http.statusCode == 200 else {
            throw APIError(statusCode: http.statusCode,
                           message: "Token validation failed (\(http.statusCode)).")
        }
        let user = try JSONDecoder().decode(RawUser.self, from: data)
        return user.login
    }

    private func errorMessage(statusCode: Int, data: Data) -> String {
        if let raw = try? decoder.decode(RawError.self, from: data) {
            return "GitHub error \(statusCode): \(raw.message)"
        }
        return "GitHub error \(statusCode)."
    }

    // MARK: – JSON helpers

    private struct RawCommit: Decodable {
        let sha: String
        let commit: RawCommitDetail
        let html_url: String
    }

    private struct RawCommitDetail: Decodable {
        let message: String
        let author: RawAuthor
    }

    private struct RawAuthor: Decodable {
        let name: String
        let date: String
    }

    private struct RawUser: Decodable {
        let login: String
    }

    private struct RawError: Decodable {
        let message: String
    }
}
