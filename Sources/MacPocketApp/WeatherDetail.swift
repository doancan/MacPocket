import AppKit
import MacPocketCore
import MapKit
import SwiftUI

@MainActor
struct WeatherLocationPicker: View {
    @ObservedObject var service: WeatherService = .shared
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
