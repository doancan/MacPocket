import Foundation

/// Decides whether the night schedule's location may be refreshed (at most once per day).
public enum LocationRefreshPolicy {
    public static let minimumInterval: TimeInterval = 24 * 60 * 60

    public static func shouldFetch(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        let elapsed = now.timeIntervalSince(lastFetch)
        return elapsed < 0 || elapsed >= minimumInterval
    }
}
