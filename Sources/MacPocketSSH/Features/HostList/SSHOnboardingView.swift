import SwiftUI
import MacPocketShared

/// Shown instead of the empty-selection placeholder when the config has no hosts at all.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.sshNavigate) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "SSH.onboarding.title", defaultValue: "İlk sunucunu ekleyelim")).font(.title2.bold())
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down").frame(width: 28, height: 28).accessibilityHidden(true)
                ImportButton(model: model, title: String(localized: "SSH.onboarding.import", defaultValue: "Başka bir Mac’ten içe aktar…"))
                    .buttonStyle(.adaptiveGlass)
            }
            step(1, title: String(localized: "SSH.onboarding.addHost", defaultValue: "İlk host'u ekle")) {
                model.addHost()
            }
            step(2, title: String(localized: "SSH.onboarding.createKey", defaultValue: "Anahtar oluştur")) {
                model.keys.pendingNewKey = true
                navigate(.keys)
            }
            step(3, title: String(localized: "SSH.onboarding.uploadKey", defaultValue: "Anahtarı sunucuya yükle")) { navigate(.keys) }
        }
        .padding(32)
        // Content layer: a standard material card. Liquid Glass stays on the step buttons only, so glass
        // never sits on glass (Apple HIG, Materials).
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: String(number))
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.fill.secondary, in: .circle)
                .accessibilityHidden(true)
            Button(title, action: action)
                .buttonStyle(.adaptiveGlass)
        }
    }
}
