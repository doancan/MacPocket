import Darwin
import Foundation

/// Every entry is a fixed query. User text is never passed to a shell or command.
public enum MacUtility: String, CaseIterable, Identifiable, Sendable {
    case timeMachine, launchJobs, listeningPorts, diskInfo, diskLayout, spotlight
    case dns, routes, updateHistory, systemIntegrity, gatekeeper
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .timeMachine: "Time Machine Anlık Görüntüleri"
        case .launchJobs: "Oturum Görevleri"
        case .listeningPorts: "Dinleyen Bağlantı Noktaları"
        case .diskInfo: "Başlangıç Diski Bilgisi"
        case .diskLayout: "Disk ve Bölüm Haritası"
        case .spotlight: "Spotlight Durumu"
        case .dns: "DNS Çözümleyicileri"
        case .routes: "Ağ Yolları"
        case .updateHistory: "macOS Güncelleme Geçmişi"
        case .systemIntegrity: "Sistem Bütünlüğü"
        case .gatekeeper: "Gatekeeper Durumu"
        }
    }
    public var category: String {
        switch self {
        case .timeMachine, .diskInfo, .diskLayout, .spotlight: "Disk ve Arama"
        case .listeningPorts, .dns, .routes: "Ağ"
        case .systemIntegrity, .gatekeeper: "Güvenlik"
        case .launchJobs, .updateHistory: "Sistem"
        }
    }
    public var symbol: String {
        switch self {
        case .timeMachine: "clock.arrow.circlepath"
        case .launchJobs: "gearshape.2"
        case .listeningPorts: "network"
        case .diskInfo, .diskLayout: "internaldrive"
        case .spotlight: "magnifyingglass"
        case .dns: "server.rack"
        case .routes: "point.3.connected.trianglepath.dotted"
        case .updateHistory: "arrow.triangle.2.circlepath"
        case .systemIntegrity, .gatekeeper: "checkmark.shield"
        }
    }
    public var detail: String {
        switch self {
        case .timeMachine: "Başlangıç diskindeki yerel Time Machine anlık görüntülerini listeler. Liste boş olabilir; yedekleme başlatılmaz ve görüntü silinmez."
        case .launchJobs: "Kendi kullanıcı oturumundaki launchd görevlerini PID ve son çıkış koduyla listeler. Tüm sistem servislerini kapsamaz."
        case .listeningPorts: "Kendi kullanıcının TCP dinleme soketlerini süreç ve adresleriyle gösterir. Diğer kullanıcıların süreçleri bu kapsamın dışındadır."
        case .diskInfo: "Başlangıç biriminin türünü, kapasitesini, APFS ve aygıt bilgilerini sorgular. SMART bilgisi yalnız macOS raporlarsa gösterilir."
        case .diskLayout: "macOS’un gördüğü fiziksel ve mantıksal diskleri, bölümleri ve kapsayıcıları listeler. Disk onarımı veya biçimlendirme yapılmaz."
        case .spotlight: "Başlangıç biriminde Spotlight indekslemesinin etkinlik durumunu sorgular. İndeks yeniden oluşturulmaz."
        case .dns: "Sistem DNS çözümleyicilerini ve arayüz kapsamlarını gösterir. DNS ayarı veya önbelleği değiştirilmez."
        case .routes: "IPv4 ve IPv6 yönlendirme tablolarını sayısal adreslerle gösterir. Ağ yapılandırması değiştirilmez."
        case .updateHistory: "macOS yazılım güncelleme geçmişini okur. Yeni sürüm aramaz veya güncelleme kurmaz; bunun için sistem ayarlarını açabilirsin."
        case .systemIntegrity: "Sistem Bütünlüğü Koruması’nın macOS tarafından bildirilen durumunu okur. Güvenlik politikası değiştirilmez."
        case .gatekeeper: "Gatekeeper değerlendirme durumunu sorgular. Tek başına zararlı yazılım taraması veya güvenlik garantisi değildir."
        }
    }
    var command: (String, [String]) {
        switch self {
        case .timeMachine: ("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        case .launchJobs: ("/bin/launchctl", ["list"])
        case .listeningPorts: ("/usr/sbin/lsof", ["-nP", "-a", "-u", String(getuid()), "-iTCP", "-sTCP:LISTEN"])
        case .diskInfo: ("/usr/sbin/diskutil", ["info", "/"])
        case .diskLayout: ("/usr/sbin/diskutil", ["list"])
        case .spotlight: ("/usr/bin/mdutil", ["-s", "/"])
        case .dns: ("/usr/sbin/scutil", ["--dns"])
        case .routes: ("/usr/sbin/netstat", ["-rn"])
        case .updateHistory: ("/usr/sbin/softwareupdate", ["--history"])
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
