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
        let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: nil)
        XCTAssertEqual(plan.candidates.count, 2)
        XCTAssertTrue(plan.candidates.contains { $0.request.url.path == exact.path })
        XCTAssertFalse(plan.candidates.contains { $0.request.url.path == shared.path })
    }

    private func touch(_ url: URL, directory: Bool = false, _ contents: String = "x") throws {
        if directory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    func testCompletePlanFindsEveryLeftoverFamilyForTheBundleIdentifier() async throws {
        let root = try fixture(), home = try fixture(), system = try fixture()
        _ = try app(root, id: "Test.MacPocket.Example")
        let lib = home.appendingPathComponent("Library")
        let expected = [
            "Caches/test.macpocket.example", "Logs/Test.MacPocket.Example", "Preferences/test.macpocket.example.plist",
            "Preferences/test.macpocket.example.helper.plist", "Preferences/ByHost/test.macpocket.example.ABC123.plist",
            "Application Support/test.macpocket.example", "Saved Application State/test.macpocket.example.savedState",
            "WebKit/test.macpocket.example", "HTTPStorages/test.macpocket.example",
            "HTTPStorages/test.macpocket.example.binarycookies", "Containers/test.macpocket.example",
            "Containers/test.macpocket.example.widget", "Group Containers/group.test.macpocket.example",
            "Group Containers/ABCDE12345.test.macpocket.example", "Application Scripts/test.macpocket.example",
            "Cookies/test.macpocket.example.binarycookies", "LaunchAgents/test.macpocket.example.agent.plist",
            "Application Support/Example", "Caches/Example", "Logs/Example",
        ]
        for path in expected { try touch(lib.appendingPathComponent(path), directory: !path.hasSuffix("plist") && !path.hasSuffix("binarycookies")) }
        let unrelated = ["Caches/test.macpocket.exampleOTHER", "Application Support/Example Vendor", "Group Containers/group.other.app",
                         "Preferences/test.macpocket.other.plist", "Containers/test.macpocket.exampl"]
        for path in unrelated { try touch(lib.appendingPathComponent(path), directory: !path.hasSuffix("plist")) }
        let systemItems = ["LaunchDaemons/test.macpocket.example.helper.plist", "PrivilegedHelperTools/test.macpocket.example.helper",
                           "Application Support/test.macpocket.example", "Preferences/test.macpocket.example.plist"]
        for path in systemItems { try touch(system.appendingPathComponent(path), directory: path.hasPrefix("Application Support")) }
        try touch(system.appendingPathComponent("LaunchAgents/other.plist"))

        let scanned = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(scanned.first)
        let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: system)
        let paths = Set(plan.candidates.map(\.request.url.path))
        let canonicalLib = try canonicalFileURL(lib), canonicalSystem = try canonicalFileURL(system)
        for path in expected { XCTAssertTrue(paths.contains(canonicalLib.appendingPathComponent(path).path), "missing user item \(path)") }
        for path in systemItems { XCTAssertTrue(paths.contains(canonicalSystem.appendingPathComponent(path).path), "missing system item \(path)") }
        for path in unrelated { XCTAssertFalse(paths.contains(canonicalLib.appendingPathComponent(path).path), "unrelated item matched \(path)") }
        XCTAssertFalse(paths.contains(canonicalSystem.appendingPathComponent("LaunchAgents/other.plist").path))
        XCTAssertEqual(plan.candidates.count, expected.count + systemItems.count + 1, "every item once, plus the application")
        XCTAssertEqual(plan.completeSelection.count, plan.candidates.count)
        XCTAssertTrue(plan.requiresAdministrator)
        XCTAssertEqual(Set(plan.candidates.filter(\.isSystemLevel).map(\.request.url.lastPathComponent)),
                       ["test.macpocket.example.helper.plist", "test.macpocket.example.helper", "test.macpocket.example", "test.macpocket.example.plist"])
        XCTAssertEqual(plan.candidates.filter(\.matchedByName).count, 3)
        for candidate in plan.candidates where !candidate.request.applicationBundle { XCTAssertNoThrow(try candidate.request.validate(), candidate.request.url.path) }
    }

    func testCompletePlanReadsLaunchdLabelsAndSkipsSymlinks() async throws {
        let root = try fixture(), home = try fixture(), outside = try fixture()
        _ = try app(root)
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let label = "test.macpocket.example.updater"
        try PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0)
            .write(to: agents.appendingPathComponent(label + ".plist"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/test.macpocket.example"),
                                                   withDestinationURL: outside)
        let scanned = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(scanned.first)
        let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: nil)
        XCTAssertEqual(plan.candidates.compactMap(\.launchdLabel), [label])
        XCTAssertFalse(plan.candidates.contains { $0.request.url.lastPathComponent == "test.macpocket.example" && $0.title == String(localized: "Önbellek") })
        XCTAssertFalse(plan.requiresAdministrator)
    }

    func testNestedSiblingApplicationKeepsItsDataWhenTheParentIsUninstalled() async throws {
        let root = try fixture(), home = try fixture()
        _ = try app(root, id: "com.example.Editor")
        let lib = home.appendingPathComponent("Library")
        let own = ["Caches/com.example.Editor", "Caches/com.example.Editor.helper", "Containers/com.example.Editor"]
        let beta = ["Caches/com.example.Editor.beta", "Caches/com.example.Editor.beta.helper", "Containers/com.example.Editor.beta",
                    "Preferences/com.example.Editor.beta.plist", "Group Containers/TEAM123456.com.example.Editor.beta"]
        for path in own + beta { try touch(lib.appendingPathComponent(path), directory: !path.hasSuffix(".plist")) }
        let scanned = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(scanned.first)
        let siblings: Set<String> = ["com.example.Editor", "com.example.Editor.beta", "com.example"]
        let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: nil, siblingIDs: siblings)
        let paths = Set(plan.candidates.map(\.request.url.path))
        let canonical = try canonicalFileURL(lib)
        for path in own { XCTAssertTrue(paths.contains(canonical.appendingPathComponent(path).path), "own item missing: \(path)") }
        for path in beta { XCTAssertFalse(paths.contains(canonical.appendingPathComponent(path).path), "sibling data would be deleted: \(path)") }
        XCTAssertEqual(plan.siblingIDs, siblings)
        // Without sibling knowledge the prefix rule is as broad as documented; the app passes the inventory.
        let blind = try UninstallPlanner.plan(application, home: home, systemLibrary: nil)
        XCTAssertTrue(blind.candidates.contains { $0.request.url.lastPathComponent == "com.example.Editor.beta" })
    }

    func testAncestorIdentifiersNeverHideTheApplicationsOwnData() async throws {
        let root = try fixture(), home = try fixture()
        _ = try app(root, id: "com.example.Editor.beta")
        let own = home.appendingPathComponent("Library/Caches/com.example.Editor.beta")
        try touch(own, directory: true)
        let scanned = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(scanned.first)
        let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: nil,
                                             siblingIDs: ["com.example.Editor", "com.example", "com.example.Editor.beta"])
        XCTAssertTrue(plan.candidates.contains { $0.request.url.lastPathComponent == "com.example.Editor.beta" })
    }

    func testShortIdentifierMatchesExactlyAndNeverByPrefix() async throws {
        let root = try fixture(), home = try fixture()
        _ = try app(root, id: "com.evil")
        let lib = home.appendingPathComponent("Library")
        for path in ["Caches/com.evil", "Caches/com.other.App", "Caches/com.evil.sub", "Containers/com.other.App",
                     "Group Containers/TEAM123456.com.evil", "Preferences/com.other.App.plist"] {
            try touch(lib.appendingPathComponent(path), directory: !path.hasSuffix(".plist"))
        }
        let scanned = try await ApplicationInventory().scan(roots: [root])
        let plan = try UninstallPlanner.plan(try XCTUnwrap(scanned.first), home: home, systemLibrary: nil)
        let names = Set(plan.candidates.map(\.request.url.lastPathComponent))
        XCTAssertTrue(names.contains("com.evil"))
        XCTAssertFalse(names.contains("com.other.App") || names.contains("com.evil.sub") || names.contains("TEAM123456.com.evil")
                       || names.contains("com.other.App.plist"))
    }

    func testOwnApplicationCannotBeUninstalled() async throws {
        let root = try fixture()
        _ = try app(root, id: "com.doancan.MacPocket")
        let applications = try await ApplicationInventory().scan(roots: [root])
        XCTAssertTrue(applications[0].protected)
        XCTAssertThrowsError(try UninstallPlanner.plan(applications[0]))
    }

    func testSIPProtectedSystemApplicationIsBuiltInAndCannotBeUninstalled() throws {
        let calculator = try XCTUnwrap(ApplicationInventory.read(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        XCTAssertTrue(calculator.sipProtected)
        XCTAssertTrue(calculator.builtIn)
        XCTAssertThrowsError(try UninstallPlanner.plan(calculator))
    }

    func testAppleApplicationInstalledSeparatelyCanBeUninstalled() async throws {
        // App Store or downloaded Apple apps (Xcode, Compressor) aren't protected by SIP, so they can be
        // removed.
        let root = try fixture()
        _ = try app(root, id: "com.apple.example")
        let scanned = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(scanned.first)
        XCTAssertFalse(application.sipProtected)
        XCTAssertFalse(application.builtIn)
        XCTAssertFalse(application.protected)
        XCTAssertNoThrow(try UninstallPlanner.plan(application, home: root, systemLibrary: nil))
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
