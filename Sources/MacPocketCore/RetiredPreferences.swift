import Foundation

/// Settings of features that were removed. Deleted at launch so nothing a person saved (window layouts,
/// repository links) lingers once no code reads it; removing a missing key is a no-op, so this is safe on
/// every launch.
public enum RetiredPreferences {
    public static let keys: Set<String> = [
        "MacPocket.workspaces",                      // Masa Düzenleri: saved window layouts
        "MacPocket.modules.workspaces.available",
        "MacPocket.updateCenter.repositories",       // Güncelleme Merkezi: per-app GitHub repositories
    ]

    public static func remove(from defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
