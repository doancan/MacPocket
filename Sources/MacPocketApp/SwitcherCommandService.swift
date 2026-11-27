import AppKit
import Darwin
import MacPocketCore

/// Uses the running switcher's catalog and focus path, so CLI MRU is the same session history.
@MainActor final class SwitcherCommandService {
    private let model: WindowSwitcherModel
    private let show: (Int) -> Bool
    private let hide: () -> Void
    private let visible: () -> Bool
    init(model: WindowSwitcherModel,show: @escaping (Int) -> Bool,hide: @escaping () -> Void,visible: @escaping () -> Bool) {
        self.model = model
        self.show = show
        self.hide = hide
        self.visible = visible
    }
    convenience init(controller: WindowSwitcherHotkeyController) {
        self.init(model: controller.model,show: { [weak controller] in controller?.showFromCommand(profile: $0) ?? false },
                  hide: { [weak controller] in controller?.hideFromCommand() },visible: { [weak controller] in controller?.commandPanelVisible ?? false })
    }

    func execute(_ request: SwitcherCLIRequest) async -> SwitcherCLIResponse {
        func fail(_ code: String,_ message: String) -> SwitcherCLIResponse {
            SwitcherCLIResponse(requestID: request.id,status: "error",message: message,errorCode: code)
        }
        guard request.isValid else { return fail("invalid-command",SwitcherCLIError.invalidCommand.localizedDescription) }
        guard request.isCurrent,!Task.isCancelled else { return fail("expired",SwitcherCLIError.timedOut.localizedDescription) }
        var response = SwitcherCLIResponse(requestID: request.id)
        switch request.command {
        case .status: response.panelVisible = visible()
        case .hide:
            hide()
            response.status = "hidden"
            response.panelVisible = visible()
        case .show(let profile):
            guard show(profile) else { return fail("unavailable",String(localized: "Pencere geçişi açılamadı. Modülün açık olduğunu, profil numarasını ve kısayol kaydının bitmiş olduğunu kontrol et.")) }
            response.status = "opening"
            response.panelVisible = visible()
        case .list, .focus, .focusMRU:
            let report = await model.commandSnapshot()
            guard request.isCurrent,!Task.isCancelled else { return fail("expired",SwitcherCLIError.timedOut.localizedDescription) }
            // The list is a full real-window inventory, independent of the current HUD/table filters.
            let windows = WindowFiltering.apply(report.windows,includeWindowless: false,order: .recent)
            response.accessibility = report.accessibilityGranted
            response.partial = report.partial
            response.otherSpacesVisible = report.otherSpacesVisible
            response.spaceMetadataAvailable = report.spaceMetadataAvailable
            response.spaceMetadataPartial = report.spaceMetadataPartial
            if case .list(let detailed) = request.command {
                response.windows = windows.enumerated().map { SwitcherCLIWindow($0.element,mru: $0.offset+1,detailed: detailed) }
                return response
            }
            guard report.accessibilityGranted else { return fail("permission-required",WindowCatalogError.permissionRequired.localizedDescription) }
            let target: SwitchableWindow?
            switch request.command {
            case .focus(let id): target = windows.first { $0.id == id || $0.windowID.map(String.init) == id }
            case .focusMRU(let index): target = windows.indices.contains(index-1) ? windows[index-1] : nil
            default: target = nil
            }
            guard let target else { return fail("not-found",String(localized: "Pencere bulunamadı. list komutuyla güncel kimliği veya MRU sırasını kontrol et.")) }
            // Cancel any keyboard opening/focus before the explicit CLI destination is raised.
            hide()
            guard request.isCurrent,!Task.isCancelled else { return fail("expired",SwitcherCLIError.timedOut.localizedDescription) }
            guard await model.focus(id: target.id) else { return fail("focus-failed",model.failure ?? WindowCatalogError.focusFailed.localizedDescription) }
            response.status = "focused"
            response.targetID = target.id
        }
        return response
    }
}

/// The bundled executable can act as a client before application state or modules are initialized.
enum SwitcherCLIEntry {
    static func runIfRequested() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "--switcher" else { return }
        do {
            let request = SwitcherCLIRequest(command: try SwitcherCLICommand.parse(Array(arguments.dropFirst())))
            let response = try SwitcherCLITransport.send(request,portName: SwitcherCLITransport.portName(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.doancan.MacPocket"))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(try encoder.encode(response))
            FileHandle.standardOutput.write(Data([10]))
            exit(response.errorCode == nil ? 0 : 2)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8))
            exit(1)
        }
    }
}
