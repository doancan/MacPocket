import Foundation

/// A place (or several) that holds System Data, with what it is, how careful to be and how to remove it.
struct SystemDataProbe: Sendable {
    let id: String
    let group: SystemDataGroup
    let title: String
    let detail: String
    let safety: SystemDataSafety
    let regeneration: SystemDataRegeneration
    /// Home-relative paths, or absolute when they start with "/". A trailing `*` in the last component matches any suffix.
    let locations: [String]
    let action: SystemDataAction
    var warning: String?
    var busyBundleIDs: [String] = []
}

enum SystemDataCatalog {
    /// Folders under a project that are build output; a project is any folder holding one of the marker files.
    static let projectRoots = ["Developer", "Projects", "Projeler", "Code", "dev", "Desktop", "Documents", "src", "repos", "workspace"]

    /// The fixed probes. Dynamic items (simulator runtimes, Docker, Ollama models, snapshots, backups, project build
    /// folders, unexplained large folders) come from the scanner.
    static func probes() -> [SystemDataProbe] {
        xcode + packages + toolchains + aiTools + logs + virtualMachines + android + appData + system + trash
    }

    // MARK: Xcode

    private static let xcode: [SystemDataProbe] = [
        .init(id: "xcode.derivedData", group: .xcode, title: String(localized: "DerivedData"),
              detail: String(localized: "Xcode’un derleme çıktıları ve dizinleri; bir sonraki derlemede yeniden oluşur."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Developer/Xcode/DerivedData"],
              action: .removeContents, busyBundleIDs: ["com.apple.dt.Xcode"]),
        .init(id: "xcode.deviceSupport", group: .xcode, title: String(localized: "Aygıt desteği dosyaları"),
              detail: String(localized: "Bağladığın iPhone, iPad, Watch ve TV aygıtlarının simge dosyaları; aygıt yeniden bağlanınca oluşur ve ilk bağlanma yavaş olur."),
              safety: .review, regeneration: .rebuildsLocally,
              locations: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport", "Library/Developer/Xcode/visionOS DeviceSupport"],
              action: .removeContents, busyBundleIDs: ["com.apple.dt.Xcode"]),
        .init(id: "xcode.archives", group: .xcode, title: String(localized: "Xcode arşivleri"),
              detail: String(localized: "Dağıtım için aldığın arşivler ve dSYM dosyaları; kaldırınca eski sürümlerin hata raporlarını çözemezsin."),
              safety: .review, regeneration: .doesNotReturn, locations: ["Library/Developer/Xcode/Archives"], action: .removeContents),
        .init(id: "xcode.previews", group: .xcode, title: String(localized: "SwiftUI önizleme aygıtları"),
              detail: String(localized: "Canvas önizlemelerinin kullandığı simülatör kopyaları; önizleme açılınca yeniden oluşur."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Developer/Xcode/UserData/Previews"], action: .removeContents),
        .init(id: "xcode.documentation", group: .xcode, title: String(localized: "Belge önbelleği"),
              detail: String(localized: "Xcode’un oluşturduğu belge dizinleri."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Developer/Xcode/DocumentationCache"], action: .removeContents),
        .init(id: "xcode.caches", group: .xcode, title: String(localized: "Xcode önbellekleri"),
              detail: String(localized: "Xcode’un kendi önbelleği ve Swift paket önbelleği."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Caches/com.apple.dt.Xcode", "Library/Caches/org.swift.swiftpm"], action: .removeContents,
              busyBundleIDs: ["com.apple.dt.Xcode"]),
        .init(id: "simulator.caches", group: .simulators, title: String(localized: "Simülatör önbellekleri"),
              detail: String(localized: "Simülatörlerin dyld önbellekleri; aygıt açılırken yeniden oluşur."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Developer/CoreSimulator/Caches"], action: .removeContents),
    ]

    // MARK: Package managers

    private static let packages: [SystemDataProbe] = [
        .init(id: "pkg.homebrew", group: .packages, title: String(localized: "Homebrew indirmeleri"),
              detail: String(localized: "Homebrew’un indirdiği paket arşivleri."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Caches/Homebrew"], action: .removeContents),
        .init(id: "pkg.npm", group: .packages, title: String(localized: "npm önbelleği"),
              detail: String(localized: "npm’in içerik adresli paket önbelleği ve günlükleri."),
              safety: .safe, regeneration: .downloadsAgain, locations: [".npm/_cacache", ".npm/_logs"], action: .removeContents),
        .init(id: "pkg.pnpm", group: .packages, title: String(localized: "pnpm deposu"),
              detail: String(localized: "pnpm’in ortak paket deposu; projelerin node_modules klasörleri bu dosyalara sabit bağlıdır."),
              safety: .review, regeneration: .downloadsAgain, locations: ["Library/pnpm/store", ".local/share/pnpm/store"], action: .removeFolder),
        .init(id: "pkg.yarn", group: .packages, title: String(localized: "Yarn önbelleği"),
              detail: String(localized: "Yarn’ın paket önbelleği."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Caches/Yarn", ".yarn/cache", ".yarn/berry/cache"], action: .removeContents),
        .init(id: "pkg.pip", group: .packages, title: String(localized: "pip ve uv önbelleği"),
              detail: String(localized: "Python paket indirmeleri ve derlenmiş wheel dosyaları."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Caches/pip", ".cache/pip", ".cache/uv", "Library/Caches/uv"], action: .removeContents),
        .init(id: "pkg.cocoapods", group: .packages, title: String(localized: "CocoaPods önbelleği"),
              detail: String(localized: "İndirilen pod’lar."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Caches/CocoaPods"], action: .removeContents),
        .init(id: "pkg.cocoapodsSpecs", group: .packages, title: String(localized: "CocoaPods spec deposu"),
              detail: String(localized: "Pod tanımlarının yerel kopyası; ilk kullanımda yeniden klonlanır ve uzun sürebilir."),
              safety: .review, regeneration: .downloadsAgain, locations: [".cocoapods/repos"], action: .removeContents),
        .init(id: "pkg.gradle", group: .packages, title: String(localized: "Gradle önbelleği"),
              detail: String(localized: "Gradle’ın bağımlılık ve derleme önbellekleri ile indirdiği dağıtımlar."),
              safety: .review, regeneration: .downloadsAgain, locations: [".gradle/caches", ".gradle/wrapper/dists"], action: .removeContents),
        .init(id: "pkg.cargo", group: .packages, title: String(localized: "Cargo kayıt defteri"),
              detail: String(localized: "İndirilen Rust crate’leri ve git bağımlılıkları."),
              safety: .review, regeneration: .downloadsAgain, locations: [".cargo/registry", ".cargo/git"], action: .removeContents),
        .init(id: "pkg.go", group: .packages, title: String(localized: "Go modülleri ve derleme önbelleği"),
              detail: String(localized: "Go’nun indirdiği modüller ve derleme önbelleği."),
              safety: .review, regeneration: .downloadsAgain, locations: ["go/pkg/mod", "Library/Caches/go-build"], action: .removeContents),
        .init(id: "pkg.maven", group: .packages, title: String(localized: "Maven deposu"),
              detail: String(localized: "Yerel Maven deposundaki bağımlılıklar."),
              safety: .review, regeneration: .downloadsAgain, locations: [".m2/repository"], action: .removeContents),
        .init(id: "pkg.bunDeno", group: .packages, title: String(localized: "Bun ve Deno önbelleği"),
              detail: String(localized: "Bun ve Deno’nun paket önbellekleri."),
              safety: .safe, regeneration: .downloadsAgain, locations: [".bun/install/cache", "Library/Caches/deno"], action: .removeContents),
        .init(id: "pkg.browsers", group: .packages, title: String(localized: "Cypress ve Playwright tarayıcıları"),
              detail: String(localized: "Test araçlarının indirdiği tarayıcı sürümleri."),
              safety: .review, regeneration: .downloadsAgain, locations: ["Library/Caches/Cypress", "Library/Caches/ms-playwright"], action: .removeContents),
    ]

    // MARK: Toolchains

    private static let toolchains: [SystemDataProbe] = [
        .init(id: "tool.nvm", group: .toolchains, title: String(localized: "Node sürümleri (nvm)"),
              detail: String(localized: "nvm ile kurduğun Node.js sürümleri."),
              safety: .review, regeneration: .downloadsAgain, locations: [".nvm/versions"], action: .removeContents),
        .init(id: "tool.rustup", group: .toolchains, title: String(localized: "Rust araç zincirleri"),
              detail: String(localized: "rustup ile kurulan araç zincirleri ve hedefler."),
              safety: .review, regeneration: .downloadsAgain, locations: [".rustup/toolchains"], action: .removeContents),
        .init(id: "tool.versionManagers", group: .toolchains, title: String(localized: "Python, Ruby ve Java sürümleri"),
              detail: String(localized: "pyenv, rbenv ve SDKMAN ile kurduğun dil sürümleri."),
              safety: .review, regeneration: .downloadsAgain, locations: [".pyenv/versions", ".rbenv/versions", ".sdkman/candidates"], action: .removeContents),
        .init(id: "tool.conda", group: .toolchains, title: String(localized: "Conda ortamları"),
              detail: String(localized: "Miniconda/Anaconda kurulumu ve paket önbelleği."),
              safety: .review, regeneration: .downloadsAgain, locations: ["miniconda3", "anaconda3", "miniforge3", ".conda/pkgs"], action: .removeFolder),
        .init(id: "tool.editors", group: .toolchains, title: String(localized: "Editör eklentileri"),
              detail: String(localized: "VS Code ve Cursor eklentileri; yeniden indirilebilir."),
              safety: .review, regeneration: .downloadsAgain, locations: [".vscode/extensions", ".cursor/extensions"], action: .removeContents),
        .init(id: "tool.containerVMs", group: .toolchains, title: String(localized: "OrbStack, Colima ve Lima"),
              detail: String(localized: "Konteyner sanal makinelerinin disk görüntüleri; içindeki imajlar ve veriler de gider."),
              safety: .manual, regeneration: .doesNotReturn, locations: [".orbstack", ".colima", ".lima"],
              action: .manual(hint: String(localized: "İlgili aracın kendi arayüzünden veya komutundan (örneğin “orb delete”, “colima delete”) kaldır."))),
    ]

    // MARK: AI

    private static let aiTools: [SystemDataProbe] = [
        .init(id: "ai.huggingface", group: .aiModels, title: String(localized: "Hugging Face modelleri"),
              detail: String(localized: "transformers ve diffusers’ın indirdiği model dosyaları."),
              safety: .review, regeneration: .downloadsAgain, locations: [".cache/huggingface/hub"], action: .removeContents),
        .init(id: "ai.lmstudio", group: .aiModels, title: String(localized: "LM Studio modelleri"),
              detail: String(localized: "LM Studio’nun indirdiği yerel modeller."),
              safety: .review, regeneration: .downloadsAgain, locations: [".lmstudio/models", ".cache/lm-studio/models"], action: .removeContents),
        .init(id: "ai.torch", group: .aiModels, title: String(localized: "PyTorch indirmeleri"),
              detail: String(localized: "torch.hub ve torchvision’ın indirdiği ağırlıklar."),
              safety: .safe, regeneration: .downloadsAgain, locations: [".cache/torch"], action: .removeContents),
        .init(id: "ai.claudeVM", group: .aiModels, title: String(localized: "Claude sanal makine paketleri"),
              detail: String(localized: "Claude masaüstü uygulamasının yerel çalışma ortamı; ihtiyaç olunca yeniden indirilir."),
              safety: .review, regeneration: .downloadsAgain, locations: ["Library/Application Support/Claude/vm_bundles"], action: .removeContents,
              busyBundleIDs: ["com.anthropic.claudefordesktop"]),
        .init(id: "ai.chromeModel", group: .aiModels, title: String(localized: "Chrome cihaz içi model"),
              detail: String(localized: "Chrome’un cihaz içi yapay zekâ modeli; gerekince yeniden indirilir."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"],
              action: .removeContents, busyBundleIDs: ["com.google.Chrome"]),
        .init(id: "ai.codingSessions", group: .aiModels, title: String(localized: "Yapay zekâ kodlama oturum kayıtları"),
              detail: String(localized: "Claude Code, Codex ve benzeri araçların yerel konuşma kayıtları; silinen oturumlar geri gelmez."),
              safety: .review, regeneration: .doesNotReturn, locations: [".claude/projects", ".codex/sessions", ".gemini/tmp"], action: .removeContents),
    ]

    // MARK: Logs

    private static let logs: [SystemDataProbe] = [
        .init(id: "log.user", group: .logs, title: String(localized: "Kullanıcı günlükleri"),
              detail: String(localized: "~/Library/Logs altındaki uygulama günlükleri ve çökme raporları."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Logs"], action: .removeContents),
        .init(id: "log.diagnosticsSystem", group: .logs, title: String(localized: "Sistem tanılama raporları"),
              detail: String(localized: "/Library/Logs altındaki çökme ve tanılama raporları; silmek yönetici izni ister."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["/Library/Logs/DiagnosticReports"], action: .removeContents),
        .init(id: "log.crashReporter", group: .logs, title: String(localized: "Eski sistem günlükleri"),
              detail: String(localized: "ASL ve eski sistem günlük dosyaları."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["/private/var/log/asl"], action: .removeContents),
    ]

    // MARK: Virtual machines

    private static let virtualMachines: [SystemDataProbe] = [
        .init(id: "vm.parallels", group: .virtualMachines, title: String(localized: "Parallels sanal makineleri"),
              detail: String(localized: "Parallels disk görüntüleri; içindeki işletim sistemi ve veriler de gider."),
              safety: .review, regeneration: .doesNotReturn, locations: ["Parallels", "Library/Parallels"],
              action: .manual(hint: String(localized: "Parallels Control Center’dan sanal makineyi sil.")),
              busyBundleIDs: ["com.parallels.desktop.console"]),
        .init(id: "vm.fusion", group: .virtualMachines, title: String(localized: "VMware Fusion sanal makineleri"),
              detail: String(localized: "VMware Fusion disk görüntüleri."),
              safety: .review, regeneration: .doesNotReturn, locations: ["Virtual Machines.localized", "Virtual Machines"],
              action: .manual(hint: String(localized: "VMware Fusion kitaplığından sanal makineyi sil."))),
        .init(id: "vm.virtualbox", group: .virtualMachines, title: String(localized: "VirtualBox sanal makineleri"),
              detail: String(localized: "VirtualBox disk görüntüleri."),
              safety: .review, regeneration: .doesNotReturn, locations: ["VirtualBox VMs"],
              action: .manual(hint: String(localized: "VirtualBox yöneticisinden sanal makineyi sil."))),
        .init(id: "vm.utm", group: .virtualMachines, title: String(localized: "UTM sanal makineleri"),
              detail: String(localized: "UTM disk görüntüleri."),
              safety: .review, regeneration: .doesNotReturn, locations: ["Library/Containers/com.utmapp.UTM/Data/Documents"],
              action: .manual(hint: String(localized: "UTM kitaplığından sanal makineyi sil."))),
        .init(id: "vm.tart", group: .virtualMachines, title: String(localized: "Tart sanal makineleri"),
              detail: String(localized: "Tart ile oluşturulan macOS ve Linux sanal makineleri."),
              safety: .review, regeneration: .doesNotReturn, locations: [".tart/vms", ".tart/cache"],
              action: .manual(hint: String(localized: "“tart delete <ad>” komutuyla sanal makineyi sil."))),
    ]

    // MARK: Android

    private static let android: [SystemDataProbe] = [
        .init(id: "android.avd", group: .android, title: String(localized: "Android emülatör aygıtları"),
              detail: String(localized: "AVD disk görüntüleri; aygıtlar yeniden oluşturulabilir ama verileri gider."),
              safety: .review, regeneration: .doesNotReturn, locations: [".android/avd"], action: .removeContents),
        .init(id: "android.sdkImages", group: .android, title: String(localized: "Android SDK sistem imajları"),
              detail: String(localized: "Emülatör sistem imajları; SDK Manager ile yeniden indirilir."),
              safety: .review, regeneration: .downloadsAgain, locations: ["Library/Android/sdk/system-images"], action: .removeContents),
        .init(id: "android.sdkComponents", group: .android, title: String(localized: "Android SDK bileşenleri"),
              detail: String(localized: "Platformlar, derleme araçları, NDK ve emülatör; SDK Manager ile yeniden indirilir."),
              safety: .review, regeneration: .downloadsAgain,
              locations: ["Library/Android/sdk/platforms", "Library/Android/sdk/build-tools", "Library/Android/sdk/ndk", "Library/Android/sdk/emulator"],
              action: .removeContents),
        .init(id: "android.caches", group: .android, title: String(localized: "Android Studio önbellekleri"),
              detail: String(localized: "Android Studio ve Android araçlarının önbellekleri."),
              safety: .safe, regeneration: .rebuildsLocally, locations: ["Library/Caches/Google/AndroidStudio*", ".android/cache"], action: .removeContents),
    ]

    // MARK: App data

    private static let appData: [SystemDataProbe] = [
        .init(id: "app.slack", group: .appData, title: String(localized: "Slack önbelleği"),
              detail: String(localized: "Slack’in yeniden oluşturduğu önbellek klasörleri."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Application Support/Slack/Cache", "Library/Application Support/Slack/Code Cache", "Library/Application Support/Slack/Service Worker/CacheStorage"],
              action: .removeContents, busyBundleIDs: ["com.tinyspeck.slackmacgap"]),
        .init(id: "app.discord", group: .appData, title: String(localized: "Discord önbelleği"),
              detail: String(localized: "Discord’un yeniden oluşturduğu önbellek klasörleri."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Application Support/discord/Cache", "Library/Application Support/discord/Code Cache", "Library/Application Support/discord/GPUCache"],
              action: .removeContents, busyBundleIDs: ["com.hnc.Discord"]),
        .init(id: "app.spotify", group: .appData, title: String(localized: "Spotify önbelleği"),
              detail: String(localized: "Çevrimdışı olmayan çalma önbelleği; şarkılar yeniden akıtılır."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Caches/com.spotify.client", "Library/Application Support/Spotify/PersistentCache"],
              action: .removeContents, busyBundleIDs: ["com.spotify.client"]),
        .init(id: "app.browsers", group: .appData, title: String(localized: "Tarayıcı önbellekleri"),
              detail: String(localized: "Safari, Chrome, Edge ve Firefox’un sayfa önbellekleri; oturumlar ve geçmiş korunur."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Caches/com.apple.Safari", "Library/Caches/Google/Chrome", "Library/Caches/Microsoft Edge", "Library/Caches/Firefox"],
              action: .removeContents, busyBundleIDs: ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox"]),
        .init(id: "app.adobe", group: .appData, title: String(localized: "Adobe medya önbelleği"),
              detail: String(localized: "Premiere ve After Effects’in medya önbellek dosyaları; projeler açılınca yeniden oluşur."),
              safety: .safe, regeneration: .rebuildsLocally,
              locations: ["Library/Application Support/Adobe/Common/Media Cache Files", "Library/Application Support/Adobe/Common/Media Cache", "Library/Caches/Adobe"],
              action: .removeContents),
        .init(id: "app.zoomTeams", group: .appData, title: String(localized: "Zoom ve Teams önbelleği"),
              detail: String(localized: "Toplantı uygulamalarının önbellekleri."),
              safety: .safe, regeneration: .downloadsAgain,
              locations: ["Library/Caches/us.zoom.xos", "Library/Application Support/Microsoft/Teams/Cache", "Library/Caches/com.microsoft.teams2"],
              action: .removeContents),
        .init(id: "app.games", group: .appData, title: String(localized: "Steam ve Epic oyunları"),
              detail: String(localized: "İndirilen oyunlar; istemciden kaldırmak daha doğrudur."),
              safety: .manual, regeneration: .downloadsAgain,
              locations: ["Library/Application Support/Steam/steamapps", "Library/Application Support/Epic/EpicGamesLauncher"],
              action: .manual(hint: String(localized: "Oyunu Steam veya Epic istemcisinden kaldır."))),
    ]

    // MARK: System

    private static let system: [SystemDataProbe] = [
        .init(id: "sys.installers", group: .system, title: String(localized: "macOS kurulum dosyaları"),
              detail: String(localized: "Yarım kalmış güncellemelerin bıraktığı kurulum verileri."),
              safety: .review, regeneration: .downloadsAgain, locations: ["/macOS Install Data", "/Library/Updates"], action: .removeContents),
        .init(id: "sys.mailDownloads", group: .system, title: String(localized: "Mail indirmeleri"),
              detail: String(localized: "Mail’de açtığın eklerin yerel kopyaları; ekler sunucuda durur."),
              safety: .safe, regeneration: .downloadsAgain, locations: ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
              action: .removeContents, busyBundleIDs: ["com.apple.mail"]),
        .init(id: "sys.libraryCaches", group: .system, title: String(localized: "Sistem önbellekleri"),
              detail: String(localized: "/Library/Caches altındaki paylaşılan önbellekler; silmek yönetici izni ister."),
              safety: .review, regeneration: .rebuildsLocally, locations: ["/Library/Caches"], action: .removeContents),
        .init(id: "sys.commandLineTools", group: .system, title: String(localized: "Komut Satırı Araçları"),
              detail: String(localized: "Xcode kuruluysa gerekmeyebilir; “xcode-select --install” ile geri gelir."),
              safety: .review, regeneration: .downloadsAgain, locations: ["/Library/Developer/CommandLineTools"], action: .removeFolder),
        .init(id: "sys.spotlight", group: .system, title: String(localized: "Spotlight dizini"),
              detail: String(localized: "Spotlight’ın arama dizini; macOS yönetir ve dizin silinirse saatlerce yeniden oluşur."),
              safety: .manual, regeneration: .rebuildsLocally, locations: ["/System/Volumes/Data/.Spotlight-V100", "Library/Metadata"],
              action: .manual(hint: String(localized: "Sorun yoksa dokunma. Gerekirse “sudo mdutil -E /” ile dizini yeniden oluştur."))),
        .init(id: "sys.swap", group: .system, title: String(localized: "Sanal bellek ve uyku imajı"),
              detail: String(localized: "macOS’un yönettiği takas ve uyku dosyaları; elle silinmez."),
              safety: .manual, regeneration: .rebuildsLocally, locations: ["/System/Volumes/VM", "/private/var/vm"],
              action: .manual(hint: String(localized: "macOS ihtiyaca göre büyütüp küçültür; yeniden başlatmak boşaltır."))),
    ]

    // MARK: Trash

    private static let trash: [SystemDataProbe] = [
        .init(id: "trash.user", group: .trash, title: String(localized: "Çöp Kutusu"),
              detail: String(localized: "Çöp’teki öğeler; boşaltılana kadar yer kaplar."),
              safety: .safe, regeneration: .doesNotReturn, locations: [".Trash"], action: .removeContents),
    ]
}
