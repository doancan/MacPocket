import AppKit
@preconcurrency import Carbon
import MacPocketCore
import SwiftUI

// MARK: - Settings

struct SwitcherSettingsForm: View {
    @ObservedObject var controller: WindowSwitcherHotkeyController
    @AppStorage("switcher.globalEnabled") private var enabled = true
    @AppStorage("switcher.style") private var style = SwitcherStyle.thumbnails.rawValue
    @AppStorage("switcher.theme") private var theme = SwitcherTheme.system.rawValue
    @AppStorage("switcher.autoSize") private var autoSize = true
    @AppStorage("switcher.size") private var size = 1.0
    @AppStorage("switcher.previewSelected") private var previewSelected = false
    @AppStorage("switcher.liveThumbnails") private var liveThumbnails = true
    @AppStorage("switcher.hoverSelects") private var hoverSelects = true
    @AppStorage("switcher.sort") private var sort = "recent"
    @State private var showsAdvanced = false

    var body: some View {
        Form {
            Section {
                Toggle("Global kısayolları etkinleştir", isOn: $enabled)
                    .disabled(controller.recordingShortcut)
                ForEach(Array(controller.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    ShortcutRow(shortcut: shortcut, canDelete: controller.shortcuts.count > 1,
                                update: { replace(index, with: $0) }, delete: { remove(index) },
                                preview: { controller.show(shortcut: shortcut) },
                                recordingLocked: controller.recordingShortcut,
                                setRecording: controller.setRecording)
                }
                HStack {
                    Button { add() } label: { Label("Kısayol Ekle", systemImage: "plus") }
                        .disabled(controller.recordingShortcut || controller.shortcuts.count >= SwitcherShortcut.maximumCount)
                    Spacer()
                    Text("\(controller.shortcuts.count) / \(SwitcherShortcut.maximumCount)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(controller.shortcutEditingError ?? controller.registrationMessage).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.canRetryNativeKeys {
                    Button("Yeniden Dene",action: controller.retryNativeKeys).disabled(controller.recordingShortcut)
                }
            } header: { Text("Kısayollar") } footer: {
                Text("Her kısayolun kendi filtreleri, görünümü ve bırakma davranışı vardır. Özelleştirilmeyen seçenekler genel ayarları izler. Shift ters yönde gezer.")
                if controller.shortcuts.contains(where: { $0.keyCode == SwitcherKeys.tab && $0.modifiers == .command }) {
                    Text("⌘Tab etkinken macOS uygulama geçişi yerine MacPocket kullanılır.")
                }
            }

            Section("Görünüm") {
                LabeledContent("Stil") {
                    GlassTabBar(tabs: [GlassTab(id: SwitcherStyle.thumbnails.rawValue, title: "Küçük resimler", symbol: "rectangle.grid.2x2"),
                                       GlassTab(id: SwitcherStyle.icons.rawValue, title: "Uygulama simgeleri", symbol: "app.dashed"),
                                       GlassTab(id: SwitcherStyle.titles.rawValue, title: "Başlık listesi", symbol: "list.bullet")],
                                selection: $style)
                        .frame(maxWidth: 420)
                }
                Toggle("Otomatik boyut (pencere sayısına göre küçült)", isOn: $autoSize)
                Picker("Tema", selection: $theme) {
                    ForEach(SwitcherTheme.allCases, id: \.self) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                    .pocketMenuPicker()
                Slider(value: $size, in: 0.6...1.4, step: 0.1) { Text("Boyut") } minimumValueLabel: { Text("Küçük") } maximumValueLabel: { Text("Büyük") }
                Toggle("Canlı küçük resimler (panel açıkken yenilenir)", isOn: $liveThumbnails)
                Toggle("Seçili pencereyi yerinde tam boy göster", isOn: $previewSelected)
                Picker("Sıralama", selection: $sort) {
                    ForEach(WindowSortOrder.allCases, id: \.self) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                    .pocketMenuPicker()
                if sort == WindowSortOrder.creation.rawValue { SwitcherCreationOrderNote() }
                DisclosureGroup("Kart ayrıntıları") { SwitcherGlobalCardOptions() }.disabled(controller.recordingShortcut)
                DisclosureGroup("Panelin yeri ve gecikme") { SwitcherGlobalPlacementOptions() }.disabled(controller.recordingShortcut)
                DisclosureGroup("Animasyonlar") { SwitcherGlobalMotionOptions() }.disabled(controller.recordingShortcut)
                Text("Bu bölüm genel görünümü belirler. Kısayollarda farklı bir görünüm seçebilirsin. Saydamlığı azalt tercihinde düz arka plan kullanılır.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Gelişmiş ayarları göster", isOn: $showsAdvanced)
                    .disabled(controller.recordingShortcut)
            } footer: {
                Text("Davranış, eylem tuşları, istisnalar, trackpad, ayar aktarımı ve komut satırı.")
            }

            if showsAdvanced {
                Section("Davranış") {
                    SwitcherNavigationSettings(bindings: controller.actionBindings).disabled(controller.recordingShortcut)
                    Toggle("Fareyle üzerine gelince seç", isOn: $hoverSelects)
                    SwitcherCursorSettings().disabled(controller.recordingShortcut)
                }

                Section {
                    if let error = controller.actionEditingError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    }
                    ForEach(controller.actionBindings) { binding in
                        SwitcherActionRow(binding: binding, allBindings: controller.actionBindings, recordingLocked: controller.recordingShortcut,
                                          update: { edited in
                            controller.saveActionBindings(controller.actionBindings.map { $0.action == edited.action ? edited : $0 })
                        }, setRecording: controller.setRecording)
                    }
                    Button("Eylem kısayollarını sıfırla") { controller.saveActionBindings(SwitcherActionBinding.defaults) }
                        .disabled(controller.recordingShortcut)
                } header: { Text("Panel açıkken kısayollar") } footer: {
                    Text("Tab/Shift+Tab her zaman gezinir; Escape vazgeçer. Oklar ve Vim gezinmesi Davranış bölümünden seçilir. Arama sırasında tek başına harfler metin yazar.")
                }

                Section {
                    SwitcherExceptionsEditor().disabled(controller.recordingShortcut)
                } header: { Text("İstisnalar") } footer: {
                    Text("Eşleşen kurallardan biri pencereyi gizler veya kısayolları kapatırsa o sonuç uygulanır. Bir kural diğerini geçersiz kılmaz.")
                    Text("Sanal makineler ve uzak masaüstü uygulamaları için kısayolları kapatmak, ⌥⇥’ın o uygulamaya iletilmesini sağlar.")
                }

                Section {
                    SwitcherGestureSettings(isAvailable: TrackpadSwipeMonitor.shared.isAvailable)
                        .disabled(controller.recordingShortcut)
                } header: { Text("Trackpad") }

                Section("Ayar aktarımı") {
                    SwitcherSettingsTransferLink().disabled(controller.recordingShortcut)
                }

                Section("Komut satırı") {
                    Text(verbatim: "MacPocket.app/Contents/MacOS/MacPocket --switcher list --detailed\nMacPocket.app/Contents/MacOS/MacPocket --switcher focus --mru 2\nMacPocket.app/Contents/MacOS/MacPocket --switcher show 1\nMacPocket.app/Contents/MacOS/MacPocket --switcher hide")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Komutlar çalışan MacPocket'a bağlanır. Profil ve MRU sırası 1'den başlar; show paneli açar, hide seçim yapmadan kapatır. status panelin görünürlüğünü bildirir.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Liste kısayol filtrelerinden bağımsız gerçek pencereleri içerir. MRU sırası her çağrıda güncellenebilir; belirli bir pencere için list çıktısındaki id değerini kullan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .pocketFormPage()
        .scrollContentBackground(.hidden)
    }

    private func replace(_ index: Int, with shortcut: SwitcherShortcut) {
        var list = controller.shortcuts
        guard list.indices.contains(index) else { return }
        list[index] = shortcut
        controller.saveShortcuts(list)
    }

    private func remove(_ index: Int) {
        var list = controller.shortcuts
        guard list.indices.contains(index), list.count > 1 else { return }
        list.remove(at: index)
        controller.saveShortcuts(list)
    }

    private func add() {
        var list = controller.shortcuts
        guard list.count < SwitcherShortcut.maximumCount else { return }
        // Suggest ⌥` (current app's windows), then ⌥1…⌥9 style combinations that are not yet used.
        let candidates: [SwitcherShortcut] = [.init(keyCode: SwitcherKeys.grave, modifiers: .option)]
            + [18, 19, 20, 21, 23, 22, 26, 28, 25].map { SwitcherShortcut(keyCode: $0, modifiers: [.control, .option]) }
        var next = candidates.first { candidate in !list.contains { $0.keyCode == candidate.keyCode && $0.modifiers == candidate.modifiers } }
            ?? .init(keyCode: SwitcherKeys.space, modifiers: [.control, .option, .command])
        if next.keyCode == SwitcherKeys.grave { next.filter.currentApplicationOnly = true }
        list.append(next)
        controller.saveShortcuts(list)
    }
}

private struct ShortcutRow: View {
    let shortcut: SwitcherShortcut
    let canDelete: Bool
    let update: (SwitcherShortcut) -> Void
    let delete: () -> Void
    let preview: () -> Void
    let recordingLocked: Bool
    let setRecording: (Bool) -> Bool
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
      VStack(alignment: .leading, spacing: PocketSpacing.s) {
        HStack(spacing: PocketSpacing.m) {
            Button { recording ? stopRecording() : startRecording() } label: {
                (recording ? Text("Tuşlara bas…") : Text(shortcut.displayName))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(minWidth: 96)
            }
            // While recording, the button is the one live action on screen.
            .buttonStyle(recording ? .pocketPrimary : .pocketSecondary)
            .disabled(recordingLocked && !recording)
            .help("Yeni kısayolu kaydetmek için tıkla, ardından tuş birleşimine bas (esc: vazgeç)")
            .accessibilityLabel("Kısayol \(shortcut.displayName), değiştirmek için tıkla")

            SwitcherShortcutPresets(shortcut: shortcut,update: update).disabled(recordingLocked)

            Text(filterSummary).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(!canDelete || recordingLocked)
                .help("Kısayolu sil").accessibilityLabel("Kısayolu sil")
        }
        Picker("Tuşlar bırakılınca", selection: binding(\.releaseBehavior)) {
            ForEach(SwitcherReleaseBehavior.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
        }
        .disabled(recordingLocked)
            .pocketMenuPicker()
        SwitcherHoldOptions(shortcut: shortcut,update: update).disabled(recordingLocked)
        DisclosureGroup("Filtreler ve gruplama") {
            SwitcherFilterOptions(filter: binding(\.filter))
        }
        .disabled(recordingLocked)
        DisclosureGroup("Görünüm ve sıralama") {
            SwitcherShortcutOptions(shortcut: shortcut, update: update)
            Button(action: preview) { Label("Bu kısayolu önizle", systemImage: "play.rectangle") }
        }
        .disabled(recordingLocked)
      }
        .onDisappear { stopRecording() }
        .onChange(of: recordingLocked) { _, locked in if !locked && recording { stopRecording() } }
    }

    private var filterSummary: String {
        var parts = [shortcut.filter.applicationScope.localizedTitle]
        if shortcut.filter.spaceScope != .all { parts.append(shortcut.filter.spaceScope.localizedTitle) }
        if shortcut.filter.currentScreenOnly { parts.append(String(localized: "bu ekran")) }
        if shortcut.filter.grouping != .allWindows { parts.append(shortcut.filter.grouping.localizedTitle) }
        return parts.joined(separator: " · ")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SwitcherShortcut, Value>) -> Binding<Value> {
        Binding(get: { shortcut[keyPath: keyPath] }, set: { value in
            var copy = shortcut
            copy[keyPath: keyPath] = value
            update(copy)
        })
    }

    private func startRecording() {
        guard setRecording(true) else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode, flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated { () -> Bool in
                if Int(keyCode) == kVK_Escape { stopRecording(); return true }
                let modifiers: SwitcherModifiers = [flags.contains(.control) ? .control : [], flags.contains(.option) ? .option : [],
                                                    flags.contains(.command) ? .command : []]
                guard !modifiers.isEmpty, SwitcherKeys.isSupported(keyCode) else { NSSound.beep(); return true }
                let copy = shortcut.replacingOpeningChord(keyCode: keyCode,modifiers: modifiers)
                stopRecording()
                update(copy)
                return true
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        _ = setRecording(false)
    }
}

/// Native picker: the opening chord stays visible in the profile header; release ownership is explicit.
struct SwitcherHoldOptions: View {
    let shortcut: SwitcherShortcut
    let update: (SwitcherShortcut) -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Basılı tutulan tuşlar",isExpanded: $expanded) {
            Picker("Basılı tutulacak değiştiriciler",selection: Binding(get: { shortcut.holdModifiers?.rawValue ?? 0 },set: { value in
                var copy = shortcut
                copy.holdModifiers = value == 0 ? nil : .init(rawValue: value)
                update(copy)
            })) {
                Text("Açma kısayolunu izle").tag(0)
                ForEach(shortcut.holdModifierChoices,id: \.rawValue) { value in Text("Yalnız \(value.symbols)").tag(value.rawValue) }
            }
            .pickerStyle(.radioGroup)
            .disabled(shortcut.holdModifierChoices.isEmpty)
            Text("Açma: \(shortcut.displayName) · Basılı tut: \(shortcut.effectiveHoldModifiers.symbols)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Seçilen değiştiricilerin tamamı bırakılınca yukarıdaki bırakma davranışı uygulanır. Açma birleşimindeki diğer tuşlar basılı kalabilir. Örneğin ⌃⌥Tab ile açıp yalnız ⌥ bırakılınca seçebilirsin.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
        }
    }
}

/// Kept as native form controls so all scopes remain reachable by keyboard and VoiceOver.
struct SwitcherFilterOptions: View {
    @Binding var filter: WindowListFilter

    var body: some View {
        option("Uygulama", selection: $filter.applicationScope, values: WindowApplicationScope.allCases) { $0.localizedTitle }
        option("Masaüstü", selection: $filter.spaceScope, values: WindowSpaceScope.allCases) { $0.localizedTitle }
        Picker("Ekran", selection: $filter.currentScreenOnly) {
            Text("Tüm ekranlar").tag(false)
            Text("Yalnız panelin gösterildiği ekran").tag(true)
        }
            .pocketMenuPicker()
        option("Küçültülmüş pencereler", selection: $filter.minimized, values: WindowVisibilityPolicy.allCases) { $0.localizedTitle }
        option("Gizli uygulamalar", selection: $filter.hidden, values: WindowVisibilityPolicy.allCases) { $0.localizedTitle }
        option("Penceresiz uygulamalar", selection: $filter.windowless, values: WindowVisibilityPolicy.allCases) { $0.localizedTitle }
        Toggle("Tam ekran pencerelerini göster", isOn: $filter.includeFullScreen)
        option("Gruplama", selection: $filter.grouping, values: WindowGrouping.allCases) { $0.localizedTitle }
        Toggle("macOS pencere sekmelerini ayrı göster", isOn: $filter.separateTabs)
        Text("Desteklenen pencere sekmeleri varsayılan olarak tek kartta toplanır. Arka plan sekmelerinin görüntüsü yalnız daha önce seçilmişse bulunabilir; tarayıcı sayfaları pencere sekmesi sayılmaz.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text("İmleç konumu panel açılırken alınır. Uygulama gruplaması, her çalışan uygulamanın filtrelenmiş sıralamadaki ilk penceresini gösterir.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text("Masaüstü filtresi macOS üyelik bilgisini kullanır; alınamazsa pencere görünürlüğüne döner. Konumu belirlenemeyen pencereler masaüstü ve ekran filtrelerinde korunur.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func option<Value: Hashable>(_ title: LocalizedStringKey, selection: Binding<Value>, values: [Value],
                                          label: @escaping (Value) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in Text(label(value)).tag(value) }
        }
            .pocketMenuPicker()
    }
}

/// The same controls render in the ordinary settings form and the isolated native UI audit.
struct SwitcherShortcutOptions: View {
    let shortcut: SwitcherShortcut
    let update: (SwitcherShortcut) -> Void

    var body: some View {
        option("Stil", selection: binding(\.style), values: SwitcherStyle.allCases, title: { $0.localizedTitle })
        option("Tema", selection: binding(\.theme), values: SwitcherTheme.allCases, title: { $0.localizedTitle })
        option("Boyutlandırma", selection: binding(\.autoSize), values: [true, false],
               title: { $0 ? String(localized: "Otomatik") : String(localized: "Sabit boyut") })
        Picker("Boyut", selection: binding(\.sizeScale)) {
            Text("Genel ayarı izle").tag(Optional<Double>.none)
            ForEach(6...14, id: \.self) { index in
                Text(Double(index) / 10, format: .percent.precision(.fractionLength(0))).tag(Optional(Double(index) / 10))
            }
        }
            .pocketMenuPicker()
        option("Tam boy önizleme", selection: binding(\.previewSelected), values: [true, false],
               title: { $0 ? String(localized: "Açık") : String(localized: "Kapalı") })
        option("Sıralama", selection: binding(\.order), values: WindowSortOrder.allCases, title: { $0.localizedTitle })
        if shortcut.presentation.order == .creation { SwitcherCreationOrderNote() }
        DisclosureGroup("Kart ayrıntıları") {
            option("Başlık", selection: binding(\.titleMode), values: SwitcherTitleMode.allCases, title: { $0.localizedTitle })
            option("Başlığı kısalt", selection: binding(\.truncation), values: SwitcherTitleTruncation.allCases, title: { $0.localizedTitle })
            option("Durum simgeleri", selection: binding(\.showStatus), values: [true, false], title: boolTitle)
            option("Masaüstü numaraları", selection: binding(\.showSpaces), values: [true, false], title: boolTitle)
            option("Dock bildirim rozetleri", selection: binding(\.showBadges), values: [true, false], title: boolTitle)
            SwitcherBadgeNote()
            option("Fare üzerindeyken pencere düğmeleri", selection: binding(\.showActions), values: [true, false], title: boolTitle)
            option("Küçük resimleri göster", selection: binding(\.showThumbnails), values: [true, false], title: boolTitle)
            SwitcherCardOptionsNote()
        }
        DisclosureGroup("Panelin yeri ve gecikme") {
            option("Paneli göster", selection: binding(\.screen), values: SwitcherScreenPolicy.allCases, title: { $0.localizedTitle })
            Toggle("Gecikmeyi özelleştir", isOn: Binding(get: { shortcut.presentation.openingDelayMilliseconds != nil }, set: { enabled in
                var copy = shortcut
                copy.presentation.openingDelayMilliseconds = enabled ? SwitcherPresentation.load().openingDelayMilliseconds : nil
                update(copy)
            }))
            if let delay = shortcut.presentation.openingDelayMilliseconds {
                Stepper("Açılma gecikmesi: \(delay) ms", value: Binding(get: { shortcut.presentation.openingDelayMilliseconds ?? delay }, set: { value in
                    var copy = shortcut
                    copy.presentation.openingDelayMilliseconds = value
                    update(copy)
                }), in: 0...900, step: 10)
            }
            SwitcherPlacementNote()
        }
        DisclosureGroup("Animasyonlar") {
            option("Panel açılışı", selection: binding(\.animateOpening), values: [true, false], title: boolTitle)
            option("Panel kapanışı", selection: binding(\.animateClosing), values: [true, false], title: boolTitle)
            option("Seçim animasyonu", selection: binding(\.animateSelection), values: [true, false], title: boolTitle)
            option("Tam boy önizleme girişi", selection: binding(\.animatePreview), values: [true, false], title: boolTitle)
            SwitcherMotionNote()
        }
        Button("Özelleştirmeleri sıfırla") {
            var copy = shortcut
            copy.presentation = .init()
            update(copy)
        }
        .disabled(shortcut.presentation.isEmpty)
    }

    private func boolTitle(_ value: Bool) -> String { value ? String(localized: "Açık") : String(localized: "Kapalı") }

    private func option<Value: Hashable>(_ label: LocalizedStringKey, selection: Binding<Value?>, values: [Value],
                                          title: @escaping (Value) -> String) -> some View {
        Picker(label, selection: selection) {
            Text("Genel ayarı izle").tag(Optional<Value>.none)
            ForEach(values, id: \.self) { value in Text(title(value)).tag(Optional(value)) }
        }
            .pocketMenuPicker()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SwitcherPresentationOverrides, Value>) -> Binding<Value> {
        Binding(get: { shortcut.presentation[keyPath: keyPath] }, set: { value in
            var copy = shortcut
            copy.presentation[keyPath: keyPath] = value
            update(copy)
        })
    }
}

private struct SwitcherActionRow: View {
    let binding: SwitcherActionBinding
    let allBindings: [SwitcherActionBinding]
    let recordingLocked: Bool
    let update: (SwitcherActionBinding) -> Void
    let setRecording: (Bool) -> Bool
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    private var fixedDefault: SwitcherActionBinding? {
        guard binding.action == .previous || binding.action == .cancel else { return nil }
        return SwitcherActionBinding.defaults.first { $0.action == binding.action }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(binding.action.localizedTitle) {
                HStack {
                    Button { recording ? stopRecording() : startRecording() } label: {
                        (recording ? Text("Tuşlara bas…") : Text(binding.displayName))
                            .font(.system(.body, design: .rounded).weight(.semibold)).frame(minWidth: 82)
                    }
                    .accessibilityLabel("\(binding.action.localizedTitle) kısayolunu değiştir")
                    .disabled(recordingLocked && !recording)
                    .help("Yeni kısayolu kaydetmek için tıkla, ardından tuş birleşimine bas (esc: vazgeç)")
                    Button {
                        if let fixedDefault { update(fixedDefault) }
                        else { var copy = binding; copy.keyCode = nil; update(copy) }
                    } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).disabled(recordingLocked || binding.keyCode == nil || binding == fixedDefault)
                    .help("Eylem kısayolunu kaldır").accessibilityLabel("Eylem kısayolunu kaldır")
                }
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
        }
        .onDisappear { stopRecording() }
        .onChange(of: recordingLocked) { _, locked in if !locked && recording { stopRecording() } }
    }

    private func startRecording() {
        guard setRecording(true) else { return }
        problem = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape { stopRecording(); return }
                var copy = binding
                copy.keyCode = event.keyCode
                copy.shift = event.modifierFlags.contains(.shift)
                copy.modifiers = [event.modifierFlags.contains(.control) ? .control : [],
                                  event.modifierFlags.contains(.option) ? .option : [], event.modifierFlags.contains(.command) ? .command : []]
                let messages = SwitcherActionBindings.problems(allBindings.map { $0.action == copy.action ? copy : $0 })
                if !messages.isEmpty { problem = messages.joined(separator: " "); NSSound.beep(); return }
                stopRecording()
                update(copy)
            }
            return nil
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        problem = nil
        _ = setRecording(false)
    }
}
