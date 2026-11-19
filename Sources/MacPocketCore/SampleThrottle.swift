import Foundation

/// Reuses an expensive reading until it is `interval` old. For values that change slowly compared with the
/// monitoring tick, such as temperatures, which take one IOHID event per sensor to read.
struct SampleThrottle<Value> {
    let interval: TimeInterval
    private var last: (value: Value, at: Date)?

    init(interval: TimeInterval) { self.interval = interval }

    /// The cached reading while it is fresh; otherwise `read()`'s result, which is then cached.
    mutating func value(now: Date, read: () -> Value) -> Value {
        if let last, now.timeIntervalSince(last.at) < interval, now >= last.at { return last.value }
        let value = read()
        last = (value, now)
        return value
    }
}
