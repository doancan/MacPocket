import Foundation

extension SystemDataSummary {
    public init(report: SystemDataReport) {
        self.init(date: report.scannedAt, systemDataBytes: report.systemDataBytes, safeBytes: report.safeBytes,
                  freeBytes: report.freeBytes, purgeableBytes: report.purgeableBytes)
    }
}
