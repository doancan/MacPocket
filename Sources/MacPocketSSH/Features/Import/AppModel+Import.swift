import Foundation
import SSHConfigKit

extension AppModel {
    private var importer: SSHImporter { SSHImporter(home: settings.homeDirectory, destination: sshDirectory) }

    /// Reads `source` (a folder or a config file) off the main actor and shows what importing it would do.
    func beginImport(from source: URL) async {
        let importer = importer
        let document = store.document
        let existing = Set(store.includedHosts.flatMap(\.entry.patterns))
        // The folder may live in iCloud Drive; reading it must not freeze the window.
        let plan = await Task.detached(priority: .userInitiated) {
            importer.plan(source: source, into: document, existingAliases: existing)
        }.value
        importPlan = plan
    }

    /// Copies the keys, then adds the hosts to the open configuration as unsaved changes: the usual save
    /// sheet shows the diff and takes the backup.
    func confirmImport() async {
        guard let plan = importPlan else { return }
        let importer = importer
        do {
            _ = try await Task.detached(priority: .userInitiated) { try importer.copyKeys(of: plan) }.value
            if !plan.hosts.isEmpty {
                try store.apply { try SSHImporter.addHosts(of: plan, to: &$0) }
            }
            importPlan = nil
            resetEditor()
            await keys.refresh()
        } catch {
            AppLog.error(.edit, error)
            errorMessage = Messages.text(for: error)
        }
    }
}
