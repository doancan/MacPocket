import SSHConfigKit
import SwiftUI
import MacPocketShared

struct BannerStack: View {
    @Bindable var model: AppModel
    @Binding var showExternalDiff: Bool
    @Environment(\.sshNavigate) private var navigate
    @State private var confirmReload = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let banners = BannerBuilder.banners(for: model.store)
        // One container: the cards render together and materialize in and out as file state changes. Its
        // spacing stays below the 6 pt gap between cards so neighbouring cards do not merge at rest.
        GlassEffectContainer(spacing: 2) {
            VStack(spacing: 0) {
                ForEach(banners) { banner in
                    row(for: banner)
                        .glassEffectTransition(.materialize)
                }
            }
            .padding(.bottom, banners.isEmpty ? 0 : 6)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: banners)
        .confirmationDialog(String(localized: "SSH.banner.external.reload.confirm.title", defaultValue: "Dosya yeniden yüklensin ve değişiklikleriniz atılsın mı?"), isPresented: $confirmReload) {
            Button(String(localized: "SSH.banner.external.reload.confirm.action", defaultValue: "Yeniden Yükle ve At"), role: .destructive) { reload() }
        }
    }

    private func reload() {
        model.store.discardChanges()
        model.resetEditor()
    }

    @ViewBuilder
    private func row(for banner: Banner) -> some View {
        switch banner {
        case .missingFile:
            BannerRow(icon: "doc.badge.plus", tint: .yellow, message: Messages.text(for: ConfigLoadState.missing) ?? "") {
                Button(String(localized: "SSH.banner.missing.create", defaultValue: "Dosya Oluştur")) {
                    do { try model.store.createFile() } catch {
                        AppLog.error(.edit, error)
                        model.errorMessage = Messages.text(for: error)
                    }
                }
                Button(String(localized: "SSH.banner.missing.choose", defaultValue: "Başka Dosya Seç…")) { navigate(.settings) }
            }
        case .notDownloaded:
            BannerRow(icon: "icloud.and.arrow.down", tint: .blue, message: Messages.text(for: ConfigLoadState.notDownloaded) ?? "") {
                Button(String(localized: "SSH.banner.retry", defaultValue: "Yeniden Dene")) { model.store.load() }
            }
        case .notUTF8:
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.notUTF8) ?? "") {
                EmptyView()
            }
        case .unreadable(let detail):
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.unreadable(detail)) ?? "") {
                Button(String(localized: "SSH.banner.missing.choose", defaultValue: "Başka Dosya Seç…")) { navigate(.settings) }
            }
        case .byteOrderMark:
            BannerRow(icon: "exclamationmark.triangle", tint: .orange, message: String(localized: "SSH.banner.bom", defaultValue: "Bu dosya ssh'in okuyamadığı bir bayt sıra işaretiyle (BOM) başlıyor.")) {
                Button(String(localized: "SSH.banner.bom.remove", defaultValue: "BOM'u Kaldır")) {
                    do { try model.store.apply { $0.removeByteOrderMark() } } catch { model.errorMessage = Messages.text(for: error) }
                }
            }
        case .unparsableLines(let first, let count):
            let line = String(first)
            let message = count == 1
                ? String(localized: "SSH.banner.unparsable.one %@", defaultValue: "\(line). satırı ssh okuyamıyor; kaydederken doğrulama reddeder.")
                : String(localized: "SSH.banner.unparsable.many %@ %lld", defaultValue: "\(line). satır dahil \(count) satırı ssh okuyamıyor; kaydederken doğrulama reddeder.")
            BannerRow(icon: "exclamationmark.triangle", tint: .orange, message: message) { EmptyView() }
        case .externalChange:
            BannerRow(icon: "arrow.triangle.2.circlepath", tint: .orange, message: Messages.text(for: ConfigStoreError.conflict)) {
                Button(String(localized: "SSH.banner.external.reload", defaultValue: "Yeniden Yükle")) {
                    if model.store.hasUnsavedChanges || model.hasPendingFormEdits {
                        confirmReload = true
                    } else {
                        reload()
                    }
                }
                Button(String(localized: "SSH.banner.external.showDiff", defaultValue: "Farkı Göster")) { showExternalDiff = true }
            }
        case .notWatching:
            BannerRow(icon: "eye.slash", tint: .secondary, message: String(localized: "SSH.banner.notWatching", defaultValue: "Diğer programların yaptığı değişiklikler algılanmıyor.")) {
                EmptyView()
            }
        }
    }
}

private struct BannerRow<Actions: View>: View {
    let icon: String
    let tint: Color
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            // Buttons keep their natural width; only the message wraps when the window is narrow.
            HStack(spacing: 8) { actions() }.fixedSize()
        }
        // Bordered, not glass: the card is already glass and glass must not sit on glass.
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlass(.regular.tint(tint.opacity(0.15)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}
