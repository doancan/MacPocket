import MacPocketSSH
import SwiftUI
import AppKit

struct SSHManagerView: View {
    @State private var runtime = SSHRuntime.shared

    var body: some View {
        GeometryReader { bounds in
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.l) {
                SSHManagerIcon(size: 48)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("SSH Yöneticisi")
                        .font(.system(.title, design: .default, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Sunucular, anahtarlar ve SSH yapılandırması.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { runtime.showQuickConnect() } label: {
                    Label("Hızlı Bağlan", systemImage: "bolt.fill")
                }
                .help("SSH sunucularını ara ve bağlan")
            }
            GlassTabBar(tabs: SSHSection.allCases.map {
                GlassTab(id: $0, title: $0.localizedTitle, symbol: $0.icon)
            }, selection: $runtime.section)
            .accessibilityLabel("SSH Yöneticisi bölümü")

            SSHWorkspaceView(runtime: runtime)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PocketRadius.large))
        }
        .padding(PocketSpacing.page)
        .frame(width: bounds.size.width, height: bounds.size.height, alignment: .topLeading)
        }
    }
}

/// The original SSHConfigManager app icon, shipped with MacPocket.
struct SSHManagerIcon: View {
    let size: CGFloat

    private static let original: NSImage? = Bundle.main.url(forResource: "SSHManagerIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let original = Self.original {
                Image(nsImage: original)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
