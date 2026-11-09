import XCTest
@testable import MacPocketCore

final class InstalledBundleIndexTests: XCTestCase {
    private func legacy(_ candidate: String, installed: Set<String>) -> Bool {
        let candidate = candidate.lowercased()
        return installed.contains { candidate == $0 || candidate.hasPrefix($0 + ".") || candidate.hasPrefix($0 + "-") }
    }

    func testExactIDsAndHelperBoundariesDoNotHideSimilarlyNamedApplications() {
        let index = InstalledBundleIndex(["Com.Example.App", "org.vendor.some-app"])
        for id in ["com.example.app", "COM.EXAMPLE.APP.Helper", "com.example.app-helper.worker", "org.vendor.some-app-Helper"] {
            XCTAssertTrue(index.containsApplicationOrHelper(id), id)
        }
        for id in ["com.example.app2", "com.example.application", "com.example.other", "org.vendor.some-application", "org.vendor.some-app2-helper"] {
            XCTAssertFalse(index.containsApplicationOrHelper(id), id)
        }
    }

    func testEmptyAndUnusualIDsPreservePreviousMatchingRules() {
        for ids: Set<String> in [[], [""], ["com.example.app-", "com.example.app.helper"], ["COM.Example.İ", "org.example.café"]] {
            let normalized = Set(ids.map { $0.lowercased() }), index = InstalledBundleIndex(ids)
            for id in ["", "-com.example.app", "com.example.app--Helper", "com.example.app-helper", "com.example.app.helper.extra", "com.example.İ.Helper", "org.example.cafe\u{301}-Helper"] {
                XCTAssertEqual(index.containsApplicationOrHelper(id), legacy(id, installed: normalized), id)
            }
        }
    }

    func testGeneratedCandidatesMatchPreviousPredicate() {
        let installed = Set((0..<120).map { "com.vendor\($0 % 17).app\($0)-desktop" })
        let index = InstalledBundleIndex(installed)
        for id in installed.sorted() {
            for candidate in [id, id.uppercased(), id + ".Helper", id + "-Helper", id + ".worker-extra", id + "2", id + "lication", "other." + id] {
                XCTAssertEqual(index.containsApplicationOrHelper(candidate), legacy(candidate, installed: installed), candidate)
            }
        }
    }

    func testScannerPreservesCandidatesAndVendorWarningAcrossAllLocations() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.BundleIndex." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let kept = ["com.example.app", "COM.EXAMPLE.APP.Helper", "com.example.app-helper"]
        let candidates = ["com.example.app2", "com.example.application", "org.removed.product"]
        for folder in ["Caches", "Logs", "Preferences", "Application Support", "Saved Application State", "HTTPStorages", "WebKit"] {
            let directory = home.appendingPathComponent("Library/" + folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for id in kept + candidates {
                let suffix = folder == "Preferences" ? ".plist" : folder == "Saved Application State" ? ".savedState" : ""
                let url = directory.appendingPathComponent(id + suffix)
                if folder == "Preferences" { try Data().write(to: url) }
                else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            }
        }
        let rows = try await ApplicationLeftoverScanner().scan(installedIDs: ["com.example.app"], home: home)
        XCTAssertEqual(rows.count, candidates.count * 7)
        XCTAssertEqual(Set(rows.map(\.bundleID)), Set(candidates))
        for row in rows {
            XCTAssertEqual(row.sharedVendor, row.bundleID.hasPrefix("com.example."))
            XCTAssertNoThrow(try row.request.validate())
        }
    }
}
