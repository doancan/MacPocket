import AppKit
import MacPocketCore
import SwiftUI

/// Click, then press a combination with ⌘, ⌃ or ⌥. Esc cancels; with `allowsClearing`, ⌫ switches it off.
/// `recording` reports start and end so the owner can suspend its global shortcuts meanwhile.
struct KeyComboRecorder: View {
    @Binding var combo: KeyCombo?
    var allowsClearing = false
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
                        Text(verbatim: combo.displayName).monospaced()
                    } else {
                        Text("Kapalı").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 96)
            }
            .help(allowsClearing ? "Yeni kısayolu kaydetmek için tıkla; kapatmak için kayıt sırasında ⌫" : "Yeni kısayolu kaydetmek için tıkla")
            if rejected {
                Text("⌘, ⌃ veya ⌥ içermeli").font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
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
        guard candidate.isValidGlobalShortcut else { rejected = true; return }
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
