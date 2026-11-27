import Foundation
import Testing
@testable import MacPocketSSH

struct StandaloneMigrationTests {
    @Test func importsPreferencesFavoritesAndBackupsWithoutChangingTheOriginal() throws {
        let tmp = try TempDir()
        let backup = try tmp.file("old/config/20261105-180000-config", "Host web\n")
        let original = try Data(contentsOf: backup)
        let legacy: [String: Any] = ["configPath": "~/ssh-custom", "terminal": "ghostty", "backupCount": 20,
                                  "hostMemory.config": ["favorites": ["web"], "recents": ["web"]],
                                  "appearance": "dark"]
        let destination = tmp.url.appending(path: "new")
        try SSHStandaloneMigration.run(defaults: tmp.defaults, legacy: legacy,
            oldBackups: tmp.url.appending(path: "old"), newBackups: destination)
        #expect(tmp.defaults.string(forKey: "configPath") == "~/ssh-custom")
        #expect(tmp.defaults.string(forKey: "terminal") == "ghostty")
        #expect(tmp.defaults.dictionary(forKey: "hostMemory.config")?["favorites"] as? [String] == ["web"])
        #expect(tmp.defaults.object(forKey: "appearance") == nil)
        #expect(try Data(contentsOf: destination.appending(path: "config/20261105-180000-config")) == original)
        #expect(try Data(contentsOf: backup) == original)
        #expect(tmp.defaults.bool(forKey: SSHStandaloneMigration.completedKey))
    }

    @Test func importIsIdempotentAndNeverOverwritesMacPocketSettings() throws {
        let tmp = try TempDir()
        tmp.defaults.set("iterm2", forKey: "terminal")
        let absent = tmp.url.appending(path: "absent")
        try SSHStandaloneMigration.run(defaults: tmp.defaults, legacy: ["terminal": "ghostty"], oldBackups: absent, newBackups: absent)
        #expect(tmp.defaults.string(forKey: "terminal") == "iterm2")
        try SSHStandaloneMigration.run(defaults: tmp.defaults, legacy: ["configPath": "/other"], oldBackups: absent, newBackups: absent)
        #expect(tmp.defaults.object(forKey: "configPath") == nil)
    }

    @Test func filenameCollisionPreservesBothBackups() throws {
        let tmp = try TempDir()
        _ = try tmp.file("old/config/20261105-180000-config", "Host imported\n")
        _ = try tmp.file("new/config/20261105-180000-config", "Host existing\n")
        try SSHStandaloneMigration.run(defaults: tmp.defaults, legacy: [:],
            oldBackups: tmp.url.appending(path: "old"), newBackups: tmp.url.appending(path: "new"))
        #expect(try tmp.read("new/config/20261105-180000-config") == "Host existing\n")
        #expect(try tmp.read("new/config/20261105-180000_2-config") == "Host imported\n")
        #expect(try tmp.read("old/config/20261105-180000-config") == "Host imported\n")
    }

    @Test func importsCustomGlobalShortcutWithoutOverwritingMacPocketShortcut() throws {
        let tmp = try TempDir()
        let absent = tmp.url.appending(path: "absent")
        let encoded = "{\"carbonKeyCode\":1,\"carbonModifiers\":2304}"
        try SSHStandaloneMigration.run(defaults: tmp.defaults,
            legacy: ["KeyboardShortcuts_quickConnect": encoded], oldBackups: absent, newBackups: absent,
            shortcutDefaults: tmp.defaults)
        #expect(tmp.defaults.string(forKey: "KeyboardShortcuts_MacPocket.SSH.quickConnect") == encoded)
    }

    @Test func failedBackupImportRemainsRetryable() throws {
        let tmp = try TempDir()
        _ = try tmp.file("old/config/20261105-180000-config", "Host original\n")
        let notDirectory = try tmp.file("blocked", "keep")
        #expect(throws: (any Error).self) {
            try SSHStandaloneMigration.run(defaults: tmp.defaults, legacy: [:], oldBackups: tmp.url.appending(path: "old"), newBackups: notDirectory)
        }
        #expect(!tmp.defaults.bool(forKey: SSHStandaloneMigration.completedKey))
        #expect(try tmp.read("blocked") == "keep")
    }
}
