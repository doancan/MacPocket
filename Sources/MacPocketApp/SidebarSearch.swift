import MacPocketCore
import SwiftUI

/// Where a sidebar search result leads.
enum SidebarDestination: Hashable {
    case page(PocketPage)
    case tool(String)
}

/// Everything reachable from the sidebar: pages, catalog tools, network tabs and practical tools. Built once;
/// titles follow the app language chosen at launch.
@MainActor
struct SidebarSearchIndex {
    struct Item: Identifiable {
        let entry: CommandSearchEntry
        let symbol: String
        let destination: SidebarDestination
        var id: String { entry.id }
    }

    static let shared = SidebarSearchIndex()
    let items: [Item]

    private init() {
        var items = PocketPage.allCases.map { page in
            Item(entry: .init(id: "page:" + page.rawValue, title: page.localizedTitle, kind: .tool),
                 symbol: page.icon, destination: .page(page))
        }
        items += NetworkTab.allCases.map { tab in
            Item(entry: .init(id: "tool:" + tab.id, title: tab.title, subtitle: String(localized: "Ağ Yönetimi"),
                              keywords: tab.detail, kind: .tool),
                 symbol: tab.symbol, destination: .tool(tab.id))
        }
        items += ApplicationsSection.searchable.map { section in
            Item(entry: .init(id: "tool:" + section.id, title: section.title, subtitle: PocketPage.applications.localizedTitle,
                              keywords: section.searchKeywords + " " + section.detail, kind: .tool),
                 symbol: section.symbol, destination: .tool(section.id))
        }
        items += HubTool.catalog.map { tool in
            Item(entry: .init(id: "tool:" + tool.id, title: tool.title, subtitle: tool.category.title,
                              keywords: tool.searchKeywords + " " + tool.description, kind: .tool),
                 symbol: tool.icon, destination: .tool(tool.id))
        }
        self.items = items
    }

    func results(for query: String) -> [Item] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CommandSearch.results(items.map(\.entry), query: query, limit: 30).compactMap { byID[$0.id] }
    }
}

/// The result list that replaces the sidebar sections while the search field has text.
struct SidebarSearchResults: View {
    let query: String
    let open: (SidebarDestination) -> Void

    var body: some View {
        let results = SidebarSearchIndex.shared.results(for: query)
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Section("Sonuçlar") {
                ForEach(results) { item in
                    Button { open(item.destination) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: item.entry.title).lineLimit(1)
                                if !item.entry.subtitle.isEmpty {
                                    Text(verbatim: item.entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        } icon: {
                            Image(systemName: item.symbol)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
