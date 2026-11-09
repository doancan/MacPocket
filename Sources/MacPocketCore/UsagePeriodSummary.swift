/// Shared period values for the screen-time cards and chart, rebuilt from the current snapshot.
public struct UsagePeriodSummary: Equatable, Sendable {
    public let dayTotals: [Double]
    public let hourTotals: [Double]
    public let total: Double
    public let activeDayCount: Int
    public let maximumDayTotal: Double
    public var average: Double { total / Double(activeDayCount) }

    public init(_ days: [UsageDay]) {
        dayTotals = days.map(\.total)
        hourTotals = UsageLedger.hourTotals(days)
        total = dayTotals.reduce(0, +)
        activeDayCount = max(1, dayTotals.filter { $0 > 0 }.count)
        maximumDayTotal = dayTotals.max() ?? 0
    }
}
