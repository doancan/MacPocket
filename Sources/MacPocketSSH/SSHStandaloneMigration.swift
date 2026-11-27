import Foundation

/// Copies standalone preferences and backups once. The original app and all SSH files remain intact.
enum SSHStandaloneMigration {
    static let completedKey = "standaloneImportCompleted"
    static func run(defaults: UserDefaults, legacy: [String: Any], oldBackups: URL, newBackups: URL,
                    fileManager: FileManager = .default, shortcutDefaults: UserDefaults? = nil) throws {
        if let shortcutDefaults, !defaults.bool(forKey: "standaloneShortcutImported") {
            let targetKey = "KeyboardShortcuts_MacPocket.SSH.quickConnect"
            if shortcutDefaults.object(forKey: targetKey) == nil, let shortcut = legacy["KeyboardShortcuts_quickConnect"] {
                shortcutDefaults.set(shortcut, forKey: targetKey)
            }
            defaults.set(true, forKey: "standaloneShortcutImported")
        }
        guard !defaults.bool(forKey: completedKey) else { return }
        for (key, value) in legacy where ["configPath", "knownHostsPath", "backupCount", "terminal"].contains(key)
            || key.hasPrefix("hostMemory.") {
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        if fileManager.fileExists(atPath: oldBackups.path) {
            try merge(oldBackups, into: newBackups, fileManager: fileManager)
        }
        defaults.set(true, forKey: completedKey)
    }

    private static func merge(_ source: URL, into destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Backups are regular files/directories. Never import links to external locations.
            guard values.isSymbolicLink != true else { continue }
            let target = destination.appending(path: child.lastPathComponent)
            if values.isDirectory == true {
                try merge(child, into: target, fileManager: fileManager)
            } else {
                var copyTarget = target
                if fileManager.fileExists(atPath: target.path) {
                    if try Data(contentsOf: child) == Data(contentsOf: target) { continue }
                    // A filename collision must retain both backups. Preserve BackupManager's timestamp
                    // format.
                    let name = child.lastPathComponent
                    let stamp = String(name.prefix(15))
                    let suffix = name.dropFirst(15)
                    let originalName = suffix.drop(while: { $0 != "-" }).dropFirst()
                    guard name.count > 16, !originalName.isEmpty else {
                        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: target.path])
                    }
                    var sequence = 2
                    repeat {
                        copyTarget = destination.appending(path: "\(stamp)_\(sequence)-\(originalName)")
                        sequence += 1
                    } while fileManager.fileExists(atPath: copyTarget.path)
                }
                try fileManager.copyItem(at: child, to: copyTarget)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copyTarget.path)
            }
        }
    }
}
