import Foundation
import SSHConfigKit

/// Turns the package's typed results into localized, user-facing text.
enum Messages {
    static func text(for issue: DraftIssue) -> String {
        switch issue {
        case .controlCharacter(let field): String(localized: "SSH.issue.controlCharacter %@", defaultValue: "“\(field)” satır sonu veya kontrol karakteri içeriyor.")
        case .emptyAlias: String(localized: "SSH.issue.emptyAlias", defaultValue: "Alias boş olamaz.")
        case .aliasHasWhitespace: String(localized: "SSH.issue.aliasHasWhitespace", defaultValue: "Alias boşluk içeremez.")
        case .duplicateAlias(let alias): String(localized: "SSH.issue.duplicateAlias %@", defaultValue: "“\(alias)” başka bir host tarafından kullanılıyor.")
        case .invalidPort(let port): String(localized: "SSH.issue.invalidPort %@", defaultValue: "“\(port)” geçerli bir port değil (1–65535).")
        case .invalidDirectiveKey(let key): String(localized: "SSH.issue.invalidDirectiveKey %@", defaultValue: "“\(key)” geçerli bir seçenek adı değil.")
        case .forbiddenDirectiveKey(let key): String(localized: "SSH.issue.forbiddenDirectiveKey %@", defaultValue: "“\(key)” burada seçenek olarak eklenemez.")
        case .emptyDirectiveValue(let key): String(localized: "SSH.issue.emptyDirectiveValue %@", defaultValue: "“\(key)” için bir değer gerekli.")
        case .valueStartsComment(let key): String(localized: "SSH.issue.valueStartsComment %@", defaultValue: "“\(key)” değerinde bir sözcüğün başında “#” var; ssh gerisini yorum olarak okur. O kısmı çift tırnak içine alın.")
        case .duplicateAliasCaseOnly(let alias): String(localized: "SSH.issue.lint.duplicateCaseOnly %@", defaultValue: "“\(alias)” başka bir Host bloğundan yalnızca büyük/küçük harfle ayrılıyor; ssh bunları farklı hostlar sayar.")
        case .identityFileMissing(let path): String(localized: "SSH.issue.identityFileMissing %@", defaultValue: "Anahtar dosyası bulunamadı: \(path)")
        case .duplicateFieldKey(let key): String(localized: "SSH.issue.duplicateFieldKey %@", defaultValue: "\(key) birden fazla kez geçiyor. ssh dosyadaki ilk değeri kullanır; bu, yukarıdaki alandaki değer olmayabilir.")
        }
    }

    static func text(for issue: HostIssue) -> String {
        switch issue {
        case .missingIdentityFile(let path): String(localized: "SSH.issue.lint.missingIdentityFile %@", defaultValue: "IdentityFile bulunamadı: \(path)")
        case .duplicateAlias(let alias, let isFirst):
            isFirst ? String(localized: "SSH.issue.lint.duplicateFirst %@", defaultValue: "“\(alias)” sonraki Host bloklarında da var; onlar yalnızca bu blokta olmayan ayarları ekler.") : String(localized: "SSH.issue.lint.duplicateLater %@", defaultValue: "“\(alias)” daha önceki bir Host bloğunda zaten tanımlı; oradaki değerler bu bloğun önüne geçer.")
        case .duplicateAliasCaseOnly(let alias): String(localized: "SSH.issue.lint.duplicateCaseOnly %@", defaultValue: "“\(alias)” başka bir Host bloğundan yalnızca büyük/küçük harfle ayrılıyor; ssh bunları farklı hostlar sayar.")
        case .unencryptedKey(let path): String(localized: "SSH.issue.lint.unencryptedKey %@", defaultValue: "Parolasız özel anahtar: \(path)")
        }
    }

    static func text(for error: ConfigEditError) -> String {
        switch error {
        case .hostNotFound: String(localized: "SSH.edit.hostNotFound", defaultValue: "Bu host artık dosyada yok.")
        case .controlCharacter: String(localized: "SSH.edit.controlCharacter", defaultValue: "Değerler satır sonu veya kontrol karakteri içeremez.")
        case .invalidDirectiveKey(let key): text(for: DraftIssue.invalidDirectiveKey(key))
        case .forbiddenDirectiveKey(let key): text(for: DraftIssue.forbiddenDirectiveKey(key))
        case .invalidAlias(let alias): String(localized: "SSH.edit.invalidAlias %@", defaultValue: "“\(alias)” geçerli bir alias değil.")
        }
    }

    static func text(for error: ConfigStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "SSH.store.notEditable", defaultValue: "Dosya şu anki durumunda düzenlenemez.")
        case .conflict, .writeFailed(.conflict): String(localized: "SSH.store.conflict", defaultValue: "Dosya başka bir program tarafından değiştirildi.")
        case .validationFailed(let message): String(localized: "SSH.store.validationFailed %@", defaultValue: "ssh yapılandırmayı reddetti:\n\(message)")
        case .validationTimedOut: String(localized: "SSH.store.validationTimedOut", defaultValue: "ssh ile doğrulama zaman aşımına uğradı.")
        case .writeFailed(.backupFailed(let detail)): String(localized: "SSH.store.backupFailed %@", defaultValue: "Yedek oluşturulamadığı için hiçbir şey yazılmadı: \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "SSH.store.writeFailed %@", defaultValue: "Dosya yazılamadı: \(detail)")
        case .saveCancelled: String(localized: "SSH.store.saveCancelled", defaultValue: "Dosya yeniden yüklendiği için kaydetme iptal edildi.")
        case .saveInProgress: String(localized: "SSH.store.saveInProgress", defaultValue: "Zaten bir kaydetme işlemi sürüyor.")
        case .validatorUnavailable(let detail): String(localized: "SSH.store.validatorUnavailable %@", defaultValue: "Dosyayı doğrulamak için ssh çalıştırılamadı: \(detail)")
        }
    }

    static func text(for error: KnownHostsStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "SSH.knownHosts.notEditable", defaultValue: "Bu known_hosts dosyası değiştirilemez.")
        case .staleSelection: String(localized: "SSH.knownHosts.staleSelection", defaultValue: "known_hosts dosyası değişti. Liste yenilendi; kayıtları yeniden seçin.")
        case .conflict, .writeFailed(.conflict): String(localized: "SSH.knownHosts.conflict", defaultValue: "known_hosts dosyası başka bir program tarafından değiştirildi. Yeniden yüklendi ve hiçbir şey silinmedi.")
        case .writeFailed(.backupFailed(let detail)): String(localized: "SSH.store.backupFailed %@", defaultValue: "Yedek oluşturulamadığı için hiçbir şey yazılmadı: \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "SSH.store.writeFailed %@", defaultValue: "Dosya yazılamadı: \(detail)")
        }
    }

    /// known_hosts load states: a missing file is normal (ssh creates it), not an error.
    static func knownHostsLoadText(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "SSH.knownHosts.missing", defaultValue: "Henüz known_hosts dosyası yok. ssh ilk bağlantıda oluşturur.")
        case .notUTF8: String(localized: "SSH.knownHosts.notUTF8", defaultValue: "known_hosts dosyası geçerli UTF-8 değil. Kayıtları gösterilemez ve dosya hiçbir zaman yeniden yazılmaz.")
        case .unreadable(let detail): String(localized: "SSH.knownHosts.unreadable %@", defaultValue: "known_hosts dosyası okunamadı: \(detail)")
        }
    }

    static func text(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "SSH.load.missing", defaultValue: "Config dosyası henüz yok.")
        case .notUTF8: String(localized: "SSH.load.notUTF8", defaultValue: "Dosya geçerli UTF-8 değil. Salt okunur gösteriliyor ve asla yeniden yazılmayacak.")
        case .unreadable(let detail): String(localized: "SSH.load.unreadable %@", defaultValue: "Dosya okunamadı: \(detail)")
        }
    }

    static func text(for outcome: ValidationOutcome) -> String {
        switch outcome {
        case .valid: String(localized: "SSH.validation.valid", defaultValue: "ssh bu yapılandırmayı kabul ediyor.")
        case .invalid(let message): text(for: ConfigStoreError.validationFailed(message))
        case .timedOut: text(for: ConfigStoreError.validationTimedOut)
        case .validatorUnavailable(let detail): text(for: ConfigStoreError.validatorUnavailable(detail))
        }
    }

    static func text(for error: HostResolverError) -> String {
        switch error {
        case .failed(let detail): String(localized: "SSH.hostKeyRemoval.resolveFailed %@", defaultValue: "ssh bu host'u çözümleyemedi: \(detail)")
        case .timedOut: String(localized: "SSH.hostKeyRemoval.resolveTimedOut", defaultValue: "ssh -G 5 saniye içinde yanıt vermedi.")
        case .unparsable: String(localized: "SSH.hostKeyRemoval.resolveUnparsable", defaultValue: "ssh -G okunamayan bir çıktı verdi.")
        }
    }


    static func text(for error: KeyManagerError) -> String {
        switch error {
        case .fileExists(let path): String(localized: "SSH.keys.error.fileExists %@", defaultValue: "\(path) konumunda zaten bir dosya var. Hiçbir şeyin üzerine yazılmadı.")
        case .passphraseTooShort: String(localized: "SSH.keys.error.passphraseTooShort", defaultValue: "Parola kullanmayın ya da en az 5 karakter kullanın.")
        case .invalidPassphrase: String(localized: "SSH.keys.error.invalidPassphrase", defaultValue: "Parola satır sonu içeremez.")
        case .wrongPassphrase: String(localized: "SSH.keys.error.wrongPassphrase", defaultValue: "Parola doğru değil.")
        case .passphraseRequired: String(localized: "SSH.keys.error.passphraseRequired", defaultValue: "Bu anahtar şifreli; parola gerekiyor.")
        case .noAgent: String(localized: "SSH.keys.error.noAgent", defaultValue: "ssh-agent çalışmıyor ya da erişilemiyor.")
        case .timedOut: String(localized: "SSH.keys.error.timedOut", defaultValue: "İşlem 30 saniye içinde bitmedi.")
        case .failed(let detail): String(localized: "SSH.keys.error.failed %@", defaultValue: "ssh şunu bildirdi: \(detail)")
        }
    }

    static func text(for error: any Error) -> String {
        if let error = error as? ConfigStoreError { return text(for: error) }
        if let error = error as? ConfigEditError { return text(for: error) }
        if let error = error as? KnownHostsStoreError { return text(for: error) }
        if let error = error as? HostResolverError { return text(for: error) }
        if let error = error as? KeyManagerError { return text(for: error) }
        if let error = error as? KeyAssignmentError {
            switch error {
            case .hostNotFound(let alias): return String(localized: "SSH.keys.error.hostNotFound %@", defaultValue: "“\(alias)” host'u dosyada bulunamadı.")
            case .pendingFormEdits: return String(localized: "SSH.keys.error.pendingFormEdits", defaultValue: "Önce host formundaki değişiklikleri uygulayın ya da vazgeçin.")
            }
        }
        let detail = error.localizedDescription
        return String(localized: "SSH.error.generic %@", defaultValue: "Beklenmeyen hata: \(detail)")
    }
}
