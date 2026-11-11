import MacPocketCore
import SwiftUI

/// Before scanning: a profile picker, one tile per category and an expandable list of its locations.
struct CleanupScanPlanner: View {
    var model: CleanupModel
    @Environment(\.pocketTint) private var tint
    @PocketReduceMotion private var reduceMotion
    @State private var openGroup: CleanupGroup?

    private var groups: [CleanupGroup] { CleanupGroup.allCases.filter { group in model.targets.contains { $0.group == group } } }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: openGroup) { _, group in
                    guard group != nil else { return }
                    withAnimation(animation) { proxy.scrollTo("locations", anchor: .bottom) }
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.m) {
                PocketSectionHeader("Ne taransın?", icon: "checklist")
                Spacer(minLength: PocketSpacing.s)
            }
            profilePicker
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: PocketSpacing.m, alignment: .top)], spacing: PocketSpacing.m) {
                ForEach(groups) { group in
                    CleanupCategoryTile(model: model, group: group, open: openGroup == group) {
                        withAnimation(animation) { openGroup = openGroup == group ? nil : group }
                    }
                }
            }
            if let openGroup {
                CleanupLocationList(model: model, group: openGroup) {
                    withAnimation(animation) { self.openGroup = nil }
                }
                .id("locations")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86) }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Picker("Profil", selection: Binding(get: { model.scanProfile }, set: { profile in
                withAnimation(animation) { model.applyProfile(profile) }
            })) {
                ForEach(CleanupProfile.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .tint(tint)
            .labelsHidden()
            .fixedSize()
            .disabled(model.busy)
            .accessibilityLabel("Tarama profili")
            Text(model.scanProfile.localizedDetail)
                .font(.subheadline).foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }
}

// MARK: - Category tile

private struct CleanupCategoryTile: View {
    var model: CleanupModel
    let group: CleanupGroup
    let open: Bool
    let toggleOpen: () -> Void
    @Environment(\.pocketTint) private var tint
    @State private var hovering = false

    private var members: [CleanupTarget] { model.targets.filter { $0.group == group } }
    private var included: Int { members.filter { model.scanSelection.contains($0.id) }.count }
    private var state: CleanupModel.TargetSelection { included == 0 ? .none : included == members.count ? .all : .some }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .top) {
                PocketIconTile(symbol: group.symbol, tint: state == .none ? Color(hex: 0x8E8E93) : tint, size: 32)
                Spacer(minLength: PocketSpacing.s)
                Image(systemName: checkSymbol)
                    .font(.title3)
                    .foregroundStyle(state == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(group.title).font(.headline).lineLimit(1)
                Text(caption).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            if members.count > 1 {
                Button(action: toggleOpen) {
                    HStack(spacing: PocketSpacing.xxs) {
                        Text("Konumlar")
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? Text("\(group.title) konumlarını gizle") : Text("\(group.title) konumlarını göster"))
            } else {
                Text(" ").font(.subheadline).accessibilityHidden(true)
            }
        }
        .padding(PocketSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .fill(state == .none ? AnyShapeStyle(.quaternary.opacity(hovering ? 0.9 : 0.55))
                                     : AnyShapeStyle(tint.opacity(hovering ? 0.18 : 0.12)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .strokeBorder(open ? tint : (state == .none ? Color.primary.opacity(0.08) : tint.opacity(0.35)),
                              lineWidth: open ? 1.5 : 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
        .onTapGesture { toggle() }
        .onHover { hovering = $0 }
        .disabled(model.busy)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(group.title))
        .accessibilityValue(state == .none ? Text("Taranmayacak") : Text("\(included)/\(members.count) konum taranacak"))
        .accessibilityAction { toggle() }
        .help(state == .all ? Text("Bu kategoriyi taramadan çıkar") : Text("Bu kategoriyi taramaya ekle"))
    }

    private var checkSymbol: String {
        switch state {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }

    private var caption: String {
        let count = String(localized: "\(included)/\(members.count) konum")
        if group == .separate { return String(localized: "\(count) · yalnız bilgi") }
        guard let bytes = model.lastSizes.total(of: members.map(\.id)) else { return count }
        return String(localized: "\(count) · son: \(pocketDiskBytes(bytes))")
    }

    private func toggle() {
        guard !model.busy else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.scanSelection.set(group, included: state != .all, targets: model.targets)
        }
    }
}

// MARK: - Location list

private struct CleanupLocationList: View {
    @Bindable var model: CleanupModel
    let group: CleanupGroup
    let close: () -> Void
    @Environment(\.pocketTint) private var tint

    var body: some View {
        let members = model.targets.filter { $0.group == group }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: group.symbol).foregroundStyle(tint)
                Text(group.title).font(.headline)
                Spacer(minLength: PocketSpacing.s)
                Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Konum listesini kapat")
            }
            .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
            ForEach(members) { target in
                Divider().padding(.leading, PocketSpacing.m)
                row(target)
            }
        }
        .pocketCard(padding: 0, radius: PocketRadius.large)
    }

    private func row(_ target: CleanupTarget) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Toggle(isOn: Binding(get: { model.scanSelection.contains(target.id) },
                                 set: { included in withAnimation(.snappy(duration: 0.2)) { model.scanSelection.set(target.id, included: included) } })) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: PocketSpacing.xs) {
                        Text(target.title).font(.callout.weight(.medium))
                        CleanupSafetyBadge(safety: target.safety)
                    }
                    Text(target.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(model.busy)
            Spacer(minLength: PocketSpacing.s)
            if target.id == .oldDownloads {
                Picker("Eski indirilenler", selection: $model.downloadsAgeDays) {
                    Text("30 günden eski").tag(30)
                    Text("90 günden eski").tag(90)
                    Text("180 günden eski").tag(180)
                    Text("1 yıldan eski").tag(365)
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .disabled(model.busy)
                .help("Eski İndirilenler bu süreden uzun süredir dokunulmamış öğeleri listeler.")
                    .pocketMenuPicker()
            }
            Text(model.lastSizes.bytes[target.id].map { pocketDiskBytes($0) } ?? "—")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
                .help("Son taramada bulunan boyut")
        }
        .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
    }
}
