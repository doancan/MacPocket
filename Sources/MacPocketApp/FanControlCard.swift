import MacPocketCore
import SwiftUI

/// Güç Merkezi → Fanlar. Shows controls only when the helper is installed and answering; otherwise one
/// honest line about why not.
struct FanControlCard: View {
    @ObservedObject private var service = FanControlService.shared

    private enum Mode: String, CaseIterable, Identifiable {
        case system, fixed, temperature
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .system: "Sistem"
            case .fixed: "Sabit"
            case .temperature: "Sıcaklığa göre"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Fanlar", icon: "fan") {
                if service.availability == .ready, service.profile != .system { Text("Manuel") }
            }
            content
            if let message = service.message { PocketMessage(message, tone: .warning) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
        .task { service.refreshAvailability() }
        .onAppear { service.viewAppeared() }
        .onDisappear { service.viewDisappeared() }
    }

    @ViewBuilder
    private var content: some View {
        switch service.availability {
        case .notInstalled:
            helperPrompt("Fan hızını değiştirmek için MacPocket’in yönetici yetkili bir yardımcıya ihtiyacı var.",
                         button: "Yardımcıyı etkinleştir") { service.installHelper() }
        case .needsApproval:
            helperPrompt("Yardımcı kaydedildi; Sistem Ayarları › Genel › Oturum Açma Öğeleri’nde MacPocket’e izin ver.",
                         button: "Sistem Ayarları’nı aç") { service.openApproval() }
        case let .unavailable(reason):
            Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .ready:
            if service.fans.isEmpty {
                Text("Bu Mac’te denetlenebilir fan yok.").font(.callout).foregroundStyle(.secondary)
            } else {
                controls
            }
        }
    }

    private func helperPrompt(_ text: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PocketSpacing.m)
            Button(button, action: action).buttonStyle(.pocketPrimary)
        }
    }

    private var mode: Binding<Mode> {
        Binding {
            switch service.profile {
            case .system: .system
            case .fixed: .fixed
            case .curve: .temperature
            }
        } set: { mode in
            switch mode {
            case .system: service.profile = .system
            case .fixed: service.profile = .fixed(percent: fixedPercent)
            case .temperature: service.profile = FanControlService.temperatureCurve
            }
        }
    }

    private var fixedPercent: Double {
        if case let .fixed(percent) = service.profile { return percent }
        return 50
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            ForEach(service.fans) { fan in
                HStack {
                    Text("Fan \(fan.id + 1)").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fan.rpm.rounded())) rpm").monospacedDigit().fontWeight(.semibold)
                    Text("(\(Int(fan.range.lowerBound))–\(Int(fan.range.upperBound)))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Picker("Fan modu", selection: mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if case .fixed = service.profile {
                HStack {
                    Slider(value: Binding(get: { fixedPercent }, set: { service.profile = .fixed(percent: $0.rounded()) }), in: 0...100, step: 5) {
                        Text("Fan hızı")
                    }
                    Text(verbatim: "\(Int(fixedPercent))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: LocalizedStringKey {
        switch service.profile {
        case .system: "Fanları macOS yönetiyor."
        case .fixed: "Fanlar seçili oranda sabit; MacPocket kapanırsa ya da Mac çok ısınırsa sistem denetimine döner."
        case .curve: "Hız sıcaklığa göre ayarlanır; MacPocket kapanırsa ya da Mac çok ısınırsa sistem denetimine döner."
        }
    }
}
