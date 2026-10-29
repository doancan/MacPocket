import Combine
import Foundation
import ServiceManagement

public enum LoginItemStatus: String, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown

    public var isRegistered: Bool { self == .enabled || self == .requiresApproval }
}

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() async throws
}

/// macOS remains the source of truth, including changes made in System Settings.
@MainActor
public final class LoginItemController: ObservableObject {
    @Published public private(set) var status: LoginItemStatus
    @Published public private(set) var isUpdating = false
    @Published public private(set) var error: String?
    private let service: any LoginItemServicing

    public convenience init() { self.init(service: MainAppLoginItemService()) }

    init(service: any LoginItemServicing) {
        self.service = service
        status = service.status
    }

    public func refresh() { status = service.status }

    public func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        refresh()
        error = nil
        guard enabled != status.isRegistered else { return }
        isUpdating = true
        defer {
            refresh()
            isUpdating = false
        }
        do {
            if enabled { try service.register() }
            else { try await service.unregister() }
        } catch { self.error = error.localizedDescription }
    }

    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
private final class MainAppLoginItemService: LoginItemServicing {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}
