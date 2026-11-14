import AppKit
import MacPocketCore
import Observation
import SwiftUI

/// Live Full Disk Access state for every screen that reads or deletes protected folders. macOS offers no API
/// for it; the probe reads a protected file, and the state is re-read whenever the app returns to the front
/// (the usual moment after flipping the switch in System Settings).
@MainActor
@Observable
final class FullDiskAccessMonitor {
    static let shared = FullDiskAccessMonitor()

    private(set) var granted = FullDiskAccessProbe.granted()
    /// The user was sent to System Settings from here; a relaunch may be needed before macOS applies it.
    private(set) var requested = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FullDiskAccessMonitor.shared.refresh() }
        }
    }

    func refresh() {
        let now = FullDiskAccessProbe.granted()
        if now != granted { granted = now }
        if now { PermissionDragHelper.shared.hide() }
    }

    func requestAccess() {
        requested = true
        NSWorkspace.shared.open(OnboardingPermission.fullDiskAccess.settingsURL())
        PermissionDragHelper.shared.show(for: .fullDiskAccess)
    }
}

/// Shown only while Full Disk Access is missing. `consequence` says what the screen cannot do without it.
struct FullDiskAccessBanner: View {
    let consequence: LocalizedStringKey
    private let monitor = FullDiskAccessMonitor.shared

    var body: some View {
        if !monitor.granted {
            HStack(alignment: .center, spacing: PocketSpacing.m) {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Tam Disk Erişimi kapalı").font(.callout.weight(.semibold))
                    Text(consequence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if monitor.requested {
                        Text("Anahtarı açtıysan macOS’un uygulaması için MacPocket’ı yeniden başlat.")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: PocketSpacing.s)
                if monitor.requested { Button("Yeniden Başlat") { PocketRelaunch.relaunch() } }
                Button(monitor.requested ? "Ayarları Yeniden Aç" : "İzin Ver…") { monitor.requestAccess() }
                    .buttonStyle(.pocketPrimary)
            }
            .pocketCard(padding: PocketSpacing.m)
            .task {
                while !Task.isCancelled && !monitor.granted {
                    monitor.refresh()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
}
