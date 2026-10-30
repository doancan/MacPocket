import Foundation

public struct ScreenRecordingSettings: Codable, Equatable, Sendable {
    public enum Codec: String, Codable, CaseIterable, Sendable { case hevc, h264 }

    public var systemAudio = true
    public var microphone = false
    public var showCursor = true
    public var framesPerSecond = 60
    public var codec = Codec.hevc
    /// Folder path; nil uses ~/Movies.
    public var folder: String?
    public var shortcut: KeyCombo? = KeyCombo(keyCode: 15, modifiers: [.control, .option, .shift]) // ⌃⌥⇧R

    public static let frameRateChoices = [30, 60]
    public static let storageKey = "MacPocket.recording.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> ScreenRecordingSettings {
        guard let data = defaults.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(ScreenRecordingSettings.self, from: data) else { return ScreenRecordingSettings() }
        if !frameRateChoices.contains(settings.framesPerSecond) { settings.framesPerSecond = 60 }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum ScreenRecordingFiles {
    /// "Ekran Kaydı 2026-10-31 at 01.12.05.mov"-style name in the app language, never overwriting an existing file.
    public static func url(in folder: URL, at date: Date, prefix: String, exists: (URL) -> Bool) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(prefix) \(formatter.string(from: date))"
        var candidate = folder.appendingPathComponent(base + ".mov")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).mov")
            counter += 1
        }
        return candidate
    }

    /// "1:05", "12:00", "1:02:03".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
