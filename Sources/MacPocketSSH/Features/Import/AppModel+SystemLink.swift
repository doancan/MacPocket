import Foundation
import SSHConfigKit

extension AppModel {
    private var systemLinker: SystemLinker { SystemLinker(home: settings.homeDirectory, backups: backupManager) }

    /// Works out, without writing, what the system's ssh would need to see the files this app edits.
    func beginSystemLink() {
        let linker = systemLinker
        let config = store.fileURL
        let known = settings.knownHostsURL
        Task {
            let plan = await Task.detached(priority: .userInitiated) { linker.plan(config: config, knownHosts: known) }.value
            systemLinkPlan = plan
        }
    }

    func confirmSystemLink() async {
        guard let plan = systemLinkPlan else { return }
        let linker = systemLinker
        do {
            try await Task.detached(priority: .userInitiated) { try linker.apply(plan) }.value
            systemLinkPlan = nil
        } catch {
            AppLog.error(.save, error)
            errorMessage = Messages.text(for: error)
        }
    }
}
