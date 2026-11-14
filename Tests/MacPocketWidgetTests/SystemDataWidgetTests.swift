import Foundation
import MacPocketShared
import SwiftUI
import Testing
import WidgetKit
@testable import MacPocketWidgetUI

@MainActor
@Suite struct SystemDataWidgetTests {
    private let summary = SystemDataSummary(date: Date(timeIntervalSince1970: 1_800_000_000), systemDataBytes: 41_000_000_000,
                                            safeBytes: 6_000_000_000, freeBytes: 167_000_000_000, purgeableBytes: 7_000_000_000)

    @Test func theSummaryFileTheAppWritesIsExactlyWhatTheWidgetReads() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = directory.appending(path: "system-data-summary.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        summary.save(to: defaults, file: file)
        #expect(SystemDataSummary.load(fromFile: file) == summary)
        #expect(SystemDataSummary.load(fromFile: directory.appending(path: "missing.json")) == nil)
        try Data("{broken".utf8).write(to: file)
        #expect(SystemDataSummary.load(fromFile: file) == nil, "a damaged file shows the empty state instead of crashing")
    }

    @Test func savingWithoutAFileNeverTouchesTheDisk() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let before = try? Data(contentsOf: SystemDataSummary.fileURL)
        summary.save(to: defaults)
        #expect((try? Data(contentsOf: SystemDataSummary.fileURL)) == before)
    }

    @Test func theTimelineCarriesTheSummaryAndAsksForARefreshInThirtyMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let timeline = SystemDataProvider(load: { [summary] in summary }).timeline(now: now)
        #expect(timeline.entries == [SystemDataEntry(date: now, summary: summary)])
        #expect(String(describing: timeline.policy) == String(describing: TimelineReloadPolicy.after(now.addingTimeInterval(30 * 60))))
    }

    @Test func withoutAScanTheEntryIsEmptyAndThePreviewShowsSampleNumbers() {
        let provider = SystemDataProvider(load: { nil })
        #expect(provider.snapshotEntry(isPreview: false).summary == nil)
        #expect(provider.snapshotEntry(isPreview: true).summary != nil)
        #expect(provider.sampleEntry().summary?.systemDataBytes == 41_000_000_000)
        #expect(provider.timeline().entries.first?.summary == nil, "the empty state is shown, nothing is invented")
    }

    @Test func bothSizesRenderTheNumbersAndTheEmptyStateRenders() throws {
        for (family, summary) in [(WidgetFamily.systemSmall, Optional(summary)), (.systemMedium, summary), (.systemSmall, nil)] {
            let size = family == .systemSmall ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
            let view = SystemDataWidgetView(entry: SystemDataEntry(date: Date(), summary: summary), family: family)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            #expect(image.size.width > 100 && image.size.height > 100)
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                let name = "widget-\(family == .systemSmall ? "small" : "medium")-\(summary == nil ? "empty" : "data").png"
                try? png.write(to: URL(fileURLWithPath: "/tmp/claude-501/widget-render").appending(path: name))
            }
        }
    }
}
