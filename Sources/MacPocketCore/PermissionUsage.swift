import Foundation

public enum CorePermissionFeature: Sendable, Equatable {
    case cleanup, diskAnalysis, leftovers, uninstall, wifi, monitorAlerts
    public var localizedTitle: String {
        switch self {
        case .cleanup: String(localized: "Temizlik")
        case .diskAnalysis: String(localized: "Disk Analizi")
        case .leftovers: String(localized: "Uygulama Kalıntıları")
        case .uninstall: String(localized: "Tam Kaldırma")
        case .wifi: String(localized: "Wi-Fi Analizi")
        case .monitorAlerts: String(localized: "İzleme uyarıları")
        }
    }
}
public struct PermissionUsage: Sendable, Equatable {
    public let activeModules: [PocketModule]
    public let inactiveModules: [PocketModule]
    public let coreFeatures: [CorePermissionFeature]
    public var isRelevant: Bool { !activeModules.isEmpty || !coreFeatures.isEmpty }
    public var activeTitles: [String] { coreFeatures.map(\.localizedTitle) + activeModules.map(\.localizedTitle) }
}
public enum PermissionUsageMap {
    public static func usage(_ permission: OnboardingPermission, availableModules: Set<PocketModule>) -> PermissionUsage {
        let modules: [PocketModule]
        let core: [CorePermissionFeature]
        switch permission {
        case .accessibility:
            modules = [.windowSwitcher, .windowLayout, .dockPreview, .clipboard, .mouseScroll, .mouseButtons, .commandBar, .menuBarOrganizer]
            core = []
        case .screenRecording:
            // The process-tap audio permission is checked by the mixer itself, not
            // CGPreflightScreenCaptureAccess.
            modules = [.screenGrab, .screenshot, .recorder, .windowSwitcher, .dockPreview]
            core = []
        case .fullDiskAccess:
            modules = []
            core = [.cleanup, .diskAnalysis, .leftovers, .uninstall]
        case .inputMonitoring:
            modules = [.bluetoothBattery]
            core = []
        case .location:
            modules = [.displays]
            core = [.wifi]
        case .notifications:
            modules = [.bluetoothBattery]
            core = [.monitorAlerts]
        }
        return .init(activeModules: modules.filter(availableModules.contains), inactiveModules: modules.filter { !availableModules.contains($0) }, coreFeatures: core)
    }
}
