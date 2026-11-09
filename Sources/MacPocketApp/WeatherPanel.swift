import AppKit
import MacPocketCore
import SwiftUI

/// Forecast first; location and provider configuration live on a separate page inside the popover.
struct WeatherDetail: View {
    @ObservedObject var service: WeatherService = .shared
    @State private var settings = false
    @State private var contentHeight: CGFloat = 360
    @State private var hourViewport = WeatherHourViewport()
    @State private var selectedHourID: Double?
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            header
            if settings {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSpacing.l) {
                        WeatherLocationPicker(service: service)
                        Divider()
                        WeatherSourcePicker(service: service, initiallyExpanded: true)
                    }.padding(.vertical, PocketSpacing.xs)
                }.frame(height: scrollHeight)
            } else {
                ScrollView {
                    forecastContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, PocketSpacing.xs)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, scrollHeight))
                Divider()
                sourceFooter
            }
        }
    }
    private var scrollHeight: CGFloat { min(450, max(220, (NSScreen.main?.visibleFrame.height ?? 800) - 190)) }
    private var header: some View {
        HStack(spacing: PocketSpacing.s) {
            if settings {
                Button { settings = false } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).help("Hava Durumuna Dön").accessibilityLabel("Hava Durumuna Dön").weatherAuditTarget("weather.back")
                Text("Konum ve Kaynaklar").font(.headline).accessibilityAddTraits(.isHeader)
            } else {
                Image(systemName: "mappin").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                if let location = service.location {
                    Text(verbatim: location.name).font(.headline).lineLimit(1).truncationMode(.middle).help(location.name)
                        .accessibilityAddTraits(.isHeader)
                } else { Text("Hava Durumu").font(.headline).accessibilityAddTraits(.isHeader) }
                Spacer(minLength: PocketSpacing.s)
                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Hava Durumu Ayarları").accessibilityLabel("Hava Durumu Ayarları").weatherAuditTarget("weather.settings")
            }
        }
    }

    @ViewBuilder private var forecastContent: some View {
        if let snapshot = service.snapshot {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                currentWeather(snapshot)
                measurements(snapshot)
                if let error = service.error {
                    Label { Text(error).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.caption).foregroundStyle(.orange)
                }
                let hours = Array(snapshot.hourly.filter { $0.time >= Date().timeIntervalSince1970 }.prefix(12))
                let days = Array(snapshot.forecast.filter { ($0.end ?? $0.start + 86_400) > Date().timeIntervalSince1970 }.prefix(5))
                if !hours.isEmpty { hourly(hours, snapshot: snapshot) }
                if !days.isEmpty { daily(days, snapshot: snapshot) }
                if hours.isEmpty && days.isEmpty {
                    Text("Bu kaynak için ayrıntılı tahmin verisi yok.").font(.caption).foregroundStyle(.secondary).weatherAuditTarget("weather.current-only")
                }
            }
        } else if service.location == nil {
            emptyState("Konumunu seç", message: String(localized: "Şehir veya ilçe ekleyerek hava durumunu menü çubuğundan takip et."), symbol: "mappin.and.ellipse") {
                Button("Konum Seç") { settings = true }.buttonStyle(.borderedProminent).controlSize(.small).weatherAuditTarget("weather.choose-location")
            }
        } else if service.loading {
            VStack(spacing: PocketSpacing.m) {
                ProgressView().controlSize(.small)
                Text("Hava durumu alınıyor…").font(.callout)
                Text(service.activeSource.localizedTitle).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, PocketSpacing.xxl).weatherAuditTarget("weather.loading")
        } else if service.activeSource.requiresAPIKey && !service.configuredKeys.contains(service.activeSource) {
            emptyState("Kaynağı bağla", message: String(localized: "\(service.activeSource.localizedTitle) için kendi ücretsiz API anahtarını ekle veya anahtarsız bir kaynak seç."), symbol: "key") {
                Button("API Anahtarı Ekle") { settings = true }.buttonStyle(.borderedProminent).controlSize(.small).weatherAuditTarget("weather.connect")
            }
        } else {
            emptyState("Hava durumu alınamadı", message: service.error ?? String(localized: "Başka bir kaynak seçebilir veya daha sonra yeniden deneyebilirsin."), symbol: "cloud.slash") {
                Button("Kaynakları Düzenle") { settings = true }.buttonStyle(.bordered).controlSize(.small).weatherAuditTarget("weather.unavailable")
            }
        }
    }

    private func currentWeather(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(snapshot.current.temperature.map { MenuBarFormatter.number($0, fractionDigits: 0) } ?? "—")
                        .font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    Text(verbatim: "°C").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .ignore).accessibilityLabel("Sıcaklık: \(temperature(snapshot.current.temperature)) Celsius")
                Text(verbatim: snapshot.current.conditions ?? snapshot.current.icon?.name ?? "—")
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                if let apparent = snapshot.current.apparent {
                    Text("Hissedilen \(temperature(apparent))").font(.caption).foregroundStyle(.secondary).padding(.top, PocketSpacing.xs)
                }
            }
            Spacer(minLength: PocketSpacing.s)
            WeatherConditionSymbol(symbol: snapshot.symbol, size: 52).frame(width: 76)
        }.padding(.vertical, PocketSpacing.xs).weatherAuditTarget("weather.current")
    }
    private func measurements(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            metric("Nem", symbol: "humidity", value: snapshot.current.humidity.map { MenuBarFormatter.percent($0, decimals: false) } ?? "—")
            Divider().frame(height: 28).padding(.horizontal, PocketSpacing.s)
            metric("Rüzgâr", symbol: "wind", value: snapshot.current.windSpeed.map { String(localized: "\(MenuBarFormatter.number($0 * 3.6, fractionDigits: 1)) km/sa") } ?? "—")
            Divider().frame(height: 28).padding(.horizontal, PocketSpacing.s)
            metric("Basınç", symbol: "barometer", value: snapshot.current.pressure.map { String(localized: "\(MenuBarFormatter.number($0, fractionDigits: 0)) hPa") } ?? "—")
        }.padding(PocketSpacing.s)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: PocketRadius.medium))
    }
    private func metric(_ title: LocalizedStringKey, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary).labelStyle(.titleOnly)
            Text(verbatim: value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func hourly(_ hours: [WeatherHour], snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    HStack {
                        Text("Saatlik Tahmin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { moveHours(-1, hours: hours, proxy: proxy) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                            .buttonStyle(.plain).disabled(!hourViewport.canGoBack)
                            .help("Önceki Saatler").accessibilityLabel("Önceki Saatler").weatherAuditTarget("weather.hours.previous")
                        Button { moveHours(1, hours: hours, proxy: proxy) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
                            .buttonStyle(.plain).disabled(!hourViewport.canGoForward)
                            .help("Sonraki Saatler").accessibilityLabel("Sonraki Saatler").weatherAuditTarget("weather.hours.next")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PocketSpacing.s) {
                            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                                Button { selectedHourID = hour.id } label: {
                                    VStack(spacing: 6) {
                                        Text(date(hour.time, snapshot: snapshot, pattern: "HH")).font(.caption2).foregroundStyle(.secondary)
                                        WeatherConditionSymbol(symbol: hour.symbol, size: 17).frame(height: 20)
                                        Text(temperature(hour.temperature)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    }.frame(width: 42).padding(.vertical, 6)
                                        .background(selectedHourID == hour.id ? Color.accentColor.opacity(0.13) : index == 0 ? Color.primary.opacity(0.045) : .clear,
                                                    in: RoundedRectangle(cornerRadius: PocketRadius.small))
                                        .contentShape(RoundedRectangle(cornerRadius: PocketRadius.small))
                                }.buttonStyle(.plain).id(hour.id)
                                    .accessibilityLabel(date(hour.time, snapshot: snapshot, pattern: "EEE d MMM, HH:mm"))
                                    .accessibilityValue(temperature(hour.temperature) + "C")
                                    .accessibilityAddTraits(selectedHourID == hour.id ? .isSelected : [])
                                    .help("Saatin Tahminini Göster").weatherAuditTarget("weather.hour." + String(hour.id))
                            }
                        }
                    }.onScrollGeometryChange(for: WeatherHourViewport.self) { geometry in
                        .init(offset: geometry.visibleRect.minX, width: geometry.visibleRect.width, contentWidth: geometry.contentSize.width)
                    } action: { _, value in hourViewport = value }
                }
                .onChange(of: hours.map(\.id)) {
                    selectedHourID = nil
                    if let first = hours.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
                .onChange(of: service.activeSource) {
                    selectedHourID = nil
                    if let first = hours.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
            if let hour = hours.first(where: { $0.id == selectedHourID }) {
                HStack(spacing: PocketSpacing.m) {
                    WeatherConditionSymbol(symbol: hour.symbol, size: 24)
                    VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                        Text(date(hour.time, snapshot: snapshot, pattern: "EEE d MMM, HH:mm")).font(.caption).foregroundStyle(.secondary)
                        Text(temperature(hour.temperature) + "C").font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    Button { selectedHourID = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).help("Saat Ayrıntısını Kapat").accessibilityLabel("Saat Ayrıntısını Kapat").weatherAuditTarget("weather.hour-close")
                }.padding(PocketSpacing.s)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: PocketRadius.small))
                    .weatherAuditTarget("weather.hour-detail")
            }
        }
    }
    private func moveHours(_ direction: Int, hours: [WeatherHour], proxy: ScrollViewProxy) {
        guard !hours.isEmpty else { return }
        let stride = 42 + PocketSpacing.s
        let first = Int(max(0, hourViewport.offset) / stride)
        let page = max(1, Int(hourViewport.width / stride) - 1)
        let index = min(hours.count - 1, max(0, first + direction * page))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { proxy.scrollTo(hours[index].id, anchor: .leading) }
    }
    private func daily(_ days: [WeatherDay], snapshot: WeatherSnapshot) -> some View {
        let minimum = days.compactMap(\.low).min() ?? 0, maximum = days.compactMap(\.high).max() ?? 1
        return VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Text("Günlük Tahmin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(days) { day in
                HStack(spacing: PocketSpacing.s) {
                    Text(dayName(day, snapshot: snapshot)).font(.system(size: 12, weight: .medium)).frame(width: 42, alignment: .leading)
                    WeatherConditionSymbol(symbol: day.icon?.symbol ?? "thermometer.medium", size: 14).frame(width: 24)
                    Text(temperature(day.low)).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    WeatherTemperatureRange(low: day.low, high: day.high, minimum: minimum, maximum: maximum)
                    Text(temperature(day.high)).frame(width: 30, alignment: .trailing)
                }.font(.system(size: 12)).monospacedDigit().frame(height: 23).accessibilityElement(children: .combine)
            }
            if [.metNorway, .openWeather].contains(service.activeSource) {
                Text("Aralıklar tahmin örneklerinden hesaplanır.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var sourceFooter: some View {
        HStack(alignment: .center, spacing: PocketSpacing.s) {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Menu {
                    ForEach(service.basket.orderedSources) { source in
                        Button { service.selectSource(source) } label: {
                            if source == service.activeSource { Label(source.localizedTitle, systemImage: "checkmark") }
                            else { Text(source.localizedTitle) }
                        }
                    }
                    Divider()
                    Button("Kaynak Sepetini Düzenle") { settings = true }
                } label: {
                    Text(service.activeSource.localizedTitle).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Veri Kaynağı").accessibilityValue(service.activeSource.localizedTitle).help("Veri Kaynağı")
                HStack(spacing: PocketSpacing.s) {
                    if let snapshot = service.snapshot {
                        Text(snapshot.fetchedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                            .help("Son başarılı güncelleme")
                        ForEach(Array(snapshot.attributions.enumerated()), id: \.offset) { _, attribution in
                            if let url = attribution.url { Link(attribution.title, destination: url).font(.caption2).buttonStyle(.borderless) }
                        }
                    } else { Text("Henüz veri yok").font(.caption2).foregroundStyle(.secondary) }
                }.lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Button { service.refresh(manual: true) } label: {
                    if service.loading { ProgressView().controlSize(.mini).frame(width: 28, height: 28) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 13)).frame(width: 28, height: 28) }
                }.buttonStyle(.plain).disabled(!service.canRefresh).accessibilityLabel("Yenile")
                    .help(service.activeSource == .metNorway ? String(localized: "Üç saatte bir otomatik yenilenir.") : String(localized: "Saatte bir otomatik yenilenir."))
            }
        }
    }
    private func emptyState<Actions: View>(_ title: LocalizedStringKey, message: String, symbol: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, PocketSpacing.xl)
    }
    private func temperature(_ value: Double?) -> String { value.map { MenuBarFormatter.number($0, fractionDigits: 0) + "°" } ?? "—" }
    private func date(_ timestamp: Double, snapshot: WeatherSnapshot, pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = pocketLocale; formatter.timeZone = snapshot.timeZone; formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
    private func dayName(_ day: WeatherDay, snapshot: WeatherSnapshot) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = snapshot.timeZone
        return calendar.isDate(Date(timeIntervalSince1970: day.start), inSameDayAs: Date()) ? String(localized: "Bugün") : date(day.start, snapshot: snapshot, pattern: "EEE")
    }
}

private struct WeatherHourViewport: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0
    var contentWidth: CGFloat = 0
    var canGoBack: Bool { offset > 1 }
    var canGoForward: Bool { width > 0 && offset + width < contentWidth - 1 }
}

private struct WeatherConditionSymbol: View {
    let symbol: String
    let size: CGFloat
    private var accent: Color {
        if symbol.contains("sun") || symbol.contains("bolt") { return .orange }
        if symbol.contains("moon") { return .indigo }
        if symbol.contains("rain") { return .blue }
        if symbol.contains("snow") || symbol.contains("sleet") { return .cyan }
        return .secondary
    }
    var body: some View {
        Image(systemName: symbol).symbolRenderingMode(.palette)
            .foregroundStyle(symbol.contains("cloud") ? Color.primary.opacity(0.6) : accent, accent)
            .font(.system(size: size, weight: .regular)).accessibilityHidden(true)
    }
}

private struct WeatherTemperatureRange: View {
    let low: Double?, high: Double?, minimum: Double, maximum: Double
    var body: some View {
        GeometryReader { geometry in
            let span = max(1, maximum - minimum)
            let start = min(1, max(0, ((low ?? minimum) - minimum) / span)) * geometry.size.width
            let end = min(1, max(0, ((high ?? minimum) - minimum) / span)) * geometry.size.width
            let width = min(geometry.size.width, max(3, end - start))
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.06))
                if low != nil && high != nil {
                    Capsule().fill(LinearGradient(colors: [.cyan, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width).offset(x: min(start, geometry.size.width - width))
                }
            }
        }.frame(height: 4).accessibilityHidden(true)
    }
}
