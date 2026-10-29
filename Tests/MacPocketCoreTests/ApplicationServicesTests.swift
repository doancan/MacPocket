import XCTest
@testable import MacPocketCore

final class ApplicationServicesTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-app-tests-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try canonicalFileURL(root)
    }
    private func app(_ root: URL, id: String = "test.macpocket.example") throws -> URL {
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": "Example", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    func testInventoryReadsBundlesAndDoesNotFollowAppSymlinks() async throws {
        let root = try fixture()
        let url = try app(root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: url)
        let applications = try await ApplicationInventory().scan(roots: [root])
        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications[0].version, "1.2")
        XCTAssertEqual(applications[0].bundleID, "test.macpocket.example")
    }

    func testUninstallerDoesNotGuessSharedVendorFolders() async throws {
        let root = try fixture(), home = try fixture()
        _ = try app(root)
        let library = home.appendingPathComponent("Library")
        let exact = library.appendingPathComponent("Caches/test.macpocket.example")
        let shared = library.appendingPathComponent("Application Support/Example Vendor")
        try FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let applications = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(applications.first)
        let plan = try UninstallPlanner.plan(application, home: home)
        XCTAssertEqual(plan.candidates.count, 2)
        XCTAssertTrue(plan.candidates.contains { $0.request.url.path == exact.path })
        XCTAssertFalse(plan.candidates.contains { $0.request.url.path == shared.path })
    }

    func testSystemAndOwnApplicationsCannotBeUninstalled() async throws {
        for id in ["com.apple.example", "com.doancan.MacPocket"] {
            let root = try fixture()
            _ = try app(root, id: id)
            let applications = try await ApplicationInventory().scan(roots: [root])
            XCTAssertThrowsError(try UninstallPlanner.plan(applications[0]))
        }
    }

    func testHomebrewParserKeepsPinnedAndVersionInformation() throws {
        let output = #"{"casks":[{"name":"example-app","installed_versions":["1.0"],"current_version":"2.0","pinned":true}]}"#
        let casks = try HomebrewApplications.decodeUpdates(output)
        XCTAssertEqual(casks[0].installedVersion, "1.0")
        XCTAssertEqual(casks[0].currentVersion, "2.0")
        XCTAssertTrue(casks[0].pinned)
    }

    func testInstalledHomebrewParserMapsAppArtifacts() throws {
        let output = #"{"casks":[{"token":"example","name":["Example"],"installed":"1.0","version":"2.0","artifacts":[{"app":["Example.app",{"target":"Renamed.app"}]}]}]}"#
        let casks = try HomebrewApplications.decodeInstalled(output)
        XCTAssertEqual(casks[0].applicationNames, ["Example.app"])
    }

    func testInvalidUpdateTokensAreRejectedBeforeLaunchingHomebrew() async {
        for token in ["--help", "../other", "app;touch x", "a b", "$(id)"] {
            do { _ = try await HomebrewApplications().upgrade(token); XCTFail("Accepted invalid token") }
            catch HomebrewError.invalidToken { }
            catch { XCTFail("Wrong error: \(error)") }
            do { _ = try await HomebrewApplications().uninstall(token); XCTFail("Accepted invalid uninstall token") }
            catch HomebrewError.invalidToken { }
            catch { XCTFail("Wrong error: \(error)") }
        }
    }
}
