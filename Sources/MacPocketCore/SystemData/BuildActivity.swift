import Darwin
import Foundation

/// Finds build tools that are running inside a folder. Deleting or rewriting a build folder under a running
/// compiler breaks that build, so removal and compression refuse until the tool is done.
public enum BuildActivity {
    public static let toolNames: Set<String> = [
        "cargo", "rustc", "rustdoc", "clippy-driver", "cc", "clang", "clang++", "ld", "lld", "swift-build", "swift-frontend", "swiftc",
        "xcodebuild", "gradle", "java", "node", "npm", "pnpm", "yarn", "bun", "deno", "make", "cmake", "ninja", "go", "tsc", "dotnet", "mvn",
    ]

    /// The names of known build tools whose working directory is `root` or inside it, without duplicates,
    /// sorted.
    public static func runningTools(under root: String, toolNames: Set<String> = BuildActivity.toolNames) -> [String] {
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        let own = getpid()
        var found = Set<String>()
        for pid in pids.prefix(Int(filled) / MemoryLayout<pid_t>.size) where pid > 0 && pid != own {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard toolNames.contains(name) else { continue }
            var info = proc_vnodepathinfo()
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { continue }
            let cwd = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if cwd == root || cwd.hasPrefix(rootPrefix) { found.insert(name) }
        }
        return found.sorted()
    }
}
