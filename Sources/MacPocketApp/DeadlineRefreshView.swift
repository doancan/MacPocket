import SwiftUI

/// Updates once at the deadline; data changes recreate the schedule without periodic polling.
struct DeadlineRefreshView<Content: View>: View {
    let deadline: Date?
    @State private var date = Date()
    @ViewBuilder let content: (Date) -> Content
    var body: some View {
        content(date).task(id: deadline) {
            guard let deadline, deadline > date else { return }
            let delay = deadline.timeIntervalSinceNow
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            date = max(Date(), deadline)
        }
    }
}
