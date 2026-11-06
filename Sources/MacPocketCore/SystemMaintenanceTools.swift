import Darwin
import Foundation

/// Every entry is a fixed query. User text is never passed to a shell or command.
public enum MacUtility: String, CaseIterable, Identifiable, Sendable {
    case timeMachine, launchJobs, diskInfo, diskLayout, spotlight
    case dns, routes, systemIntegrity, gatekeeper
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .timeMachine: String(localized: "Time Machine Anlık Görüntüleri")
        case .launchJobs: String(localized: "Oturum Görevleri")
        case .diskInfo: String(localized: "Başlangıç Diski Bilgisi")
        case .diskLayout: String(localized: "Disk ve Bölüm Haritası")
        case .spotlight: String(localized: "Spotlight Durumu")
        case .dns: String(localized: "DNS Çözümleyicileri")
        case .routes: String(localized: "Ağ Yolları")
        case .systemIntegrity: String(localized: "Sistem Bütünlüğü")
        case .gatekeeper: String(localized: "Gatekeeper Durumu")
        }
    }
    public var category: String {
        switch self {
        case .timeMachine, .diskInfo, .diskLayout, .spotlight: String(localized: "Disk ve Arama")
        case .dns, .routes: String(localized: "Ağ")
        case .systemIntegrity, .gatekeeper: String(localized: "Güvenlik")
        case .launchJobs: String(localized: "Sistem")
        }
    }
    public var symbol: String {
        switch self {
        case .timeMachine: "clock.arrow.circlepath"
        case .launchJobs: "gearshape.2"
        case .diskInfo, .diskLayout: "internaldrive"
        case .spotlight: "magnifyingglass"
        case .dns: "server.rack"
        case .routes: "point.3.connected.trianglepath.dotted"
        case .systemIntegrity, .gatekeeper: "checkmark.shield"
        }
    }
    public var detail: String {
        switch self {
        case .timeMachine: String(localized: "Başlangıç diskindeki yerel Time Machine anlık görüntülerini listeler. Liste boş olabilir; yedekleme başlatılmaz ve görüntü silinmez.")
        case .launchJobs: String(localized: "Kendi kullanıcı oturumundaki launchd görevlerini PID ve son çıkış koduyla listeler. Tüm sistem servislerini kapsamaz.")
        case .diskInfo: String(localized: "Başlangıç biriminin türünü, kapasitesini, APFS ve aygıt bilgilerini sorgular. SMART bilgisi yalnız macOS raporlarsa gösterilir.")
        case .diskLayout: String(localized: "macOS’un gördüğü fiziksel ve mantıksal diskleri, bölümleri ve kapsayıcıları listeler. Disk onarımı veya biçimlendirme yapılmaz.")
        case .spotlight: String(localized: "Başlangıç biriminde Spotlight indekslemesinin etkinlik durumunu sorgular. İndeks yeniden oluşturulmaz.")
        case .dns: String(localized: "Sistem DNS çözümleyicilerini ve arayüz kapsamlarını gösterir. DNS ayarı veya önbelleği değiştirilmez.")
        case .routes: String(localized: "IPv4 ve IPv6 yönlendirme tablolarını sayısal adreslerle gösterir. Ağ yapılandırması değiştirilmez.")
        case .systemIntegrity: String(localized: "Sistem Bütünlüğü Koruması’nın macOS tarafından bildirilen durumunu okur. Güvenlik politikası değiştirilmez.")
        case .gatekeeper: String(localized: "Gatekeeper değerlendirme durumunu sorgular. Tek başına zararlı yazılım taraması veya güvenlik garantisi değildir.")
        }
    }
    var command: (String, [String]) {
        switch self {
        case .timeMachine: ("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        case .launchJobs: ("/bin/launchctl", ["list"])
        case .diskInfo: ("/usr/sbin/diskutil", ["info", "/"])
        case .diskLayout: ("/usr/sbin/diskutil", ["list"])
        case .spotlight: ("/usr/bin/mdutil", ["-s", "/"])
        case .dns: ("/usr/sbin/scutil", ["--dns"])
        case .routes: ("/usr/sbin/netstat", ["-rn"])
        case .systemIntegrity: ("/usr/bin/csrutil", ["status"])
        case .gatekeeper: ("/usr/sbin/spctl", ["--status"])
        }
    }
}

public enum MacUtilityService {
    public static func run(_ tool: MacUtility) async throws -> DiagnosticReport {
        let command = tool.command
        return try await run(tool, runner: SystemDiagnosticCommandRunner(executable: command.0, arguments: command.1))
    }
    static func run(_ tool: MacUtility, runner: SystemDiagnosticCommandRunner) async throws -> DiagnosticReport {
        do {
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try runner.execute() }.value
            } onCancel: { runner.cancel() }
            return report(tool, output: result.output, exit: result.exitCode, completion: .complete)
        } catch let SystemDiagnosticError.outputLimit(output) {
            return report(tool, output: output, exit: nil, completion: .outputLimit)
        } catch let SystemDiagnosticError.timedOut(output) {
            return report(tool, output: output, exit: nil, completion: .timedOut)
        }
    }
    private static func report(_ tool: MacUtility, output: String, exit: Int32?, completion: DiagnosticCompletion) -> DiagnosticReport {
        .init(id: tool.id, title: tool.title, capturedAt: Date(), output: output, exitCode: exit,
              completion: completion, partial: completion != .complete, truncated: completion == .outputLimit)
    }
}
