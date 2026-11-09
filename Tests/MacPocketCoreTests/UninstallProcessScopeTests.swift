import XCTest
@testable import MacPocketCore

final class UninstallProcessScopeTests: XCTestCase {
    func testOnlyExecutableDescendantsMatch() {
        let root = URL(fileURLWithPath: "/Applications/Example.app")
        XCTAssertTrue(UninstallProcessScope.contains("/Applications/Example.app/Contents/MacOS/Example", applicationURL: root))
        XCTAssertTrue(UninstallProcessScope.contains("/Applications/Example.app/Contents/Helpers/worker", applicationURL: root))
        for path in ["/Applications/Example.app.bak/worker", "/Applications/Example Helper.app/worker", "/Library/PrivilegedHelperTools/com.example.worker", "worker", "/Applications/Example.app/../Other.app/worker"] {
            XCTAssertFalse(UninstallProcessScope.contains(path, applicationURL: root), path)
        }
        XCTAssertFalse(UninstallProcessScope.contains("/Applications/Example.app/worker", applicationURL: URL(fileURLWithPath: "/Applications")))
    }
    func testSymlinkToSharedExecutableIsNotOwnedByBundle() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: base) }
        let app = base.appendingPathComponent("Example.app"), shared = base.appendingPathComponent("Shared/worker")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("owned fixture".utf8).write(to: shared)
        let link = app.appendingPathComponent("worker")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: shared)
        XCTAssertFalse(UninstallProcessScope.contains(link.path, applicationURL: app))
    }
    func testPlanKeepsHomeAndRejectsChangedBundleIdentifier() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app"), plist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        func write(_ id: String) throws { try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0).write(to: plist) }
        try write("org.example.UninstallFixture")
        let applications = try await ApplicationInventory().scan(roots: [root])
        let application = try XCTUnwrap(applications.first)
        let plan = try UninstallPlanner.plan(application, home: root)
        XCTAssertEqual(plan.home, root)
        try write("org.example.Replacement")
        XCTAssertThrowsError(try UninstallPlanner.validateApplication(application))
    }
}
