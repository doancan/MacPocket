import AppKit
import MacPocketCore
import SwiftUI

@MainActor
enum KeyComboPresentation {
    static func displayName(_ combo: KeyCombo) -> String {
        let key: String
        if combo.keyCode == 49 { key = String(localized: "Boşluk") }
        else if combo.keyCode <= 50, ![36, 48].contains(combo.keyCode),
                let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: combo.keyCode, keyDown: true),
                let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !characters.isEmpty {
            key = characters.uppercased()
        } else { key = SwitcherKeys.name(for: combo.keyCode) }
        return (combo.modifiers.contains(.control) ? "⌃" : "") + (combo.modifiers.contains(.option) ? "⌥" : "")
            + (combo.modifiers.contains(.shift) ? "⇧" : "") + (combo.modifiers.contains(.command) ? "⌘" : "") + key
    }
}

/// Click, then press a combination with ⌘, ⌃ or ⌥. Esc cancels; with `allowsClearing`, ⌫ switches it off.
/// `recording` reports start and end so the owner can suspend its global shortcuts meanwhile.
struct KeyComboRecorder: View {
    private static let recordingBegan = Notification.Name("MacPocket.keyComboRecordingBegan")
    @State private var recordingID = UUID()
    @Binding var combo: KeyCombo?
    var allowsClearing = false
    /// false for macro steps, which may press plain keys such as ↩ or ⇥.
    var requiresModifier = true
    var recording: (Bool) -> Void = { _ in }
    @State private var monitor: Any?
    @State private var isRecording = false
    @State private var rejected = false

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Group {
                    if isRecording {
                        Text("Kısayola bas…")
                    } else if let combo {
                        Text(verbatim: KeyComboPresentation.displayName(combo))
                    } else {
                        Text("Kapalı").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 96)
            }
            .help(allowsClearing ? "Yeni kısayolu kaydetmek için tıkla; kapatmak için kayıt sırasında ⌫" : "Yeni kısayolu kaydetmek için tıkla")
            if rejected {
                Text(requiresModifier ? "⌘, ⌃ veya ⌥ içermeli" : "Bu tuş desteklenmiyor").font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: Self.recordingBegan)) { notification in
            if notification.object as? UUID != recordingID { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        NotificationCenter.default.post(name: Self.recordingBegan, object: recordingID)
        rejected = false
        isRecording = true
        recording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    /// Every key press is consumed while recording.
    private func record(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if allowsClearing, event.keyCode == 51, flags.isEmpty {
            combo = nil
            stop()
            return
        }
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        guard requiresModifier ? candidate.isValidGlobalShortcut : SwitcherKeys.isSupported(candidate.keyCode) else { rejected = true; return }
        combo = candidate
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            recording(false)
        }
    }
}
