import AppKit
import MacPocketCore
import MapKit
import SwiftUI

@MainActor
struct WeatherLocationPicker: View {
    @ObservedObject private var service = WeatherService.shared
    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var searching = false
    @State private var editing = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            if let location = service.location {
                HStack(alignment: .top) {
                    Label { Text(verbatim: location.name).lineLimit(2) } icon: { Image(systemName: "mappin.circle") }
                    Spacer(minLength: 4)
                    Button("Konumu Değiştir") { editing.toggle() }.controlSize(.small)
                }
            }
            if editing || service.location == nil {
                HStack {
                    TextField("Şehir veya ilçe ara", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button("Ara") { search() }.disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if searching { ProgressView("Konumlar aranıyor…").controlSize(.small) }
                if let searchError { Text(searchError).font(.caption).foregroundStyle(.orange) }
                ForEach(results) { location in
                    Button {
                        service.select(location); editing = false; results = []; query = ""
                    } label: {
                        HStack {
                            Image(systemName: "mappin")
                            Text(verbatim: location.name).multilineTextAlignment(.leading).lineLimit(3)
                            Spacer(minLength: 4)
                            Image(systemName: "plus.circle")
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.vertical, 4)
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true; results = []; searchError = nil
        searchTask = Task { @MainActor in
            defer { searching = false }
            do {
                results = try await WeatherLocationSearch.find(text)
                guard !Task.isCancelled else { return }
                if results.isEmpty { searchError = String(localized: "Konum bulunamadı. Şehir adının yanına ülke veya bölge ekleyerek dene.") }
            } catch {
                if !Task.isCancelled { searchError = String(localized: "Konum araması tamamlanamadı. Bağlantını kontrol edip yeniden dene.") }
            }
        }
    }
}

struct WeatherDetail: View {
    @ObservedObject private var service = WeatherService.shared
    @State private var contentHeight: CGFloat = 160

    var body: some View {
        ScrollView {
            content.padding(.trailing, 2)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, 510))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            WeatherLocationPicker()
            if let snapshot = service.snapshot {
                HStack(spacing: PocketSpacing.m) {
                    Image(systemName: snapshot.symbol).font(.system(size: 32)).foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(temperature(snapshot.current.temperature)).font(.system(size: 32, weight: .medium, design: .rounded))
                        Text(verbatim: snapshot.current.conditions ?? snapshot.current.icon?.name ?? "—").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                HStack(alignment: .top) {
                    metric("Hissedilen", temperature(snapshot.current.apparent))
                    Spacer()
                    metric("Nem", snapshot.current.humidity.map { MenuBarFormatter.percent($0, decimals: false) } ?? "—")
                    Spacer()
                    metric("Rüzgâr", snapshot.current.windSpeed.map { String(localized: "\(MenuBarFormatter.number($0 * 3.6, fractionDigits: 1)) km/sa") } ?? "—")
                }
                let hours = Array(snapshot.hourly.filter { $0.time >= Date().timeIntervalSince1970 }.prefix(8))
                if !hours.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PocketSpacing.m) {
                            ForEach(hours) { hour in
                                VStack(spacing: 6) {
                                    Text(date(hour.time, snapshot: snapshot, pattern: "HH:mm")).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: hour.symbol).accessibilityHidden(true)
                                    Text(temperature(hour.temperature)).font(.caption.weight(.medium))
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                let days = Array(snapshot.forecast.filter { ($0.end ?? $0.start + 86400) > Date().timeIntervalSince1970 }.prefix(5))
                ForEach(days) { day in
                    HStack {
                        Text(date(day.start, snapshot: snapshot, pattern: "EEE")).frame(width: 56, alignment: .leading)
                        Image(systemName: day.icon?.symbol ?? "cloud.sun.fill").frame(width: 22).accessibilityHidden(true)
                        Spacer()
                        Text(temperature(day.low)).foregroundStyle(.secondary)
                        Text(temperature(day.high)).frame(width: 56, alignment: .trailing)
                    }.font(.callout).monospacedDigit()
                }
                HStack {
                    Text("Güncelleme: \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(Array(snapshot.attributions.enumerated()), id: \.offset) { _, attribution in
                        if let url = attribution.url { Link(attribution.title, destination: url).font(.caption) }
                    }
                }
            } else if service.loading {
                ProgressView("Hava durumu alınıyor…").controlSize(.small)
            } else if service.location == nil {
                Text("Menü çubuğunda hava durumunu görmek için bir konum seç.").font(.callout).foregroundStyle(.secondary)
            }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if service.location != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        Text("Saatte bir otomatik yenilenir.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { service.refresh(manual: true) } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                            .controlSize(.small).disabled(!service.canRefresh)
                            .help("Elle yenileme için istekler arasında en az bir dakika beklenir.")
                    }
                }
            }
        }
    }

    private func temperature(_ value: Double?) -> String {
        value.map { MenuBarFormatter.number($0, fractionDigits: 0) + "°C" } ?? "—"
    }
    private func date(_ timestamp: Double, snapshot: WeatherSnapshot, pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = pocketLocale; formatter.timeZone = snapshot.timeZone; formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}
