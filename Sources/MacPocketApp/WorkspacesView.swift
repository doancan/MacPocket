import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

@MainActor
final class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    @Published var store = WorkspaceStore.load(from: .standard) {
        didSet {
            guard store != oldValue else { return }
            store.save(to: .standard)
            registerShortcuts()
        }
    }
    @Published private(set) var restoring: WorkspaceLayout.ID?
    @Published private(set) var message: String?
    var recordingShortcut = false { didSet { registerShortcuts() } }
    private var hotKeys: [WorkspaceLayout.ID: PocketGlobalHotKey] = [:]

    private init() {}

    func start() { registerShortcuts() }

    private func registerShortcuts() {
        for (id, hotKey) in hotKeys where !store.layouts.contains(where: { $0.id == id }) {
            hotKey.unregister()
            hotKeys[id] = nil
        }
        for layout in store.layouts {
            let hotKey = hotKeys[layout.id] ?? PocketGlobalHotKey { [weak self] in
                guard let self, let current = self.store.layouts.first(where: { $0.id == layout.id }) else { return }
                Task { await self.restore(current) }
            }
            hotKeys[layout.id] = hotKey
            if let shortcut = layout.shortcut, !recordingShortcut { hotKey.register(shortcut) } else { hotKey.unregister() }
        }
    }

    /// Captures the ordinary windows of every regular app (MacPocket excluded).
    func capture(named name: String) -> WorkspaceLayout? {
        guard AXIsProcessTrusted() else {
            message = String(localized: "Pencereleri okumak için Erişilebilirlik izni gerekir.")
            return nil
        }
        var windows: [SavedWindow] = []
        let frozen = AppFreezerService.shared.frozen
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            // A paused app can't answer Accessibility requests.
            guard let bundleID = app.bundleIdentifier, !app.isHidden, frozen[app.processIdentifier] == nil else { continue }
            for window in FocusedWindow.windows(of: app.processIdentifier) {
                if let frame = window.frame { windows.append(SavedWindow(bundleID: bundleID, title: window.title, frame: frame)) }
            }
        }
        guard !windows.isEmpty else {
            message = String(localized: "Kaydedilecek açık pencere bulunamadı.")
            return nil
        }
        message = nil
        return WorkspaceLayout(name: name, windows: windows, savedAt: Date())
    }

    func restore(_ layout: WorkspaceLayout) async {
        guard restoring == nil else { return }
        guard AXIsProcessTrusted() else {
            message = String(localized: "Pencereleri taşımak için Erişilebilirlik izni gerekir.")
            return
        }
        restoring = layout.id
        defer { restoring = nil }
        var moved = 0, skipped = 0
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        // Screens in Accessibility coordinates, to check that each saved frame is still reachable.
        let screens = NSScreen.screens.map { WindowLayoutGeometry.flip($0.visibleFrame, primaryHeight: primaryHeight) }
        for bundleID in layout.applications {
            var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            if app == nil, layout.launchMissingApps, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                app = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                // Give the app a few seconds to open its windows.
                for _ in 0..<20 where FocusedWindow.windows(of: app?.processIdentifier ?? 0).isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            guard let app else { continue }
            if AppFreezerService.shared.frozen[app.processIdentifier] != nil { AppFreezerService.shared.thaw(app.processIdentifier) }
            if app.isHidden { app.unhide() }
            let current = FocusedWindow.windows(of: app.processIdentifier)
            let saved = layout.windows.filter { $0.bundleID == bundleID }
            for pair in WorkspaceMatcher.match(saved: saved, currentTitles: current.map(\.title)) {
                guard WorkspaceMatcher.isReachable(pair.saved.frame, screens: screens) else { skipped += 1; continue }
                if current[pair.index].setFrame(pair.saved.frame) { moved += 1 } else { skipped += 1 }
            }
        }
        message = skipped == 0 ? String(localized: "“\(layout.name)” yüklendi: \(moved) pencere yerleşti.")
            : String(localized: "“\(layout.name)” yüklendi: \(moved) pencere yerleşti, \(skipped) pencere atlandı (artık bağlı olmayan ekran veya taşınamayan pencere).")
    }

    func dismissMessage() { message = nil }
}

/// Tools → Masa Düzenleri.
struct WorkspacesView: View {
    @ObservedObject private var service = WorkspaceService.shared
    @State private var newName = ""
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Masa Düzenleri",
                              subtitle: "Açık pencerelerin yerleşimini adıyla kaydet, tek kısayolla geri getir; kapalı uygulamalar da açılır.",
                              icon: "rectangle.3.group")
            if !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Pencereleri okuyup taşımak için Erişilebilirlik izni gerekir.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            if let message = service.message {
                HStack(alignment: .top) {
                    PocketMessage(message, tone: .neutral)
                    Button { service.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        .accessibilityLabel("Mesajı kapat")
                }
            }
            HStack(spacing: PocketSpacing.m) {
                TextField("Düzen adı (ör. Kodlama, Toplantı)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit(save)
                Button { save() } label: { Label("Şu anki yerleşimi kaydet", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.pocketPrimary)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(spacing: PocketSpacing.m) {
                    if service.store.layouts.isEmpty {
                        ContentUnavailableView("Henüz düzen yok", systemImage: "rectangle.3.group",
                                               description: Text("Pencereleri istediğin gibi yerleştir, bir ad ver ve kaydet."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .pocketCard()
                    }
                    ForEach($service.store.layouts) { $layout in
                        WorkspaceRow(layout: $layout, service: service, update: {
                            if let fresh = service.capture(named: layout.name) {
                                layout.windows = fresh.windows
                                layout.savedAt = fresh.savedAt
                            }
                        }, delete: { service.store.layouts.removeAll { $0.id == layout.id } })
                    }
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let layout = service.capture(named: name) else { return }
        service.store.layouts.append(layout)
        newName = ""
    }
}

private struct WorkspaceRow: View {
    @Binding var layout: WorkspaceLayout
    @ObservedObject var service: WorkspaceService
    let update: () -> Void
    let delete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                TextField("Ad", text: $layout.name).textFieldStyle(.plain).font(.title3.weight(.semibold))
                Spacer()
                KeyComboRecorder(combo: $layout.shortcut, allowsClearing: true, recording: { service.recordingShortcut = $0 })
                Button { Task { await service.restore(layout) } } label: {
                    if service.restoring == layout.id { ProgressView().controlSize(.small) } else { Label("Yükle", systemImage: "play.fill") }
                }
                .buttonStyle(.pocketPrimary)
                .disabled(service.restoring != nil)
                Menu {
                    Button("Şu anki yerleşimle güncelle", action: update)
                    Divider()
                    Button("Sil…", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .confirmationDialog("“\(layout.name)” silinsin mi?", isPresented: $confirmDelete) {
                    Button("Sil", role: .destructive, action: delete)
                }
            }
            HStack(spacing: PocketSpacing.s) {
                ForEach(layout.applications.prefix(12), id: \.self) { bundleID in
                    PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 22)
                        .help(bundleID)
                }
                Text("\(layout.windows.count) pencere · \(layout.savedAt.formatted(.dateTime.day().month().hour().minute().locale(pocketLocale)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Kapalı uygulamaları aç", isOn: $layout.launchMissingApps).toggleStyle(.checkbox).font(.callout)
            }
        }
        .pocketCard()
    }
}
