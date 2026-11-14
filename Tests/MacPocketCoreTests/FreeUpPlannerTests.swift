import Foundation
import Testing
@testable import MacPocketCore

@Suite struct FreeUpPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let gigabyte: Int64 = 1_000_000_000

    private func item(_ id: String, gb: Int64, safety: SystemDataSafety = .safe, group: SystemDataGroup = .packages,
                      idleDays: Int? = nil, action: SystemDataAction = .removeFolder) -> SystemDataItem {
        SystemDataItem(id: id, group: group, title: id, detail: "", safety: safety, regeneration: .rebuildsLocally,
                       paths: ["/x/\(id)"], sizeBytes: gb * Self.gigabyte,
                       lastActivity: idleDays.map { now.addingTimeInterval(-Double($0) * 86_400) }, action: action)
    }

    @Test func safeItemsAreTakenLargestFirstAndStopAtTarget() {
        let plan = FreeUpPlanner.plan(items: [item("a", gb: 2), item("b", gb: 9), item("c", gb: 5)],
                                      targetBytes: 10 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["b", "c"])
        #expect(plan.reachesTarget && !plan.includesReview)
    }

    @Test func trashComesLastAmongSafeItems() {
        let plan = FreeUpPlanner.plan(items: [item("trash", gb: 50, group: .trash), item("cache", gb: 3)],
                                      targetBytes: 2 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["cache"])
    }

    @Test func reviewItemsAreAddedOnlyWhenNeededLongestUntouchedFirst() {
        let items = [item("safe", gb: 1), item("fresh", gb: 8, safety: .review, idleDays: 3),
                     item("stale", gb: 4, safety: .review, idleDays: 400)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 5 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["safe", "stale"])
        #expect(plan.includesReview)
    }

    @Test func unreachableTargetSelectsOnlySafeItemsAndReportsTheShortfall() {
        let items = [item("safe", gb: 2), item("review", gb: 3, safety: .review)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 20 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["safe"])
        #expect(plan.shortfallBytes == 15 * Self.gigabyte)
        #expect(!plan.reachesTarget && !plan.includesReview)
    }

    @Test func manualAndEmptyItemsAreNeverSelected() {
        let items = [item("manual", gb: 40, safety: .manual), item("hint", gb: 40, action: .manual(hint: "do it yourself")),
                     item("empty", gb: 0), item("ok", gb: 1)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 100 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["ok"])
    }

    @Test func zeroOrNegativeTargetSelectsNothing() {
        #expect(FreeUpPlanner.plan(items: [item("a", gb: 1)], targetBytes: 0, now: now).selectedIDs.isEmpty)
        #expect(FreeUpPlanner.plan(items: [item("a", gb: 1)], targetBytes: -5, now: now).reachesTarget)
    }

    @Test func orderingIsDeterministicForEqualSizes() {
        let plan = FreeUpPlanner.plan(items: [item("b", gb: 1), item("a", gb: 1)], targetBytes: 2 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["a", "b"])
    }

    @Test func aHugeIdleReviewItemIsSkippedWhileSmallerOnesCanDoTheJob() {
        let items = [item("huge", gb: 188, safety: .review, idleDays: 900), item("a", gb: 12, safety: .review, idleDays: 100),
                     item("b", gb: 9, safety: .review, idleDays: 50)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 20 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs == ["a", "b"])
        #expect(plan.selectedBytes == 21 * Self.gigabyte)
    }

    @Test func whenOnlyAHugeItemCanReachTheTargetItIsTheOneChosen() {
        let items = [item("huge", gb: 188, safety: .review, idleDays: 900), item("small", gb: 2, safety: .review, idleDays: 10)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 20 * Self.gigabyte, now: now)
        #expect(plan.reachesTarget)
        #expect(plan.selectedIDs.contains("huge"))
    }

    @Test func theSmallestSufficientSingleItemWinsAmongOversizedOnes() {
        let items = [item("big", gb: 90, safety: .review, idleDays: 900), item("bigger", gb: 300, safety: .review, idleDays: 800),
                     item("tiny", gb: 1, safety: .review, idleDays: 5)]
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 20 * Self.gigabyte, now: now)
        #expect(plan.selectedIDs.contains("big") && !plan.selectedIDs.contains("bigger"))
    }
}
