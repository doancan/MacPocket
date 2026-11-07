import AppKit
import MacPocketCore
import SwiftUI

struct SwitcherNavigationSettings: View {
    let bindings: [SwitcherActionBinding]
    @AppStorage private var arrows: Bool
    @AppStorage private var vim: Bool
    init(bindings: [SwitcherActionBinding], defaults: UserDefaults = .standard) {
        self.bindings = bindings
        _arrows = AppStorage(wrappedValue: true, SwitcherNavigationOptions.arrowsKey, store: defaults)
        _vim = AppStorage(wrappedValue: false, SwitcherNavigationOptions.vimKey, store: defaults)
    }
    private var overrides: [SwitcherActionBinding] {
        var characters: [UInt16: String] = [:], shifted: [UInt16: String] = [:]
        for code in Set(bindings.compactMap(\.keyCode)) {
            if let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),virtualKey: code,keyDown: true) {
                characters[code] = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
                event.flags = .maskShift
                shifted[code] = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
            }
        }
        return SwitcherNavigationOptions(arrows: arrows,vim: vim).overriddenBindings(bindings,characters: characters,shiftedCharacters: shifted)
    }
    var body: some View {
        Toggle("Ok tuşlarıyla gezin", isOn: $arrows)
        Toggle("Vim tuşlarıyla gezin (h/j/k/l)", isOn: $vim)
        Text("h/l önceki/sonraki pencereyi, j/k alt/üst sırayı seçer. Vim açıkken / aramayı başlatır; aramada h/j/k/l normal metindir. Tab/Shift+Tab her zaman kullanılabilir. Değişiklikler sonraki panel açılışında uygulanır.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let conflicts = overrides
        if !conflicts.isEmpty {
            let list = conflicts.map { "\($0.displayName): \($0.action.localizedTitle)" }.joined(separator: ", ")
            Label(String(localized: "Özel eylemler gezinmeden önce uygulanır: \(list)"), systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
