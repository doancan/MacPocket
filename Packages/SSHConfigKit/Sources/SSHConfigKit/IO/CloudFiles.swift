import Foundation

enum CloudFiles {
    /// SF_DATALESS (sys/stat.h): the file's content lives in the cloud and is fetched on first read.
    private static let datalessFlag: UInt32 = 0x4000_0000

    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & datalessFlag != 0
    }
}
