import AppKit
import MacPocketCore
import SwiftUI

struct PocketMenuBarView: View {
    @ObservedObject var model: PocketModel
    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.dark

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent").font(.title2)
                    .foregroundStyle(PocketTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPocket").font(.headline)
                    Text(model.system?.hardwareModel ?? "Mac").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.paused ? "Duraklatıldı" : "Canlı")
                    .font(.caption).foregroundStyle(model.paused ? Color.orange : PocketTheme.disk)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                metric("CPU", value: model.cpuLabel, icon: "cpu")
                metric("Fiziksel RAM", value: model.system.map { pocketBytes($0.physicalMemoryBytes) } ?? "—", icon: "memorychip")
                metric("Boş disk alanı", value: model.system?.volumes.first.map { pocketBytes(UInt64(max(0, $0.availableBytes))) } ?? "—", icon: "internaldrive")
                if let power = model.system?.power, power.batteryPresent {
                    metric("Pil", value: power.chargePercent.map { String(format: "%.0f%%", $0) } ?? "—", icon: "battery.100percent")
                }
            }.font(.callout).monospacedDigit()
            if let date = model.lastUpdate {
                Text("Son ölçüm: \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            if model.awakeSession?.active == true {
                Label("Mac uyanık tutuluyor", systemImage: "cup.and.saucer.fill").font(.callout)
                Button("Uyanık Tutmayı Durdur") { Task { await model.stopAwake() } }
            } else {
                Button { Task { await model.startAwake() } } label: {
                    Label("30 Dakika Uyanık Tut", systemImage: "cup.and.saucer")
                }
            }
            HStack {
                Button { model.paused.toggle() } label: {
                    Label(model.paused ? "Sürdür" : "Duraklat", systemImage: model.paused ? "play" : "pause")
                }
                Button { Task { await model.refresh() } } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
            }
            if let error = model.awakeError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button { model.openMainWindow?() } label: {
                Label("MacPocket’ı Aç", systemImage: "macwindow")
            }.keyboardShortcut("0", modifiers: .command)
            HStack {
                Button { model.openSettingsWindow?() } label: { Label("Ayarlar…", systemImage: "gearshape") }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(18).frame(width: 330)
        .buttonStyle(.bordered).controlSize(.regular)
        .preferredColorScheme(appearance.colorScheme)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        GridRow {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
