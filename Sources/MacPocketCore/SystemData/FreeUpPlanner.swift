import Foundation

public struct FreeUpPlan: Sendable, Equatable {
    public let selectedIDs: [String]
    public let selectedBytes: Int64
    public let targetBytes: Int64
    /// How far the best available selection falls short of the target; zero when the target is reached.
    public let shortfallBytes: Int64
    /// True when the plan had to reach into items marked Review.
    public let includesReview: Bool
    public var reachesTarget: Bool { shortfallBytes == 0 }
}

/// "I need 20 GB": picks the least worrying removable set that adds up to an amount.
///
/// Safe items go first, largest first so the fewest rows are touched; the Trash comes last because emptying it
/// cannot be undone. Review items are added only as far as needed, longest untouched first. Manual items are
/// never chosen. A Review item far larger than what is still needed is skipped while smaller ones can do the job, so
/// "20 GB" never selects a 188 GB build folder. When the target is out of reach only the Safe items are returned, with
/// the shortfall.
public enum FreeUpPlanner {
    public static func plan(items: [SystemDataItem], targetBytes: Int64, now: Date = Date()) -> FreeUpPlan {
        let target = max(0, targetBytes)
        let removable = items.filter { $0.isRemovable && $0.sizeBytes > 0 }

        let safe = removable.filter { $0.safety == .safe }.sorted {
            if ($0.group == .trash) != ($1.group == .trash) { return $1.group == .trash }
            return $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id
        }
        let review = removable.filter { $0.safety == .review }.sorted {
            let lhs = $0.idleDays(now: now) ?? -1, rhs = $1.idleDays(now: now) ?? -1
            if lhs != rhs { return lhs > rhs }
            return $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id
        }

        var chosen: [SystemDataItem] = []
        var total: Int64 = 0
        func take(_ pool: [SystemDataItem]) {
            for item in pool where total < target {
                chosen.append(item); total += item.sizeBytes
            }
        }
        take(safe)
        let safeOnly = chosen
        let safeTotal = total
        takeReview(review, target: target, chosen: &chosen, total: &total)

        guard total >= target else {
            return FreeUpPlan(selectedIDs: safeOnly.map(\.id), selectedBytes: safeTotal, targetBytes: target,
                              shortfallBytes: target - total, includesReview: false)
        }
        return FreeUpPlan(selectedIDs: chosen.map(\.id), selectedBytes: total, targetBytes: target,
                          shortfallBytes: 0, includesReview: chosen.contains { $0.safety == .review })
    }
}

extension FreeUpPlanner {
    /// How much larger than the remaining need a Review item may be before it is passed over.
    static let overshootFactor: Int64 = 3
    static let overshootFloor: Int64 = 1_000_000_000

    static func takeReview(_ review: [SystemDataItem], target: Int64, chosen: inout [SystemDataItem], total: inout Int64) {
        var unused: [SystemDataItem] = []
        for item in review {
            let remaining = target - total
            guard remaining > 0 else { return }
            if item.sizeBytes <= max(remaining * overshootFactor, overshootFloor) {
                chosen.append(item); total += item.sizeBytes
            } else {
                unused.append(item)
            }
        }
        // Still short: the smallest single item that closes the gap, otherwise whatever is left, longest untouched first.
        let remaining = target - total
        guard remaining > 0 else { return }
        if let fit = unused.filter({ $0.sizeBytes >= remaining }).min(by: { ($0.sizeBytes, $0.id) < ($1.sizeBytes, $1.id) }) {
            chosen.append(fit); total += fit.sizeBytes
            return
        }
        for item in unused where total < target { chosen.append(item); total += item.sizeBytes }
    }
}
