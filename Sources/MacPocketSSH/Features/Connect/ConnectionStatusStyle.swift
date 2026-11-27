import SSHConfigKit
import SwiftUI

struct ConnectionStatusStyle {
    let symbol: String
    let tint: Color
    let title: String

    static func style(for status: ConnectionStatus) -> ConnectionStatusStyle {
        switch status {
        case .reachable: .init(symbol: "checkmark.circle.fill", tint: .green, title: String(localized: "SSH.status.reachable", defaultValue: "Erişilebilir"))
        case .authenticationRequired: .init(symbol: "key.fill", tint: .yellow, title: String(localized: "SSH.status.authenticationRequired", defaultValue: "Kimlik doğrulama gerekli"))
        case .hostKeyChanged: .init(symbol: "exclamationmark.shield.fill", tint: .red, title: String(localized: "SSH.status.hostKeyChanged", defaultValue: "Host anahtarı değişmiş"))
        case .unknownHostKey: .init(symbol: "questionmark.circle.fill", tint: .yellow, title: String(localized: "SSH.status.unknownHostKey", defaultValue: "Bilinmeyen host anahtarı"))
        case .timeout: .init(symbol: "clock.badge.xmark", tint: .red, title: String(localized: "SSH.status.timeout", defaultValue: "Zaman aşımı"))
        case .dnsFailure: .init(symbol: "network.slash", tint: .red, title: String(localized: "SSH.status.dnsFailure", defaultValue: "Sunucu adı bulunamadı"))
        case .connectionRefused: .init(symbol: "xmark.octagon.fill", tint: .red, title: String(localized: "SSH.status.connectionRefused", defaultValue: "Bağlantı reddedildi"))
        case .other: .init(symbol: "exclamationmark.circle.fill", tint: .secondary, title: String(localized: "SSH.status.other", defaultValue: "Bağlantı başarısız"))
        }
    }

    static var testing: ConnectionStatusStyle {
        .init(symbol: "ellipsis.circle", tint: .secondary, title: String(localized: "SSH.status.testing", defaultValue: "Test ediliyor…"))
    }
}
