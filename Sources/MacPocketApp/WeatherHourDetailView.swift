import MacPocketCore
import SwiftUI

struct WeatherHourDetailView: View {
    let hour: WeatherHour
    let snapshot: WeatherSnapshot
    let chooseSource: () -> Void

    private struct Field: Identifiable {
        let id: String
        let title: String
        let value: String
        var note: String? = nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Text(date("EEEE d MMMM")).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                        Text(date("HH:mm")).font(.title2.weight(.semibold)).monospacedDigit()
                        Text(hour.temperature.map { MenuBarFormatter.number($0, fractionDigits: 0) + "°C" } ?? "—")
                            .font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    WeatherConditionSymbol(symbol: hour.symbol, size: 42)
                }
                if let condition = hour.icon?.localizedDescription { Text(condition).font(.callout).foregroundStyle(.secondary) }
            }
            if fields.isEmpty {
                Text("Bu kaynak bu saat için sıcaklık dışında ayrıntı sunmuyor. Başka bir kaynak seçebilirsin.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .weatherAuditTarget("weather.hour-no-details")
                Button("Kaynakları Düzenle", action: chooseSource).controlSize(.small)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading,
                          spacing: PocketSpacing.m) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                            Text(field.title).font(.caption).foregroundStyle(.secondary)
                            Text(field.value).font(.callout.weight(.semibold)).monospacedDigit()
                            if let note = field.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                            .padding(.bottom, PocketSpacing.s).overlay(alignment: .bottom) { Divider() }
                            .accessibilityElement(children: .combine).weatherAuditTarget("weather.hour-field." + field.id)
                    }
                }
                Text("Yalnız seçili kaynağın bu saate ait verileri gösterilir. Sunulmayan alanlar gösterilmez.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var fields: [Field] {
        var fields: [Field] = []
        func add(_ id: String, _ title: String, _ value: Double?, format: (Double) -> String, note: String? = nil) {
            if let value { fields.append(.init(id: id, title: title, value: format(value), note: note)) }
        }
        let percent: (Double) -> String = { MenuBarFormatter.percent($0, decimals: false) }
        let degrees: (Double) -> String = { MenuBarFormatter.number($0, fractionDigits: 1) + "°C" }
        let speed: (Double) -> String = { String(localized: "\(MenuBarFormatter.number($0 * 3.6, fractionDigits: 1)) km/sa") }
        let millimeters: (Double) -> String = { String(localized: "\(MenuBarFormatter.number($0, fractionDigits: 1)) mm") }
        add("probability", String(localized: "Yağış Olasılığı"), hour.precipitationProbability, format: percent)
        add("precipitation", String(localized: "Yağış Miktarı"), hour.precipitation, format: millimeters, note: precipitationPeriod)
        add("rain-probability", String(localized: "Yağmur Olasılığı"), hour.rainProbability, format: percent)
        add("snow-probability", String(localized: "Kar Olasılığı"), hour.snowProbability, format: percent)
        add("intensity", hour.intensityIsRainOnly == true ? String(localized: "Yağmur Şiddeti") : String(localized: "Yağış Şiddeti"), hour.precipitationIntensity,
            format: { String(localized: "\(MenuBarFormatter.number($0, fractionDigits: 1)) mm/sa") })
        add("apparent", String(localized: "Hissedilen"), hour.apparent, format: degrees)
        add("humidity", String(localized: "Nem"), hour.humidity, format: percent)
        add("wind", String(localized: "Rüzgâr"), hour.windSpeed, format: speed)
        add("gust", String(localized: "Rüzgâr Hamlesi"), hour.windGust, format: speed)
        add("direction", String(localized: "Rüzgâr Yönü"), hour.windDirection, format: direction)
        add("pressure", String(localized: "Basınç"), hour.pressure, format: { String(localized: "\(MenuBarFormatter.number($0, fractionDigits: 0)) hPa") })
        add("cloud", String(localized: "Bulut Örtüsü"), hour.cloudCover, format: percent)
        add("visibility", String(localized: "Görüş Mesafesi"), hour.visibility, format: { String(localized: "\(MenuBarFormatter.number($0 / 1_000, fractionDigits: 1)) km") })
        add("uv", String(localized: "UV İndeksi"), hour.uvIndex, format: { MenuBarFormatter.number($0, fractionDigits: 1) })
        add("clear-sky-uv", String(localized: "UV · Açık Gökyüzü"), hour.clearSkyUVIndex, format: { MenuBarFormatter.number($0, fractionDigits: 1) })
        add("dew", String(localized: "Çiy Noktası"), hour.dewPoint, format: degrees)
        return fields
    }
    private var precipitationPeriod: String? {
        guard let hours = hour.precipitationHours else { return nil }
        switch hour.precipitationTiming {
        case .preceding: return String(localized: "Önceki \(hours) saat")
        case .following: return String(localized: "Sonraki \(hours) saat")
        case nil: return String(localized: "\(hours) saatlik toplam")
        }
    }
    private func direction(_ degrees: Double) -> String {
        let names = [String(localized: "Kuzey"), String(localized: "Kuzeydoğu"), String(localized: "Doğu"), String(localized: "Güneydoğu"),
                     String(localized: "Güney"), String(localized: "Güneybatı"), String(localized: "Batı"), String(localized: "Kuzeybatı")]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return MenuBarFormatter.number(degrees, fractionDigits: 0) + "° · " + names[index]
    }
    private func date(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = pocketLocale
        formatter.timeZone = snapshot.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: hour.time))
    }
}
