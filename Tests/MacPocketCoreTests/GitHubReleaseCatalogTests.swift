import Foundation
import XCTest
@testable import MacPocketCore

final class GitHubReleaseCatalogTests: XCTestCase {
    func testRepositoryOnlyAcceptsCanonicalGitHubPaths() {
        XCTAssertEqual(GitHubRepository("https://github.com/example/App.git/")?.slug, "example/App")
        XCTAssertEqual(GitHubRepository("example/App")?.owner, "example")
        for bad in ["http://github.com/example/App", "https://github.com.evil.com/example/App", "https://user@github.com/example/App", "https://github.com/example/App?x=1", "https://github.com/example/App/issues", "../App", "a/../b", "", "x/%2f"] {
            XCTAssertNil(GitHubRepository(bad), bad)
        }
    }
    func testStableVersionAndReleaseURLStayBoundToRepository() throws {
        let repository = try XCTUnwrap(GitHubRepository("owner/app"))
        let rows: [[String:Any]] = [
            ["tag_name":"v2.4.1", "draft":false, "prerelease":false, "html_url":"https://github.com/owner/app/releases/tag/v2.4.1"],
            ["tag_name":"v3.0.0-beta.1", "draft":false, "prerelease":true, "html_url":"https://github.com/owner/app/releases/tag/v3"],
            ["tag_name":"v9.0.0", "draft":true, "prerelease":false, "html_url":"https://github.com/owner/app/releases/tag/v9"],
            ["tag_name":"v8.0.0", "draft":false, "prerelease":false, "html_url":"https://github.com/other/app/releases/tag/v8"],
            ["tag_name":"not-a-version", "draft":false, "prerelease":false, "html_url":"https://github.com/owner/app/releases/tag/latest"]
        ]
        let data = try JSONSerialization.data(withJSONObject: rows)
        let stable = try GitHubReleaseCatalog.decode(data, repository: repository)
        XCTAssertEqual(stable.map(\.version), ["2.4.1"])
        XCTAssertEqual(try GitHubReleaseCatalog.decode(data, repository: repository, includePrereleases: true).count, 2)
    }
    func testMalformedOrOversizedCatalogCannotLookCurrent() throws {
        let repository = try XCTUnwrap(GitHubRepository("owner/app"))
        XCTAssertThrowsError(try GitHubReleaseCatalog.decode(Data("{}".utf8), repository: repository))
        XCTAssertThrowsError(try GitHubReleaseCatalog.decode(Data(repeating: 0, count: 2097153), repository: repository))
    }
}
