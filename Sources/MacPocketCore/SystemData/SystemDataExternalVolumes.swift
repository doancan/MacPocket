import Foundation

/// Which mounted volumes the Projects search may look into when the user has switched external drives on.
/// Only plugged-in, writable, local drives qualify. Time Machine disks, network shares, read-only volumes and
/// the Mac's own disks are never walked, and nothing but the usual project folders at the top of a drive is.
public enum SystemDataExternalVolumes {
    public static let defaultsKey = "MacPocket.systemData.externalProjects"
    public static let projectFolderNames = ["Developer", "Projects", "Projeler", "Code", "dev"]

    public struct Volume: Equatable, Sendable {
        public let url: URL
        public let isLocal: Bool
        public let isInternal: Bool
        public let isReadOnly: Bool
        public let isRootFileSystem: Bool
        public let isTimeMachineDestination: Bool

        public init(url: URL, isLocal: Bool, isInternal: Bool, isReadOnly: Bool, isRootFileSystem: Bool, isTimeMachineDestination: Bool) {
            self.url = url
            self.isLocal = isLocal
            self.isInternal = isInternal
            self.isReadOnly = isReadOnly
            self.isRootFileSystem = isRootFileSystem
            self.isTimeMachineDestination = isTimeMachineDestination
        }
    }

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: defaultsKey) }

    public static func isEligible(_ volume: Volume) -> Bool {
        volume.isLocal && !volume.isInternal && !volume.isReadOnly && !volume.isRootFileSystem && !volume.isTimeMachineDestination
            && volume.url.path.hasPrefix("/Volumes/") && volume.url.path != "/Volumes/"
    }

    /// Mounted volumes read from the system. Reading only asks for resource values; nothing is opened or
    /// walked.
    public static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let timeMachine = FileManager.default.fileExists(atPath: url.appending(path: "Backups.backupdb").path)
                || FileManager.default.fileExists(atPath: url.appending(path: ".com.apple.timemachine.supported").path)
            return Volume(url: url, isLocal: values.volumeIsLocal ?? false, isInternal: values.volumeIsInternal ?? true,
                          isReadOnly: values.volumeIsReadOnly ?? true, isRootFileSystem: values.volumeIsRootFileSystem ?? false,
                          isTimeMachineDestination: timeMachine)
        }
    }

    public static func eligibleVolumeURLs() -> [URL] { mounted().filter(isEligible).map(\.url) }
}
