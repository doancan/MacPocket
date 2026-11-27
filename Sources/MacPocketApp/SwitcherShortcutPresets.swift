import MacPocketCore
import SwiftUI

/// Native menu provides system-reserved chords which cannot reliably reach the key recorder.
struct SwitcherShortcutPresets: View {
    let shortcut: SwitcherShortcut
    let update: (SwitcherShortcut) -> Void
    var body: some View {
        Menu {
            ForEach([SwitcherModifiers.option,.command],id: \.rawValue) { modifiers in
                Button {
                    update(shortcut.replacingOpeningChord(keyCode: SwitcherKeys.tab,modifiers: modifiers))
                } label: {
                    Text(SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: modifiers).displayName)
                }
            }
        } label: {
            Text("Hazır kısayollar").frame(minHeight: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Hazır kısayollar")
        .accessibilityLabel("Hazır kısayollar")
    }
}
