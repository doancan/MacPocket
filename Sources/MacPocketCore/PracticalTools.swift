import Foundation
import CryptoKit
import Security
import CoreImage
import ImageIO

public enum PracticalTool: String, CaseIterable, Identifiable, Sendable {
    case json, base64, url, jwt, hash, uuid, password, timestamp, diff, qr, caseConverter
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .json: String(localized: "JSON Düzenleyici")
        case .base64: String(localized: "Base64 Dönüştürücü")
        case .url: String(localized: "URL Kodlayıcı")
        case .jwt: String(localized: "JWT İnceleyici")
        case .hash: String(localized: "Hash Hesaplayıcı")
        case .uuid: String(localized: "UUID Üretici")
        case .password: String(localized: "Parola ve Token")
        case .timestamp: String(localized: "Unix Zaman Dönüştürücü")
        case .diff: String(localized: "Metin Karşılaştırma")
        case .qr: String(localized: "QR Oluşturucu")
        case .caseConverter: String(localized: "Harf Biçimleri (Case Converter)")
        }
    }
    public var detail: String {
        switch self {
        case .json: String(localized: "JSON sözdizimini kontrol et, okunabilir biçime getir veya küçült.")
        case .base64: String(localized: "UTF-8 metni standart veya URL uyumlu Base64 biçimine dönüştür.")
        case .url: String(localized: "Bir URL parametresini kodla veya yüzde kodlamasını çöz.")
        case .jwt: String(localized: "JWT başlığını, içeriğini ve bildirilen zaman aralığını incele.")
        case .hash: String(localized: "Metnin SHA-256 veya SHA-512 özetini hesapla.")
        case .uuid: String(localized: "Tek veya toplu UUID v4 kimlikleri oluştur.")
        case .password: String(localized: "Seçtiğin karakterlerle güvenli rastgele parola veya token üret.")
        case .timestamp: String(localized: "Unix saniye/milisaniye değerleri ile tarih arasında dönüşüm yap.")
        case .diff: String(localized: "İki metindeki eklenen, silinen ve aynı kalan satırları gör.")
        case .qr: String(localized: "Metin, bağlantı veya Wi-Fi bilgisi için QR oluştur ve PNG olarak kaydet.")
        case .caseConverter: String(localized: "Türkçe/İngilizce harf kurallarıyla 14 biçimi karşılaştır; kod adlarını ve çok satırlı metinleri dönüştür.")
        }
    }
    public var symbol: String {
        switch self {
        case .json: "curlybraces"
        case .base64: "arrow.left.arrow.right"
        case .url: "link"
        case .jwt: "doc.text.magnifyingglass"
        case .hash: "number"
        case .uuid: "barcode"
        case .password: "key"
        case .timestamp: "clock"
        case .diff: "text.badge.plus"
        case .qr: "qrcode"
        case .caseConverter: "textformat.abc"
        }
    }
    public var group: PracticalToolGroup {
        switch self {
        case .json, .base64, .url: .data
        case .jwt, .hash, .password: .security
        case .uuid, .qr: .generators
        case .timestamp: .date
        case .diff, .caseConverter: .text
        }
    }
}

public enum PracticalToolGroup: String, CaseIterable, Identifiable, Sendable {
    case data, security, generators, date, text
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .data: String(localized: "Veri ve Kodlama")
        case .security: String(localized: "İnceleme ve Güvenlik")
        case .generators: String(localized: "Üreticiler")
        case .date: String(localized: "Tarih ve Saat")
        case .text: String(localized: "Metin")
        }
    }
}

public enum PracticalToolError: Error, LocalizedError, Equatable {
    case empty, tooLarge, expandedJSON, json, base64, utf8, url, jwt, encryptedJWT, random, alphabet, length, count, date, diffSize, qrSize, qr, ssid, wifiPassword
    public var errorDescription: String? {
        switch self {
        case .empty: String(localized: "Önce bir girdi yaz veya Panodan Al ile metin ekle.")
        case .tooLarge: String(localized: "Girdi en fazla 256 KiB olabilir. Daha küçük bir metin kullan.")
        case .expandedJSON: String(localized: "Biçimlendirilmiş JSON çok büyük. Küçült seçeneğini kullan veya daha küçük bir bölüm dene.")
        case .json: String(localized: "JSON okunamadı. Tırnakları, virgülleri ve parantezleri kontrol et.")
        case .base64: String(localized: "Base64 okunamadı. Seçili alfabeyi, karakterleri ve sondaki = işaretlerini kontrol et.")
        case .utf8: String(localized: "Çözülen veri UTF-8 metin değil. Bu araç metin dönüştürmek içindir.")
        case .url: String(localized: "URL kodlaması okunamadı. Her % işaretinden sonra iki onaltılık rakam olmalı.")
        case .jwt: String(localized: "JWT okunamadı. Noktayla ayrılmış üç parçalı bir token ve JSON başlık/içerik kullan.")
        case .encryptedJWT: String(localized: "Şifreli JWT (JWE) desteklenmiyor. Bu araç üç parçalı JWT içeriğini çözümler.")
        case .random: String(localized: "Güvenli rastgele veri üretilemedi. Yeniden dene.")
        case .alphabet: String(localized: "En az bir karakter grubu seç.")
        case .length: String(localized: "Parola uzunluğu 8 ile 128 arasında olmalı.")
        case .count: String(localized: "UUID sayısı 1 ile 100 arasında olmalı.")
        case .date: String(localized: "Tarih okunamadı. Unix birimini kontrol et veya saat dilimi içeren ISO 8601 tarihi kullan.")
        case .diffSize: String(localized: "Her metin en fazla 2.000 satır olabilir. Daha küçük bir bölüm karşılaştır.")
        case .qrSize: String(localized: "QR içeriği en fazla 2.048 UTF-8 bayt olabilir. Metni kısalt.")
        case .qr: String(localized: "QR görüntüsü oluşturulamadı. Daha kısa bir içerikle yeniden dene.")
        case .wifiPassword: String(localized: "Parolalı ağ için Wi-Fi parolasını gir veya Parolasız ağ seçeneğini aç.")
        case .ssid: String(localized: "Wi-Fi ağ adı boş olamaz ve en fazla 32 UTF-8 bayt olabilir.")
        }
    }
}

public enum PracticalHash: String, CaseIterable, Identifiable, Sendable {
    case sha256, sha512
    public var id: String { rawValue }
    public var localizedTitle: String { self == .sha256 ? "SHA-256" : "SHA-512" }
}

public struct JWTInspection: Sendable {
    public let header: String
    public let payload: String
    public let expiration: Date?
    public let notBefore: Date?
    public let issuedAt: Date?
    public let timeDescription: String
}

public struct PracticalDiffLine: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable { case context, removed, added }
    public let id: Int
    public let kind: Kind
    public let text: String
    public var prefix: String {
        switch kind { case .context: " "; case .removed: "-"; case .added: "+" }
    }
}

public enum PracticalTools {
    public static let maximumInputBytes = 256 * 1024
    public static func validateSize(_ input: String) throws {
        guard input.utf8.count <= maximumInputBytes else { throw PracticalToolError.tooLarge }
    }
    private static func nonempty(_ input: String) throws {
        try validateSize(input)
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PracticalToolError.empty }
    }

    /// Validate with Foundation, then format the original tokens to preserve large numbers and key order.
    public static func json(_ input: String, compact: Bool = false) throws -> String {
        try nonempty(input)
        guard (try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])) != nil else {
            throw PracticalToolError.json
        }
        let bytes = Array(input.utf8)
        var result: [UInt8] = [], quoted = false, escaped = false, depth = 0
        result.reserveCapacity(bytes.count)
        func whitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
        func nextNonspace(_ index: Int) -> UInt8? { bytes.dropFirst(index + 1).first(where: { !whitespace($0) }) }
        func newline() { result.append(10); result.append(contentsOf: repeatElement(32, count: depth * 2)) }
        var previous: UInt8?
        for (index, byte) in bytes.enumerated() {
            guard result.count <= 4 * 1_024 * 1_024 else { throw PracticalToolError.expandedJSON }
            if quoted {
                result.append(byte)
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                continue
            }
            if whitespace(byte) { continue }
            if byte == 34 { quoted = true; result.append(byte) }
            else if byte == 123 || byte == 91 {
                result.append(byte); depth += 1
                if !compact, nextNonspace(index) != (byte == 123 ? 125 : 93) { newline() }
            } else if byte == 125 || byte == 93 {
                depth -= 1
                if !compact, previous != (byte == 125 ? 123 : 91) { newline() }
                result.append(byte)
            } else if byte == 44 {
                if let next = nextNonspace(index), next == 125 || next == 93 { throw PracticalToolError.json }
                result.append(byte); if !compact { newline() }
            } else if byte == 58 {
                result.append(byte); if !compact { result.append(32) }
            } else { result.append(byte) }
            previous = byte
        }
        return String(decoding: result, as: UTF8.self)
    }

    public static func base64(_ input: String, decode: Bool, urlSafe: Bool = false) throws -> String {
        try validateSize(input)
        if !decode {
            let encoded = Data(input.utf8).base64EncodedString()
            return urlSafe ? encoded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") : encoded
        }
        let text = input.filter { !$0.isWhitespace }
        let data = try decodeBase64(text, urlSafe: urlSafe)
        guard let decoded = String(data: data, encoding: .utf8) else { throw PracticalToolError.utf8 }
        return decoded
    }

    private static func decodeBase64(_ input: String, urlSafe: Bool) throws -> Data {
        let alphabet = urlSafe ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var body = input
        while body.last == "=" { body.removeLast() }
        let paddingCount = input.count - body.count
        guard paddingCount <= 2, body.allSatisfy({ alphabet.contains($0) }),
              (urlSafe || input.count.isMultiple(of: 4)),
              paddingCount == 0 || input.count.isMultiple(of: 4) else { throw PracticalToolError.base64 }
        var normalized = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized) else { throw PracticalToolError.base64 }
        let canonical = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
        guard canonical == body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") else { throw PracticalToolError.base64 }
        return data
    }

    public static func url(_ input: String, decode: Bool) throws -> String {
        try validateSize(input)
        if !decode {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        let bytes = Array(input.utf8)
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count, hex(bytes[index + 1]), hex(bytes[index + 2]) else { throw PracticalToolError.url }
        }
        guard let text = input.removingPercentEncoding else { throw PracticalToolError.url }
        return text
    }

    public static func jwt(_ input: String, at now: Date = Date()) throws -> JWTInspection {
        try nonempty(input)
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 5 { throw PracticalToolError.encryptedJWT }
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty,
              parts.allSatisfy({ !$0.contains("=") }),
              let header = try? decodeBase64(parts[0], urlSafe: true),
              let payload = try? decodeBase64(parts[1], urlSafe: true),
              (try? decodeBase64(parts[2], urlSafe: true)) != nil,
              let head = try? JSONSerialization.jsonObject(with: header) as? [String: Any],
              head["alg"] is String,
              let body = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let headerText = String(data: header, encoding: .utf8), let payloadText = String(data: payload, encoding: .utf8) else {
            throw PracticalToolError.jwt
        }
        func date(_ key: String) throws -> Date? {
            guard let value = body[key] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (-62_135_596_800...253_402_300_799).contains(number.doubleValue) else { throw PracticalToolError.jwt }
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        let expiration = try date("exp"), notBefore = try date("nbf"), issued = try date("iat")
        let status: String
        if let expiration, now >= expiration { status = String(localized: "Bildirilen sona erme zamanı geçmiş.") }
        else if let notBefore, now < notBefore { status = String(localized: "Bildirilen başlangıç zamanı henüz gelmemiş.") }
        else if expiration == nil { status = String(localized: "Token sona erme zamanı bildirmiyor.") }
        else { status = String(localized: "Bildirilen zaman aralığı içinde.") }
        return try JWTInspection(header: json(headerText), payload: json(payloadText), expiration: expiration,
                                 notBefore: notBefore, issuedAt: issued, timeDescription: status)
    }

    public static func hash(_ input: String, algorithm: PracticalHash) throws -> String {
        try validateSize(input)
        let data = Data(input.utf8)
        let digest = algorithm == .sha256 ? Array(SHA256.hash(data: data)) : Array(SHA512.hash(data: data))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func uuids(count: Int, uppercase: Bool = false) throws -> String {
        guard (1...100).contains(count) else { throw PracticalToolError.count }
        return (0..<count).map { _ in uppercase ? UUID().uuidString : UUID().uuidString.lowercased() }.joined(separator: "\n")
    }

    public static func password(length: Int, uppercase: Bool = true, lowercase: Bool = true,
                                digits: Bool = true, symbols: Bool = true) throws -> String {
        guard (8...128).contains(length) else { throw PracticalToolError.length }
        let groups = [(uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"), (lowercase, "abcdefghijklmnopqrstuvwxyz"),
                      (digits, "0123456789"), (symbols, "!@#$%^&*()-_=+[]{}:,.?")].filter(\.0).map { Array($0.1) }
        guard !groups.isEmpty else { throw PracticalToolError.alphabet }
        let pool = groups.flatMap { $0 }
        func randomIndex(_ count: Int) throws -> Int {
            let ceiling = (UInt64(UInt32.max) + 1) / UInt64(count) * UInt64(count)
            while true {
                var value: UInt32 = 0
                guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value) == errSecSuccess else { throw PracticalToolError.random }
                if UInt64(value) < ceiling { return Int(value % UInt32(count)) }
            }
        }
        var characters = try groups.map { $0[try randomIndex($0.count)] }
        while characters.count < length { characters.append(pool[try randomIndex(pool.count)]) }
        for index in stride(from: characters.count - 1, through: 1, by: -1) { characters.swapAt(index, try randomIndex(index + 1)) }
        return String(characters)
    }

    public static func timestamp(_ input: String, milliseconds: Bool) throws -> Date {
        try nonempty(input)
        guard let value = Double(input.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { throw PracticalToolError.date }
        let seconds = value / (milliseconds ? 1_000 : 1)
        guard (-62_135_596_800...253_402_300_799).contains(seconds) else { throw PracticalToolError.date }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func isoDate(_ input: String) throws -> Date {
        try nonempty(input)
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})\z"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { throw PracticalToolError.date }
        let bytes = Array(value.utf8)
        func number(_ start: Int, _ count: Int) -> Int { Int(String(decoding: bytes[start..<(start + count)], as: UTF8.self)) ?? -1 }
        let expected = [number(0, 4), number(5, 2), number(8, 2), number(11, 2), number(14, 2), number(17, 2)]
        let zone: TimeZone?
        if value.hasSuffix("Z") { zone = TimeZone(secondsFromGMT: 0) }
        else {
            let offset = Array(bytes.suffix(6))
            let hours = Int(String(decoding: offset[1...2], as: UTF8.self)) ?? 99
            let minutes = Int(String(decoding: offset[4...5], as: UTF8.self)) ?? 99
            guard hours <= 23, minutes <= 59 else { throw PracticalToolError.date }
            zone = TimeZone(secondsFromGMT: (offset[0] == 45 ? -1 : 1) * (hours * 3600 + minutes * 60))
        }
        guard let zone else { throw PracticalToolError.date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = formatter.date(from: value)
        if parsed == nil { formatter.formatOptions = [.withInternetDateTime]; parsed = formatter.date(from: value) }
        guard let date = parsed else { throw PracticalToolError.date }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard [actual.year, actual.month, actual.day, actual.hour, actual.minute, actual.second] == expected.map(Optional.init),
              (-62_135_596_800...253_402_300_799).contains(date.timeIntervalSince1970) else { throw PracticalToolError.date }
        return date
    }

    public static func unix(_ date: Date, milliseconds: Bool) throws -> String {
        let value = date.timeIntervalSince1970
        guard value.isFinite, (-62_135_596_800...253_402_300_799).contains(value) else { throw PracticalToolError.date }
        return String(Int64(floor(value * (milliseconds ? 1_000 : 1))))
    }

    public static func diff(_ before: String, _ after: String) throws -> [PracticalDiffLine] {
        try validateSize(before); try validateSize(after)
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        guard old.count <= 2_000, new.count <= 2_000 else { throw PracticalToolError.diffSize }
        let changes = new.difference(from: old)
        let removed = Set(changes.removals.map { change -> Int in if case .remove(let offset, _, _) = change { return offset }; return -1 })
        let inserted = Set(changes.insertions.map { change -> Int in if case .insert(let offset, _, _) = change { return offset }; return -1 })
        var result: [PracticalDiffLine] = [], i = 0, j = 0
        func append(_ kind: PracticalDiffLine.Kind, _ text: String) { result.append(.init(id: result.count, kind: kind, text: text)) }
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) { append(.removed, old[i]); i += 1 }
            else if j < new.count, inserted.contains(j) { append(.added, new[j]); j += 1 }
            else if i < old.count, j < new.count { append(.context, old[i]); i += 1; j += 1 }
            else { break }
        }
        return result
    }

    public static func wifiPayload(ssid: String, password: String, hidden: Bool, open: Bool) throws -> String {
        guard !ssid.isEmpty, ssid.utf8.count <= 32 else { throw PracticalToolError.ssid }
        guard open || !password.isEmpty else { throw PracticalToolError.wifiPassword }
        func escaped(_ text: String) -> String {
            text.reduce(into: "") { result, character in
                if "\\;,:\"".contains(character) { result.append("\\") }
                result.append(character)
            }
        }
        return "WIFI:T:\(open ? "nopass" : "WPA");S:\(escaped(ssid));P:\(open ? "" : escaped(password));H:\(hidden ? "true" : "false");;"
    }

    public static func qrPNG(_ input: String) throws -> Data {
        try nonempty(input)
        guard input.utf8.count <= 2_048 else { throw PracticalToolError.qrSize }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw PracticalToolError.qr }
        filter.setValue(Data(input.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { throw PracticalToolError.qr }
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let scale = floor(1_024 / extent.width)
        let image = code.composited(over: CIImage(color: CIColor.white)).cropped(to: extent)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(image, from: image.extent) else { throw PracticalToolError.qr }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw PracticalToolError.qr }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw PracticalToolError.qr }
        return data as Data
    }
}
