import Foundation

extension SystemDataCatalog {
    /// Existing, canonical directories for catalog locations. A trailing `*` matches any suffix in the last
    /// component. Paths nested inside another returned path are dropped so nothing is counted twice.
    static func resolve(_ locations: [String], home: URL, systemRoot: URL = URL(fileURLWithPath: "/")) -> [String] {
        var found = Set<String>()
        for location in locations {
            let base = location.hasPrefix("/") ? absoluteURL(location, systemRoot: systemRoot)
                                               : home.appending(path: location, directoryHint: .isDirectory)
            let candidates: [URL]
            if base.lastPathComponent.hasSuffix("*") {
                let prefix = String(base.lastPathComponent.dropLast())
                let parent = base.deletingLastPathComponent()
                candidates = ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
                    .filter { $0.hasPrefix(prefix) }.sorted().map { parent.appending(path: $0, directoryHint: .isDirectory) }
            } else {
                candidates = [base]
            }
            for url in candidates {
                guard let canonical = existingCanonicalPath(url) else { continue }
                var info = stat()
                guard lstat(canonical, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
                found.insert(canonical)
            }
        }
        let sorted = found.sorted()
        return sorted.filter { path in !sorted.contains { $0 != path && path.hasPrefix($0 + "/") } }
    }

    /// An absolute location under `systemRoot`; with the real root this is the path itself.
    static func absoluteURL(_ path: String, systemRoot: URL) -> URL {
        systemRoot.path == "/" ? URL(fileURLWithPath: path) : systemRoot.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
    }

    /// The places developer tools install to; GUI apps do not inherit a shell PATH.
    static func defaultToolSearchPaths(home: URL) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.path + "/.docker/bin", home.path + "/.orbstack/bin",
         "/Applications/Docker.app/Contents/Resources/bin", "/Applications/Ollama.app/Contents/Resources"]
    }

    /// First executable named `name` in `directories`.
    static func executable(named name: String, in directories: [String]) -> String? {
        directories.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Project build folders

struct ProjectBuildFolder: Equatable {
    let project: String
    let folder: String
    let kind: Kind
    /// Newest change among the project's own files, not counting what the build or an install produced.
    let lastActivity: Date?

    struct Kind: Equatable {
        let folderName: String
        /// A project is a folder holding one of these next to the build folder.
        let markers: [String]
        let rebuildCost: SystemDataRegeneration
    }
}

enum SystemDataProjectFinder {
    static let kinds: [ProjectBuildFolder.Kind] = [
        .init(folderName: "node_modules", markers: ["package.json"], rebuildCost: .downloadsAgain),
        .init(folderName: ".next", markers: ["package.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".nuxt", markers: ["package.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".svelte-kit", markers: ["package.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".astro", markers: ["package.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".angular", markers: ["package.json", "angular.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".turbo", markers: ["package.json", "turbo.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".parcel-cache", markers: ["package.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".expo", markers: ["package.json", "app.json"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".build", markers: ["Package.swift"], rebuildCost: .rebuildsLocally),
        .init(folderName: "Pods", markers: ["Podfile"], rebuildCost: .downloadsAgain),
        .init(folderName: "target", markers: ["Cargo.toml"], rebuildCost: .rebuildsLocally),
        .init(folderName: "build", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], rebuildCost: .rebuildsLocally),
        .init(folderName: ".venv", markers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"], rebuildCost: .downloadsAgain),
        .init(folderName: "venv", markers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"], rebuildCost: .downloadsAgain),
    ]

    static let skippedDirectoryNames: Set<String> = ["Library", "Applications", ".Trash", ".git", "Pictures", "Music", "Movies", "Public"]
    /// Bundles and libraries are leaves for this search: no project lives inside them.
    static let leafExtensions: Set<String> = ["app", "framework", "xcodeproj", "xcworkspace", "xcassets", "xcframework", "photoslibrary",
                                              "bundle", "lproj", "plugin", "appex", "playground", "imovielibrary", "fcpbundle", "tvlibrary"]
    static let maximumDepth = 5
    static let maximumDirectories = 60_000

    /// Searches the usual project folders under `home` for build folders next to a project marker file.
    static func find(home: URL, roots: [String], control: StorageScanControl) -> [ProjectBuildFolder] {
        let fm = FileManager.default
        var results: [ProjectBuildFolder] = []
        var visited = 0
        func walk(_ directory: String, depth: Int) {
            guard depth <= maximumDepth, visited < maximumDirectories, !control.isCancelled,
                  let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
            visited += 1
            let nameSet = Set(names)
            var claimed = Set<String>()
            for kind in kinds where nameSet.contains(kind.folderName) {
                guard kind.markers.contains(where: nameSet.contains) else { continue }
                let folder = directory + "/" + kind.folderName
                guard isRealDirectory(folder) else { continue }
                results.append(ProjectBuildFolder(project: directory, folder: folder, kind: kind,
                                                  lastActivity: projectActivity(directory, names: names)))
                claimed.insert(kind.folderName)
            }
            let buildNames = Set(kinds.map(\.folderName))
            for name in names where !claimed.contains(name) && !buildNames.contains(name)
                && !name.hasPrefix(".") && !skippedDirectoryNames.contains(name)
                && !leafExtensions.contains((name as NSString).pathExtension.lowercased()) {
                let child = directory + "/" + name
                if isRealDirectory(child) { walk(child, depth: depth + 1) }
            }
        }
        for root in roots {
            let path = home.appending(path: root, directoryHint: .isDirectory).path
            if isRealDirectory(path) { walk(path, depth: 0) }
        }
        return results
    }

    static func isRealDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// Newest change among the project's own top-level files and git index; lockfiles and dotfiles are
    /// ignored because an install or a tool run touches them without anyone having worked on the project.
    static func projectActivity(_ directory: String, names: [String]) -> Date? {
        let lockfiles: Set<String> = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", "Package.resolved",
                                      "Podfile.lock", "Cargo.lock", "poetry.lock", "uv.lock", "Gemfile.lock"]
        var newest: Int64 = 0
        var candidates = names.filter { !$0.hasPrefix(".") && !lockfiles.contains($0) }.map { directory + "/" + $0 }
        candidates.append(directory + "/.git/index")
        for path in candidates {
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG || path.hasSuffix("/.git/index") else { continue }
            newest = max(newest, Int64(info.st_mtimespec.tv_sec))
        }
        return newest > 0 ? Date(timeIntervalSince1970: Double(newest)) : nil
    }
}

extension SystemDataScanner {
    /// Runs `transform` over the inputs with at most `limit` in flight. Results come back in no particular
    /// order.
    static func concurrentMap<Input: Sendable, Output: Sendable>(_ inputs: [Input], limit: Int = 4,
                                                                  _ transform: @escaping @Sendable (Input) async -> Output?) async -> [Output] {
        await withTaskGroup(of: Output?.self) { group in
            var iterator = inputs.makeIterator()
            var results: [Output] = []
            for _ in 0..<max(1, limit) { if let next = iterator.next() { group.addTask { await transform(next) } } }
            while let result = await group.next() {
                if let result { results.append(result) }
                if !Task.isCancelled, let next = iterator.next() { group.addTask { await transform(next) } }
            }
            return results
        }
    }

    static let minimumProjectFolderBytes: Int64 = 20_000_000

    static func projectItems(env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry,
                             completeness: ScanCompleteness) async -> [SystemDataItem] {
        let volumes = env.includeExternalProjects ? env.externalVolumes() : []
        let found = await StorageWork.run(control) {
            var all = SystemDataProjectFinder.find(home: env.home, roots: SystemDataCatalog.projectRoots, control: control)
            for volume in volumes {
                all += SystemDataProjectFinder.find(home: volume, roots: SystemDataExternalVolumes.projectFolderNames, control: control)
            }
            return all
        }
        let items = await concurrentMap(found) { entry -> SystemDataItem? in
            guard let canonical = existingCanonicalPath(URL(fileURLWithPath: entry.folder)) else { return nil }
            control.setCurrent(URL(fileURLWithPath: entry.project).lastPathComponent + "/" + entry.kind.folderName)
            let measurement = await StorageWork.run(control) { DirectorySizer.measure(canonical, control: control, links: links) }
            completeness.note(measurement)
            guard measurement.allocatedBytes >= minimumProjectFolderBytes else { return nil }
            let projectName = URL(fileURLWithPath: entry.project).lastPathComponent
            return SystemDataItem(
                id: "project.\(canonical)", group: .projects, title: "\(entry.kind.folderName) — \(projectName)",
                detail: entry.kind.rebuildCost == .downloadsAgain
                    ? String(localized: "Bağımlılıklar; proje yeniden kurulunca indirilir.")
                    : String(localized: "Derleme çıktısı; proje yeniden derlenince oluşur."),
                safety: .review, regeneration: entry.kind.rebuildCost, paths: [canonical], sizeBytes: measurement.allocatedBytes,
                lastActivity: entry.lastActivity ?? Date(timeIntervalSince1970: Double(measurement.newestModification)),
                action: .removeFolder, projectPath: entry.project)
        }
        return items.sorted { $0.id < $1.id }
    }

    // MARK: Unexplained large folders

    static let homeFolderThreshold: Int64 = 500_000_000
    static let libraryFolderThreshold: Int64 = 200_000_000
    static let cacheFolderThreshold: Int64 = 100_000_000
    /// User data that Storage settings counts as Documents, Photos or Music, not as System Data.
    /// The folders projects are searched in hold the user's own work; only their build folders are reported.
    static let userDataFolders = Set<String>(["Library", "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", ".Trash"] + SystemDataCatalog.projectRoots)

    static func catchAllItems(env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry, covered: Set<String>,
                              completeness: ScanCompleteness) async -> [SystemDataItem] {
        struct Candidate { let url: URL; let threshold: Int64 }
        var candidates: [Candidate] = []
        let fm = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted().map { url.appending(path: $0, directoryHint: .isDirectory) }
        }
        for url in children(env.home) where !userDataFolders.contains(url.lastPathComponent) {
            candidates.append(Candidate(url: url, threshold: homeFolderThreshold))
        }
        let library = env.home.appending(path: "Library", directoryHint: .isDirectory)
        for (folder, threshold) in [("Application Support", libraryFolderThreshold), ("Containers", libraryFolderThreshold),
                                    ("Group Containers", libraryFolderThreshold), ("Caches", cacheFolderThreshold)] {
            for url in children(library.appending(path: folder, directoryHint: .isDirectory)) {
                candidates.append(Candidate(url: url, threshold: threshold))
            }
        }
        for root in ["/opt", "/usr/local", "/Users/Shared"] {
            for url in children(SystemDataCatalog.absoluteURL(root, systemRoot: env.systemRoot)) { candidates.append(Candidate(url: url, threshold: homeFolderThreshold)) }
        }

        let items = await concurrentMap(candidates) { candidate -> SystemDataItem? in
            guard !control.isCancelled, let path = existingCanonicalPath(candidate.url) else { return nil }
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
            // Inside a place another probe explains: skip. Containing one: measure only what is left over.
            if covered.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return nil }
            control.setCurrent(candidate.url.lastPathComponent)
            let inside = covered.filter { $0.hasPrefix(path + "/") }
            let measurement = await StorageWork.run(control) { DirectorySizer.measure(path, control: control, links: links, excluding: inside) }
            completeness.note(measurement)
            guard measurement.allocatedBytes >= candidate.threshold else { return nil }
            let name = candidate.url.lastPathComponent
            let (detail, regeneration) = ownerDescription(name: name, env: env)
            return SystemDataItem(
                id: "other.\(path)", group: .other, title: name, detail: detail, safety: .review, regeneration: regeneration,
                paths: [path], sizeBytes: measurement.allocatedBytes,
                lastActivity: measurement.newestModification > 0 ? Date(timeIntervalSince1970: Double(measurement.newestModification)) : nil,
                action: .removeFolder)
        }
        return items.sorted { $0.id < $1.id }
    }

    /// Folder names in Containers, Group Containers and Caches are bundle identifiers, sometimes behind a
    /// team ID (`UBF8T346G9.com.microsoft.teams`) or a `group.` prefix. Returns the identifiers worth looking
    /// up.
    static func bundleIdentifierCandidates(from name: String) -> [String] {
        let pattern = #"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else { return [] }
        var candidates = [name]
        var stripped = name
        if stripped.hasPrefix("group.") { stripped.removeFirst("group.".count) }
        if let dot = stripped.firstIndex(of: "."), stripped[..<dot].count == 10,
           stripped[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) { stripped = String(stripped[stripped.index(after: dot)...]) }
        if stripped != name { candidates.append(stripped) }
        return candidates
    }

    private static func ownerDescription(name: String, env: SystemDataEnvironment) -> (String, SystemDataRegeneration) {
        let candidates = bundleIdentifierCandidates(from: name)
        for id in candidates {
            if id.hasPrefix("com.apple.") { return (String(localized: "macOS’un kendi verisi; kaldırmak sistem özelliklerini sıfırlayabilir."), .rebuildsLocally) }
            if let app = env.installedAppName(id) {
                return (String(localized: "\(app) uygulamasına ait; silersen uygulamanın bu verisi sıfırlanır."), .doesNotReturn)
            }
        }
        if let id = candidates.last {
            return (String(localized: "\(id) tarafından bırakıldı; uygulama artık bu Mac’te kurulu değil."), .notNeededAgain)
        }
        return (String(localized: "Başka bir kategorinin açıklamadığı büyük klasör. Silmeden önce içine bak."), .doesNotReturn)
    }
}
