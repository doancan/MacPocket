import MacPocketCore

protocol FanTemperatureReading: Sendable {
    func celsius() async -> Double?
}

/// Serializes blocking HID reads away from the UI actor. The client is created only when a curve needs it.
actor FanTemperatureReader: FanTemperatureReading {
    private var reader: HottestTemperatureReader?
    private let readOverride: (@Sendable () -> Double?)?

    init(read: (@Sendable () -> Double?)? = nil) { readOverride = read }

    func celsius() -> Double? {
        if let readOverride { return readOverride() }
        if reader == nil { reader = HottestTemperatureReader() }
        return reader?.celsius()
    }
}
