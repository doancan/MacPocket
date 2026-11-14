import MacPocketCore
import SwiftUI

/// One place to choose between deleting for good and the Trash; every cleanup surface shares the choice.
struct RemovalModePicker: View {
    @AppStorage(RemovalModePreference.storageKey) private var mode: RemovalMode = .deletePermanently

    var body: some View {
        Picker("Silme biçimi", selection: $mode) {
            ForEach(RemovalMode.allCases) { Text($0.localizedTitle).tag($0) }
        }
        .pickerStyle(.menu).fixedSize()
        .help("Kalıcı silme alanı hemen geri verir ve geri alınamaz. Çöp’e taşımak alanı Çöp boşaltılana kadar tutar.")
    }
}

extension RemovalMode {
    /// Label of the button that performs the removal.
    var actionTitle: String {
        self == .deletePermanently ? String(localized: "Kalıcı Sil…") : String(localized: "Çöp’e Taşı…")
    }

    func completed(_ count: Int) -> String {
        self == .deletePermanently ? String(localized: "\(count) öğe kalıcı olarak silindi.") : String(localized: "\(count) öğe Çöp’e taşındı.")
    }

    func inProgress(_ count: Int) -> String {
        self == .deletePermanently ? String(localized: "\(count) öğe kalıcı olarak siliniyor…") : String(localized: "\(count) öğe Çöp’e taşınıyor…")
    }
}
