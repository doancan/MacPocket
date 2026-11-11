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

/// The SSH Yöneticisi icon: a dark rounded tile with a three-unit server rack, drawn as vectors in the same tile
/// geometry as `PocketIconTile` so it matches the other sidebar icons at every size.
struct SSHManagerIcon: View {
    let size: CGFloat

    /// Graphite in light appearance; a lighter slate in dark appearance, where graphite would vanish into the sidebar.
    private var base: Color { colorScheme == .dark ? Color(hex: 0x4A5262) : Color(hex: 0x252A33) }
    private static let led = Color(hex: 0x22C55E)
    private static let idleLED = Color(hex: 0xC7C7CC)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius = size * 0.27
        let unitHeight = size * 0.19, unitWidth = size * 0.62, gap = size * 0.065
        ZStack {
            if size >= 40 {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(.white, lineWidth: size * 0.035)
                    .frame(width: size * 0.74, height: size * 0.74)
            }
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { index in
                    unit(index: index, width: unitWidth, height: unitHeight)
                }
            }
        }
        .frame(width: size, height: size)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(base)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                }
        }
        .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(colorScheme == .dark ? 0.30 : 0.18), lineWidth: 0.5) }
        .shadow(color: base.opacity(size > 30 ? 0.35 : 0.2), radius: size > 30 ? 8 : 2, y: size > 30 ? 4 : 1)
        .accessibilityHidden(true)
    }

    private func unit(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let dot = height * 0.34
        return RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
            .fill(.white)
            .frame(width: width, height: height)
            .overlay {
                HStack(spacing: dot * 0.55) {
                    Circle().fill(base).frame(width: dot, height: dot)
                    Circle().fill(base).frame(width: dot, height: dot)
                    Spacer(minLength: 0)
                    Circle().fill(index == 1 ? Self.idleLED : Self.led).frame(width: dot * 1.2, height: dot * 1.2)
                }
                .padding(.horizontal, height * 0.34)
            }
    }
}
