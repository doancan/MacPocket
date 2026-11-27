import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class ApplicationUpdateCatalogTests: XCTestCase {
    private func feed(_ items: String) -> Data { Data("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>\(items)</channel></rss>".utf8) }
    private func item(_ version: String, extra: String = "", attributes: String = "") -> String {
        "<item><sparkle:version>\(version)</sparkle:version>\(extra)<enclosure url=\"https://example.com/app.zip\" \(attributes)/></item>"
    }
    func testAppcastVersionAndDisplayVersionStaySeparateAndOrderIsPreserved() throws {
        let rows = try SparkleUpdateCatalog.decode(feed(item("201", extra: "<sparkle:shortVersionString>2.0</sparkle:shortVersionString>") + item("199")))
        XCTAssertEqual(rows.map(\.version), ["201", "199"])
        XCTAssertEqual(rows[0].displayVersion, "2.0")
    }
    func testLegacyEnclosureVersionsAndDeltaExclusion() throws {
        let xml = "<item><enclosure url=\"https://example.com/full.zip\" sparkle:version=\"8\" sparkle:shortVersionString=\"1.8\"/><sparkle:deltas><enclosure url=\"https://example.com/delta.zip\" sparkle:version=\"9\" sparkle:deltaFrom=\"7\"/></sparkle:deltas></item>"
        let rows = try SparkleUpdateCatalog.decode(feed(xml))
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.version, "8")
        XCTAssertEqual(row.displayVersion, "1.8")
    }
    func testOSHardwareAndPreviewRequirements() throws {
        let xml = item("5", extra: "<sparkle:channel>beta</sparkle:channel><sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion><sparkle:maximumSystemVersion>28.0</sparkle:maximumSystemVersion><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>")
        let row = try XCTUnwrap(SparkleUpdateCatalog.decode(feed(xml)).first)
        let compare: (String, String) -> ComparisonResult = { $0.compare($1, options: .numeric) }
        XCTAssertTrue(row.prerelease)
        XCTAssertTrue(row.supports(os: "27.0", architecture: "arm64", compare: compare))
        XCTAssertFalse(row.supports(os: "25.0", architecture: "arm64", compare: compare))
        XCTAssertFalse(row.supports(os: "29.0", architecture: "arm64", compare: compare))
        XCTAssertFalse(row.supports(os: "27.0", architecture: "x86_64", compare: compare))
        let implicit = try XCTUnwrap(SparkleUpdateCatalog.decode(feed(item("2.0rc1"))).first)
        XCTAssertTrue(implicit.prerelease)
    }
    func testWrongPlatformUnsafeDownloadsAndMissingVersionsAreNotCandidates() throws {
        let xml = item("3", attributes: "sparkle:os=\"windows\"") + "<item><enclosure url=\"file:///tmp/install.pkg\" sparkle:version=\"5\"/></item><item><enclosure url=\"https://example.com/a.zip\"/></item>"
        XCTAssertTrue(try SparkleUpdateCatalog.decode(feed(xml)).isEmpty)
    }
    func testNamespaceAliasesAreAcceptedAndSpoofedNamespaceIsIgnored() throws {
        let alias = Data("<rss xmlns:x=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><item><enclosure url=\"https://example.com/app.zip\" x:version=\"4\"/></item></channel></rss>".utf8)
        XCTAssertEqual(try SparkleUpdateCatalog.decode(alias).first?.version, "4")
        let spoof = Data("<rss xmlns:sparkle=\"https://unrelated.example/namespace\"><item><enclosure url=\"https://example.com/app.zip\" sparkle:version=\"4\"/></item></rss>".utf8)
        XCTAssertTrue(try SparkleUpdateCatalog.decode(spoof).isEmpty)
    }
    func testMalformedOversizedAndEntityFeedsFailExplicitly() {
        for data in [Data("<rss><item>".utf8), Data(repeating: 32, count: 2_097_153), Data("<!DOCTYPE rss [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><rss>&secret;</rss>".utf8)] {
            XCTAssertThrowsError(try SparkleUpdateCatalog.decode(data))
        }
    }
    func testUTF16FeedsAndEntityDeclarationsWithoutBOM() throws {
        let valid = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + String(data: feed(item("5")), encoding: .utf8)!
        let entity = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE rss [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><rss>&secret;</rss>"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            XCTAssertEqual(try SparkleUpdateCatalog.decode(valid.data(using: encoding)!).first?.version, "5")
            XCTAssertThrowsError(try SparkleUpdateCatalog.decode(entity.data(using: encoding)!))
        }
    }
    func testAppStoreMatchesBundleIdentityAndMacEditionOnly() throws {
        let data = Data(#"{"resultCount":4,"results":[{"kind":"mac-software","bundleId":"com.example.app","version":"2.5","trackId":123,"minimumOsVersion":"26.1"},{"kind":"software","bundleId":"com.example.app","version":"99","trackId":124},{"kind":"mac-software","bundleId":"com.other.app","version":"100","trackId":125},{"kind":"mac-software","bundleId":"com.example.app","version":"3","trackId":-2}]}"#.utf8)
        let rows = try AppStoreUpdateCatalog.decode(data, requested: ["com.example.app"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows["com.example.app"]?.version, "2.5")
        XCTAssertEqual(rows["com.example.app"]?.storeID, 123)
    }
    func testEmptyCatalogMeansUnmatchedAndMalformedCatalogThrows() throws {
        XCTAssertTrue(try AppStoreUpdateCatalog.decode(Data(#"{"resultCount":0,"results":[]}"#.utf8), requested: ["app.id"]).isEmpty)
        XCTAssertThrowsError(try AppStoreUpdateCatalog.decode(Data(#"{"resultCount":1,"results":[]}"#.utf8), requested: []))
    }
    func testLookupBatchesValidateIDsAndStoreCountryAndUseMacEntity() throws {
        let url = try ApplicationUpdateURL.lookup(bundleIDs: ["com.apple.dt.Xcode", "com.example.app"], country: "tr")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "bundleId" }?.value, "com.apple.dt.Xcode,com.example.app")
        XCTAssertEqual(items.first { $0.name == "entity" }?.value, "desktopSoftware")
        for id in ["../app", "com.app&country=us", "", "app id"] { XCTAssertThrowsError(try ApplicationUpdateURL.lookup(bundleIDs: [id], country: "TR")) }
        XCTAssertThrowsError(try ApplicationUpdateURL.lookup(bundleIDs: ["app.id"], country: "ZZ"))
        XCTAssertThrowsError(try ApplicationUpdateURL.lookup(bundleIDs: Array(repeating: "app.id", count: 21), country: "TR"))
    }
    func testSourcesDefaultToLocalHomebrewAndPersist() {
        let defaults = temporaryDefaults()
        var settings = ApplicationUpdateSettings.load(from: defaults)
        XCTAssertEqual(settings.sources, [.homebrew])
        XCTAssertFalse(settings.includePrereleases)
        settings.sources = [.appStore, .sparkle]
        settings.country = "TR"
        settings.includePrereleases = true
        settings.save(to: defaults)
        XCTAssertEqual(ApplicationUpdateSettings.load(from: defaults), settings)
    }
    func testMetadataTransportRejectsUnsafeSchemesWithoutNetwork() async {
        for raw in ["http://example.com/feed", "file:///tmp/feed", "https://user:password@example.com/feed"] {
            do { _ = try await ApplicationUpdateHTTP.fetch(URL(string: raw)!); XCTFail("Accepted unsafe metadata URL") } catch {}
        }
    }
}
