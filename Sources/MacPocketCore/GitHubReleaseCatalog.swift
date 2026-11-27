import Foundation

public struct GitHubRepository: Codable, Equatable, Hashable, Sendable {
    public let owner: String
    public let name: String
    public var slug: String { owner + "/" + name }
    public init?(_ input: String) {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") {
            guard let url = URLComponents(string: value), url.host?.lowercased() == "github.com", url.user == nil,
                  url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return nil }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in
            part.count <= 100 && part.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil && part != "." && part != ".."
        }) else { return nil }
        owner = String(parts[0])
        name = String(parts[1]).replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
        guard !name.isEmpty else { return nil }
    }
    public var apiURL: URL { URL(string: "https://api.github.com/repos/\(slug)/releases?per_page=20")! }
}
public struct GitHubApplicationRelease: Equatable, Sendable {
    public let version: String
    public let url: URL
    public let prerelease: Bool
    public let publishedAt: Date?
}
public enum GitHubReleaseCatalog {
    /// Release URLs must belong to the explicitly selected repository. Assets are never executed.
    public static func decode(_ data: Data, repository: GitHubRepository, includePrereleases: Bool = false) throws -> [GitHubApplicationRelease] {
        guard data.count <= 2_097_152 else { throw ApplicationUpdateError.tooLarge }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ApplicationUpdateError.malformed }
        return rows.prefix(100).compactMap { row in
            guard row["draft"] as? Bool == false, let prerelease = row["prerelease"] as? Bool,
                  !prerelease || includePrereleases, let tag = row["tag_name"] as? String, tag.utf8.count <= 128,
                  tag.range(of: #"^[vV]?[0-9]+(?:\.[0-9]+){0,4}(?:[-+._][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil,
                  let rawURL = row["html_url"] as? String, let url = URL(string: rawURL),
                  url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil, url.password == nil, url.port == nil,
                  url.path.lowercased().hasPrefix("/\(repository.slug.lowercased())/releases/tag/") else { return nil }
            let version = tag.first == "v" || tag.first == "V" ? String(tag.dropFirst()) : tag
            let published = (row["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return .init(version: version, url: url, prerelease: prerelease, publishedAt: published)
        }
    }
}
