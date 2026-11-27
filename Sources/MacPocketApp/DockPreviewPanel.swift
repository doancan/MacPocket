import AppKit
import MacPocketCore
import SwiftUI

private final class DockPreviewWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DockPreviewHost<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class DockPreviewPanelController {
    private unowned let service: DockPreviewService
    private(set) var window: NSWindow?
    private var keyMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private(set) var layout = DockPreviewLayout.compute(count: 1, icon: .zero, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), edge: .bottom)
    var frame: CGRect? { window?.frame }
    var isVisible: Bool { window?.isVisible == true }
    init(service: DockPreviewService) { self.service = service }

    func show(anchor: CGRect, edge: DockEdge, focus: Bool) {
        if window == nil {
            let panel = DockPreviewWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.title = String(localized: "Dock Önizlemeleri")
            panel.contentView = nil
            window = panel
        }
        resize(anchor: anchor, edge: edge)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return consumed ? nil : event
        }
        if menuObservers.isEmpty {
            for (name, open) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
                menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak service] _ in
                    MainActor.assumeIsolated { service?.menuChanged(open) }
                })
            }
        }
        if focus { window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(window?.contentView) }
        else { window?.orderFrontRegardless() }
    }

    func resize(anchor: CGRect, edge: DockEdge) {
        guard !service.menuIsOpen else { return }
        let midpoint = CGPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) ?? NSScreen.main else { return }
        let computed = DockPreviewLayout.compute(count: service.windows.count, icon: anchor, visibleFrame: screen.visibleFrame, edge: edge)
        let changed = computed.frame.size != layout.frame.size || computed.columns != layout.columns || window?.contentView == nil
        layout = computed
        if changed {
            let host = DockPreviewHost(rootView: DockPreviewPanelView(service: service, layout: computed).pocketAppearanceRoot())
            window?.contentView = host
            window?.initialFirstResponder = host
            window?.makeFirstResponder(host)
        }
        window?.setFrame(computed.frame, display: true)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === window, window?.isVisible == true, !service.menuIsOpen else { return false }
        if event.keyCode == 53 { service.close(); return true }
        guard !(window?.firstResponder is NSControl), !(window?.firstResponder is NSTextView),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 123: service.moveSelection(-1)
        case 124: service.moveSelection(1)
        case 125: service.moveSelection(layout.columns)
        case 126: service.moveSelection(-layout.columns)
        case 36, 76: if let selected = service.selected { service.perform(.focus, on: selected) }
        default: return false
        }
        return true
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers = []
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        window?.contentView = nil
    }

    #if DEBUG
    var diagnosticResources: [String: Int] { ["keyMonitor": keyMonitor == nil ? 0 : 1, "menuObservers": menuObservers.count] }
    var diagnosticKeyboardState: [String: Bool] {
        ["gridFirstResponder": window?.firstResponder === window?.contentView, "keyWindow": window?.isKeyWindow == true,
         "menuOpen": service.menuIsOpen, "appActive": NSApp.isActive]
    }
    #endif
}

struct DockPreviewPanelView: View {
    @ObservedObject var service: DockPreviewService
    let layout: DockPreviewLayout
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.s) {
                PocketAppIcon(url: service.target?.applicationURL, size: 22)
                Text(service.target?.application ?? String(localized: "Pencereler"))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if service.actionBusyID != nil { ProgressView().controlSize(.small).accessibilityLabel("Pencere işlemi sürüyor") }
                Text("\(service.windows.count) pencere").font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button("Bu Uygulamayı Hariç Tut") { service.excludeTarget() }
                    Button("Önizlemeyi Kapat") { service.close() }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Dock önizleme seçenekleri")
                Button { service.close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Dock önizlemesini kapat")
            }
            if service.loading {
                ProgressView("Pencereler okunuyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.windows.isEmpty {
                ContentUnavailableView("Açık pencere yok", systemImage: "macwindow", description: Text("Bu uygulamanın gösterilebilen penceresi yok."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardSize.width), spacing: DockPreviewLayout.spacing), count: layout.columns), spacing: DockPreviewLayout.spacing) {
                            ForEach(service.windows) { window in
                                DockWindowCard(window: window, service: service, size: layout.cardSize)
                                    .id(window.id)
                                    .onAppear { service.setVisible(window.id, true) }
                                    .onDisappear { service.setVisible(window.id, false) }
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: service.selectedID) { _, id in
                        if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { reader.scrollTo(id) } }
                    }
                }
            }
            if let message = service.message {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else if !service.captureAllowed, service.settings.thumbnails {
                Label("Görseller için Ekran Kaydı izni gerekli", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if service.partial {
                Label("Bazı pencereler okunamadı", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            } else if !service.settings.currentSpaceOnly, !service.otherSpacesVisible {
                Text("Diğer masaüstlerindeki bazı pencereler görünmeyebilir.").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(DockPreviewLayout.padding)
        .frame(width: layout.frame.width, height: layout.frame.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PocketRadius.large).strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel("Dock Önizlemeleri")
    }
}

private struct DockWindowCard: View {
    let window: SwitchableWindow
    @ObservedObject var service: DockPreviewService
    let size: CGSize
    private var selected: Bool { service.selectedID == window.id }
    var body: some View {
        VStack(spacing: 4) {
            Button { service.perform(.focus, on: window) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(window.title).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if window.minimized { Image(systemName: "minus.square").accessibilityLabel("Küçültülmüş") }
                        if window.otherSpace { Image(systemName: "rectangle.3.group").accessibilityLabel("Başka masaüstünde") }
                    }
                    ZStack {
                        RoundedRectangle(cornerRadius: PocketRadius.small).fill(.primary.opacity(0.06))
                        if let image = service.thumbnails[window.id] {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small))
                        } else {
                            VStack(spacing: 4) {
                                PocketAppIcon(url: window.applicationURL, size: 34)
                                if window.minimized { Text("Küçültülmüş").font(.caption).foregroundStyle(.secondary) }
                                else if service.unavailableImages.contains(window.id) { Text("Görsel alınamadı").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .frame(height: 112)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(window.title) penceresine geç")
            HStack(spacing: 8) {
                if window.canMinimize {
                    Button { service.perform(.window(window.minimized ? .restore : .minimize), on: window) } label: {
                        Image(systemName: window.minimized ? "arrow.up.left.and.arrow.down.right" : "minus")
                    }
                    .accessibilityLabel(window.minimized ? "Pencereyi geri aç" : "Pencereyi küçült")
                    .help(window.minimized ? "Pencereyi geri aç" : "Pencereyi küçült")
                }
                if window.canResize, !window.fullScreen {
                    Menu {
                        ForEach([WindowLayoutAction.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize, .center, .nextDisplay, .previousDisplay]) { action in
                            Button(action.title) { service.perform(.layout(action), on: window) }
                                .disabled((action == .nextDisplay || action == .previousDisplay) && NSScreen.screens.count < 2)
                        }
                    } label: { Image(systemName: "rectangle.split.2x1") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Pencereyi yerleştir")
                }
                Spacer(minLength: 0)
                if window.canClose {
                    Button { service.perform(.window(.close), on: window) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Pencereyi kapat").help("Pencereyi kapat")
                }
            }
            .buttonStyle(.borderless)
            .frame(height: 20)
        }
        .padding(6)
        .frame(width: size.width, height: size.height)
        .background(selected ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: PocketRadius.medium))
        .overlay { RoundedRectangle(cornerRadius: PocketRadius.medium).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2) }
        .disabled(service.actionBusyID != nil)
        .onContinuousHover { phase in if case .active = phase { service.selectFromHover(window.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(window.title)
    }
}
