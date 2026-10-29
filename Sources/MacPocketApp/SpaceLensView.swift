import AppKit
import MacPocketCore
import SwiftUI

extension SpaceLensKind {
    var color: Color {
        switch self {
        case .folder: Color(hex: 0x0A84FF)
        case .package: Color(hex: 0x7B5CFF)
        case .image: Color(hex: 0xFFB800)
        case .video: Color(hex: 0xFF375F)
        case .audio: Color(hex: 0xFF6FB5)
        case .archive: Color(hex: 0xA2845E)
        case .document: Color(hex: 0x30B0C7)
        case .code: Color(hex: 0x32B76A)
        case .diskImage: Color(hex: 0x5E5CE6)
        case .other: Color(hex: 0x8E8E93)
        case .remainder: Color(light: 0xC9CCD3, dark: 0x4A4D55)
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .package: "shippingbox.fill"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .archive: "doc.zipper"
        case .document: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .diskImage: "externaldrive"
        case .other: "doc"
        case .remainder: "ellipsis"
        }
    }
}

/// Folder colors rotate through cool hues so neighbouring folders stay distinguishable.
private let folderPalette: [Color] = [0x0A84FF, 0x30B0C7, 0x5E5CE6, 0x22A55B, 0x00A6C8, 0x6C8CFF, 0x3D9BE9, 0x34C1A6]
    .map { Color(hex: $0) }

private func lensColor(_ node: SpaceLensNode, index: Int) -> Color {
    node.kind == .folder ? folderPalette[index % folderPalette.count] : node.kind.color
}

struct SpaceLensView: View {
    @ObservedObject var model: SpaceLensModel
    @State private var hovered: String?
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            toolbar
            if let failure = model.failure { PocketMessage(failure, tone: model.tree == nil ? .critical : .warning) }
            if let result = model.resultMessage { PocketMessage(result, tone: .success) }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Seçilen öğeler Çöp’e taşınsın mı?", isPresented: $confirmTrash) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp’e Taşı", role: .destructive) { model.trashSelection() }
        } message: {
            Text("\(model.selectedNodes.count) öğe · \(pocketBytes(model.selectedBytes)). Finder’daki Çöp’ten geri alabilirsin; alan Çöp boşaltılınca açılır.")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: PocketSpacing.s) {
            Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                .disabled(model.breadcrumb.count < 2 || model.busy)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Üst klasöre dön (⌘↑)")
                .accessibilityLabel("Üst klasör")
            breadcrumb
            Spacer(minLength: PocketSpacing.s)
            Button("Klasör Seç…") { model.chooseFolder() }
                .disabled(model.busy)
                .help("Haritalanacak klasörü seç")
            if model.scanning {
                Button("İptal Et", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(model.tree == nil ? ("Tara" as LocalizedStringKey) : "Yeniden Tara") { model.scan() }
                    .buttonStyle(.pocketPrimary)
                    .disabled(model.working)
                    .help("\((model.rootURL.path as NSString).abbreviatingWithTildeInPath) klasörünü tara")
            }
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PocketSpacing.xxs) {
                let trail = model.breadcrumb
                if trail.isEmpty {
                    Label((model.rootURL.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button {
                        model.goTo(node.path)
                    } label: {
                        Text(index == 0 ? (node.path as NSString).abbreviatingWithTildeInPath : node.name)
                            .fontWeight(index == trail.count - 1 ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                    .disabled(model.busy)
                }
            }
            .font(.callout)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.scanning, model.expandingPath == nil || model.tree == nil {
            scanningState
        } else if let current = model.current {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    summary(current)
                    treemap(current)
                }
                SpaceLensList(model: model, node: current, hovered: $hovered)
                    .frame(width: 340)
            }
            footer
        } else {
            ContentUnavailableView {
                Label("Space Lens", systemImage: "square.grid.3x3.square")
            } description: {
                Text("Klasördeki her öğe kapladığı alanla orantılı bir kutu olarak gösterilir. Bir klasöre tıklayınca içine girersin.")
            } actions: {
                Button("Ev Klasörünü Tara") { model.scan(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) }
                    .buttonStyle(.pocketPrimary)
                Button("Klasör Seç…") { model.chooseFolder() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var scanningState: some View {
        VStack(spacing: PocketSpacing.l) {
            PocketScanRing(tint: PocketPage.storage.tint, symbol: "square.grid.3x3.square", active: true)
            Text("\((model.rootURL.path as NSString).abbreviatingWithTildeInPath) haritalanıyor")
                .font(.title3.weight(.semibold))
            Text(pocketScanProgressText(model.progress))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Text("Büyük klasörler bir dakikayı bulabilir. İstediğin an iptal edebilirsin.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ node: SpaceLensNode) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Text(pocketBytes(node.allocatedBytes)).font(.title2.weight(.bold)).monospacedDigit()
            Text("\(node.fileCount) dosya").foregroundStyle(.secondary).monospacedDigit()
            if model.working {
                ProgressView().controlSize(.small)
                Text("Çöp’e taşınıyor…").foregroundStyle(.secondary)
            }
            if model.scanning, let path = model.expandingPath {
                ProgressView().controlSize(.small)
                Text("\((path as NSString).lastPathComponent) yükleniyor · \(pocketScanProgressText(model.progress))")
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            if !node.complete {
                PocketStatusBadge(text: "Kısmi sonuç", systemImage: PocketTone.warning.symbol, tone: .warning)
                    .help(partialHelp(node))
            }
            Spacer(minLength: 0)
            if let date = model.scannedAt {
                Text(date.formatted(.relative(presentation: .named).locale(pocketLocale)))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .help(Text("Tarama zamanı: \(date.formatted(date: .abbreviated, time: .standard))"))
            }
        }
        .font(.callout)
    }

    private func partialHelp(_ node: SpaceLensNode) -> String {
        var parts: [String] = []
        if node.inaccessibleCount > 0 { parts.append(String(localized: "\(node.inaccessibleCount) öğeye erişilemedi (izin gerekebilir).")) }
        if model.limitReached { parts.append(String(localized: "Süre veya öğe sınırına ulaşıldı; bazı klasörler eksik ölçüldü.")) }
        if parts.isEmpty { parts.append(String(localized: "Bazı alt klasörler tam ölçülemedi.")) }
        return parts.joined(separator: "\n")
    }

    private func treemap(_ node: SpaceLensNode) -> some View {
        SpaceLensTreemap(node: node, hovered: $hovered, selection: model.selection) { child in
            if child.kind == .folder { model.open(child) } else { model.toggle(child) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 320)
        .disabled(model.busy)
    }

    private var footer: some View {
        HStack(spacing: PocketSpacing.s) {
            legend
            Spacer(minLength: PocketSpacing.s)
            if !model.selection.isEmpty {
                Text("\(model.selectedNodes.count) seçili · \(pocketBytes(model.selectedBytes))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button("Seçimi Temizle") { model.selection = [] }.buttonStyle(.borderless)
            }
            Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting(model.selectedNodes.map(\.url)) }
                .disabled(model.selectedNodes.isEmpty)
            Button("Çöp’e Taşı…", role: .destructive) { confirmTrash = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedNodes.isEmpty || model.busy)
                .help("Seçili öğeleri Çöp’e taşı (⌘⌫)")
        }
    }

    private var legend: some View {
        HStack(spacing: PocketSpacing.m) {
            ForEach([SpaceLensKind.folder, .package, .image, .video, .archive, .document, .other], id: \.self) { kind in
                HStack(spacing: PocketSpacing.xs) {
                    RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 9, height: 9)
                    Text(kind.title)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Treemap

private struct SpaceLensTreemap: View {
    let node: SpaceLensNode
    @Binding var hovered: String?
    let selection: Set<String>
    let activate: (SpaceLensNode) -> Void
    @State private var pointer: CGPoint?

    private struct Tile {
        let node: SpaceLensNode
        let rect: CGRect
        let color: Color
        let nested: [(rect: CGRect, color: Color)]
    }

    var body: some View {
        GeometryReader { proxy in
            let tiles = layout(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for tile in tiles { draw(tile, in: &context) }
                }
                if let hoveredTile = tiles.first(where: { $0.node.id == hovered }), let pointer {
                    tooltip(hoveredTile.node)
                        .position(tooltipPosition(pointer, in: proxy.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    pointer = location
                    let id = tiles.first { $0.rect.contains(location) }?.node.id
                    if hovered != id { hovered = id }
                case .ended:
                    pointer = nil
                    hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                if let tile = tiles.first(where: { $0.rect.contains(location) }), tile.node.kind != .remainder { activate(tile.node) }
            }
            .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Alan haritası")
            .accessibilityValue(tiles.prefix(5).map { "\($0.node.name) \(pocketBytes($0.node.allocatedBytes))" }.joined(separator: ", "))
        }
    }

    private func layout(in bounds: CGRect) -> [Tile] {
        let children = (node.children ?? []).filter { $0.allocatedBytes > 0 }
        guard !children.isEmpty else { return [] }
        let rects = Treemap.layout(children.map { Double($0.allocatedBytes) }, in: bounds.insetBy(dx: 2, dy: 2))
        var folderIndex = 0
        return zip(children, rects).compactMap { child, rect in
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            let color: Color
            if child.kind == .folder { color = lensColor(child, index: folderIndex); folderIndex += 1 } else { color = child.kind.color }
            // A glimpse of the next level inside large folders.
            var nested: [(CGRect, Color)] = []
            if child.kind == .folder, rect.width > 90, rect.height > 70, let grandchildren = child.children {
                let inner = rect.insetBy(dx: 5, dy: 5)
                let area = CGRect(x: inner.minX, y: inner.minY + 20, width: inner.width, height: max(0, inner.height - 20))
                let visible = grandchildren.filter { $0.allocatedBytes > 0 }.prefix(60)
                let innerRects = Treemap.layout(visible.map { Double($0.allocatedBytes) }, in: area)
                nested = zip(visible, innerRects).filter { $1.width >= 3 && $1.height >= 3 }.map { grandchild, innerRect in
                    (innerRect, grandchild.kind == .folder ? Color.white : grandchild.kind.color)
                }
            }
            return Tile(node: child, rect: rect, color: color, nested: nested)
        }
    }

    private func draw(_ tile: Tile, in context: inout GraphicsContext) {
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        let isHovered = hovered == tile.node.id
        let isSelected = selection.contains(tile.node.id)
        let radius = min(6, min(rect.width, rect.height) / 4)
        let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        context.fill(shape, with: .linearGradient(Gradient(colors: [tile.color.opacity(isHovered ? 1 : 0.92), tile.color.opacity(isHovered ? 0.88 : 0.74)]),
                                                  startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                  endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
        for nested in tile.nested {
            let inner = nested.rect.insetBy(dx: 0.75, dy: 0.75)
            guard inner.width > 0, inner.height > 0 else { continue }
            context.fill(Path(roundedRect: inner, cornerRadius: min(3, min(inner.width, inner.height) / 4)),
                         with: .color(nested.color.opacity(nested.color == .white ? 0.18 : 0.55)))
        }
        if isSelected {
            context.stroke(shape, with: .color(.white), lineWidth: 3)
            context.stroke(Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: max(0, radius - 2)),
                           with: .color(.black.opacity(0.35)), lineWidth: 1)
        } else if isHovered {
            context.stroke(shape, with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
        guard rect.width > 54, rect.height > 22 else { return }
        // Tiles with nested children have no room below the name, so their size rides on the same line.
        let label = tile.nested.isEmpty
            ? Text(tile.node.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            : Text("\(Text(tile.node.name).font(.system(size: 11, weight: .semibold)))  \(Text(pocketBytes(tile.node.allocatedBytes)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85)))").foregroundStyle(.white)
        let size = Text(pocketBytes(tile.node.allocatedBytes)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        var clipped = context
        clipped.clip(to: Path(rect.insetBy(dx: 5, dy: 3)))
        clipped.draw(label, at: CGPoint(x: rect.minX + 6, y: rect.minY + 4), anchor: .topLeading)
        if rect.height > 40, tile.nested.isEmpty {
            clipped.draw(size, at: CGPoint(x: rect.minX + 6, y: rect.minY + 19), anchor: .topLeading)
        }
    }

    private func tooltip(_ node: SpaceLensNode) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
            HStack(spacing: PocketSpacing.xs) {
                Image(systemName: node.kind.symbol).foregroundStyle(node.kind == .folder ? PocketTheme.accent : node.kind.color)
                Text(node.name).font(.callout.weight(.semibold)).lineLimit(1)
            }
            (node.fileCount > 1 ? Text("\(pocketBytes(node.allocatedBytes)) · \(node.kind.title) · \(node.fileCount) dosya") : Text(verbatim: "\(pocketBytes(node.allocatedBytes)) · \(node.kind.title)"))
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            if node.kind == .folder {
                (node.needsExpansion ? Text("Tıkla: içini tara ve aç") : Text("Tıkla: içine gir")).font(.caption2).foregroundStyle(.tertiary)
            } else if node.kind != .remainder {
                Text("Tıkla: seç").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PocketSpacing.s).padding(.vertical, PocketSpacing.xs + 2)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PocketRadius.small + 2, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .fixedSize()
    }

    private func tooltipPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let width: CGFloat = 220, height: CGFloat = 64
        var x = point.x + 16 + width / 2
        var y = point.y + 18 + height / 2
        if x + width / 2 > size.width { x = point.x - 16 - width / 2 }
        if y + height / 2 > size.height { y = point.y - 18 - height / 2 }
        return CGPoint(x: max(width / 2, x), y: max(height / 2, y))
    }
}

// MARK: - Children list

private struct SpaceLensList: View {
    @ObservedObject var model: SpaceLensModel
    let node: SpaceLensNode
    @Binding var hovered: String?

    var body: some View {
        let children = node.children ?? []
        let total = Double(max(1, node.allocatedBytes))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("İçerik").font(.headline)
                Spacer()
                Text("\(children.count) öğe").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
            Divider()
            if children.isEmpty {
                ContentUnavailableView("Klasör boş", systemImage: "folder", description: Text("Burada ölçülecek öğe yok."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            row(child, index: index, share: Double(child.allocatedBytes) / total)
                        }
                    }
                    .padding(.vertical, PocketSpacing.xs)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .pocketCard(padding: 0, radius: PocketRadius.medium)
    }

    private func row(_ child: SpaceLensNode, index: Int, share: Double) -> some View {
        let selectable = child.identity != nil && child.kind != .remainder
        let selected = model.selection.contains(child.id)
        return HStack(spacing: PocketSpacing.s) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in model.toggle(child) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!selectable || model.busy)
                .opacity(selectable ? 1 : 0)
                .accessibilityLabel("\(child.name) seç")
            Group {
                if child.kind == .remainder {
                    Image(systemName: "ellipsis.circle").resizable().foregroundStyle(.secondary)
                } else {
                    Image(nsImage: PocketIconCache.typeIcon(for: child.url, isDirectory: child.kind == .folder || child.kind == .package))
                        .resizable()
                }
            }
            .scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(child.name).lineLimit(1).truncationMode(.middle)
                    if !child.complete {
                        Image(systemName: PocketTone.warning.symbol).font(.caption2).foregroundStyle(PocketTone.warning.color)
                            .help("Bu klasör tam ölçülemedi.")
                    }
                }
                GeometryReader { proxy in
                    Capsule().fill(Color.secondary.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule().fill(lensColorForList(child, index: index)).frame(width: max(2, proxy.size.width * share))
                        }
                }
                .frame(height: 3)
            }
            Text(pocketBytes(child.allocatedBytes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            if child.kind == .folder {
                Button { model.open(child) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(model.busy)
                    .help(child.needsExpansion ? Text("İçini tara ve aç") : Text("İçine gir"))
                    .accessibilityLabel("\(child.name) klasörünü aç")
            } else {
                Image(systemName: "chevron.right").opacity(0).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PocketSpacing.m).padding(.vertical, 5)
        .background(hovered == child.id ? Color.accentColor.opacity(0.1) : (selected ? Color.accentColor.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? child.id : (hovered == child.id ? nil : hovered) }
        .onTapGesture(count: 2) { if child.kind == .folder { model.open(child) } }
        .help(child.kind == .remainder ? Text("Ayrı gösterilemeyecek kadar küçük öğelerin toplamı") : Text(verbatim: child.path))
        .contextMenu {
            if child.kind != .remainder {
                Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([child.url]) }
                if child.kind == .folder { Button("Aç") { model.open(child) } }
                if selectable { Button(selected ? ("Seçimi Kaldır" as LocalizedStringKey) : "Seç") { model.toggle(child) } }
            }
        }
    }

    private func lensColorForList(_ child: SpaceLensNode, index: Int) -> Color {
        guard child.kind == .folder else { return child.kind.color }
        let folderIndex = (node.children ?? []).prefix(index).filter { $0.kind == .folder && $0.allocatedBytes > 0 }.count
        return lensColor(child, index: folderIndex)
    }
}
