import MacPocketSSH
import SwiftUI
import AppKit

struct SSHManagerView: View {
    @State private var runtime = SSHRuntime.shared

    var body: some View {
        GeometryReader { bounds in
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "SSH Yöneticisi", subtitle: "Sunucular, anahtarlar ve SSH yapılandırması.",
                              icon: PocketPage.ssh.icon) {
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
