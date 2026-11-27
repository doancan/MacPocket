#if DEBUG
import AppKit
import MacPocketCore

/// `--audit-network <report.json>`: runs the Shortcuts actions and the diagnosis inside the real app process,
/// leaves the Tanılama tab on screen with its result for a screenshot, and writes what happened.
@MainActor
enum NetworkRuntimeAudit {
    static func run(destination: URL) async {
        var checks: [String: Bool] = [:]
        var details: [String: String] = [:]
        let model = PocketApplicationState.shared.model

        // Open MacPocket Page → Bağlantı Tanılama.
        let openIntent = OpenPocketPageIntent()
        openIntent.page = .connectionDiagnosis
        _ = try? await openIntent.perform()
        checks["openPageIntentNavigates"] = model.navigation.page == .network && model.navigation.networkTab == .diagnosis

        // Diagnose Connection, as Shortcuts would run it.
        let started = ContinuousClock.now
        let result = try? await DiagnoseConnectionIntent().perform()
        let elapsed = ContinuousClock.now - started
        checks["diagnoseIntentReturns"] = result != nil
        let diagnosis = ConnectionDiagnosisModel.shared
        if let measurement = diagnosis.measurement {
            let verdict = ConnectionDiagnosis.verdict(measurement)
            details["verdict"] = verdict.rawValue
            details["gateway"] = measurement.gateway ?? "-"
            details["router"] = measurement.router?.milliseconds.map { String(format: "%.1f", $0) } ?? "-"
            details["internet"] = measurement.internet.milliseconds.map { String(format: "%.1f", $0) } ?? "-"
            details["dns"] = measurement.dns.milliseconds.map { String(format: "%.1f", $0) } ?? "-"
            checks["measurementHasLink"] = measurement.hasLink
            checks["finishesWithinTenSeconds"] = elapsed < .seconds(10)
        } else {
            checks["measurementRecorded"] = false
        }
        details["elapsed"] = "\(elapsed)"
        checks["watchServiceRunning"] = ConnectionWatchService.shared.online != nil

        let report: [String: Any] = ["checks": checks, "details": details,
                                     "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination)
        }
    }
}
#endif
