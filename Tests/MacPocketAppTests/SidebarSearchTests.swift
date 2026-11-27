import XCTest
@testable import MacPocketApp
@testable import MacPocketCore

@MainActor
final class SidebarSearchTests: XCTestCase {
    func testFindsPagesToolsAndNetworkTabsByTurkishAndAsciiSpelling() {
        let index = SidebarSearchIndex.shared
        XCTAssertEqual(index.results(for: "wi-fi").first?.destination, .tool("wifi"))
        XCTAssertEqual(index.results(for: "ag yonetimi").first?.destination, .page(.network), "ASCII typing finds Turkish titles")
        XCTAssertTrue(index.results(for: "tanılama").contains { $0.destination == .tool(NetworkTab.diagnosis.id) })
        XCTAssertTrue(index.results(for: "json").contains { $0.destination == .tool("practical-tools") }, "descriptions are searched too")
    }

    func testEveryResultOpensSomethingThatExists() {
        let model = PocketModel(startMonitoring: false)
        for item in SidebarSearchIndex.shared.items {
            guard case .tool(let id) = item.destination else { continue }
            model.navigation.select(.overview)
            model.openCatalogTool(id)
            XCTAssertTrue(model.navigation.page != .overview || model.navigation.tool != nil, "\(id) does not route anywhere")
        }
    }

    func testAppLeftoversLivesInApplicationsInsteadOfTools() {
        XCTAssertFalse(HubTool.catalog.contains { $0.id == ApplicationsSection.leftovers.rawValue })
        XCTAssertFalse(HubCategory.allCases.contains { $0.rawValue == "Uygulamalar" }, "no empty Tools category is left behind")
        let hit = SidebarSearchIndex.shared.results(for: "kalıntı").first
        XCTAssertEqual(hit?.destination, .tool(ApplicationsSection.leftovers.rawValue), "still findable from search")
        let model = PocketModel(startMonitoring: false)
        model.openCatalogTool(ApplicationsSection.leftovers.rawValue)
        XCTAssertEqual(model.navigation.page, .applications)
        XCTAssertNil(model.navigation.tool)
        XCTAssertEqual(model.applications.section, .leftovers)
    }

    func testApplicationsSectionsRouteToTheirTab() {
        let model = PocketModel(startMonitoring: false)
        for section in ApplicationsSection.allCases {
            model.navigation.select(.overview)
            model.openCatalogTool(section.rawValue)
            XCTAssertEqual(model.navigation.page, .applications)
            XCTAssertEqual(model.applications.section, section)
        }
    }

    func testUpdateCenterIsRemoved() {
        XCTAssertFalse(HubTool.catalog.contains { $0.id == "update-center" })
        XCTAssertNil(PocketTool(rawValue: "Güncelleme Merkezi"), "a remembered launch tool falls back to the Tools hub")
        XCTAssertFalse(SidebarSearchIndex.shared.items.contains { $0.destination == .tool("update-center") })
    }

    func testNoMatchesAndOversizedQueriesReturnNothing() {
        XCTAssertTrue(SidebarSearchIndex.shared.results(for: "zzzqqq").isEmpty)
        XCTAssertTrue(SidebarSearchIndex.shared.results(for: String(repeating: "a", count: 300)).isEmpty)
    }
}

@MainActor
final class SidebarIconStyleTests: XCTestCase {
    func testNewInstallationsStartWithMonochromeIcons() {
        XCTAssertEqual(PocketSidebarIconStyle.standard, .monochrome)
    }
}
