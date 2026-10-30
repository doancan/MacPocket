import XCTest
@testable import MacPocketCore

final class ScreenRecordingFilesTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/Kayıtlar")
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testNamesNeverOverwrite() {
        var taken: Set<String> = []
        let first = ScreenRecordingFiles.url(in: folder, at: date, prefix: "Ekran Kaydı") { taken.contains($0.lastPathComponent) }
        taken.insert(first.lastPathComponent)
        let second = ScreenRecordingFiles.url(in: folder, at: date, prefix: "Ekran Kaydı") { taken.contains($0.lastPathComponent) }
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Ekran Kaydı 2027-01-15 "))
        XCTAssertEqual(first.pathExtension, "mov")
        XCTAssertEqual(second.lastPathComponent, first.deletingPathExtension().lastPathComponent + " (2).mov")
        XCTAssertEqual(first.deletingLastPathComponent().path, folder.path)
    }

    func testDurationText() {
        XCTAssertEqual(ScreenRecordingFiles.duration(65), "1:05")
        XCTAssertEqual(ScreenRecordingFiles.duration(720), "12:00")
        XCTAssertEqual(ScreenRecordingFiles.duration(3723), "1:02:03")
        XCTAssertEqual(ScreenRecordingFiles.duration(-5), "0:00")
    }

    func testSettingsFixUnknownFrameRate() {
        let defaults = UserDefaults(suiteName: "ScreenRecordingTests")!
        defer { defaults.removePersistentDomain(forName: "ScreenRecordingTests") }
        var settings = ScreenRecordingSettings()
        settings.framesPerSecond = 144
        settings.save(to: defaults)
        XCTAssertEqual(ScreenRecordingSettings.load(from: defaults).framesPerSecond, 60)
    }
}
