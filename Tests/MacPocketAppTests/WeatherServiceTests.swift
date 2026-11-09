import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

@MainActor private final class WeatherCredentialFixture: WeatherCredentialStoring {
    var values: [WeatherSource: String] = [:]
    var reads = 0, saves = 0
    var rejects = false
    func contains(_ source: WeatherSource) -> Bool { values[source] != nil }
    func read(_ source: WeatherSource) throws -> String? { reads += 1; return values[source] }
    func save(_ value: String?, for source: WeatherSource) throws {
        if rejects { throw WeatherCredentialError.unavailable }
        saves += 1; values[source] = value
    }
}
private actor WeatherFetchFixture {
    var sources: [WeatherSource] = []
    var keys: [String?] = []
    var holding: WeatherSource?
    var pending: CheckedContinuation<WeatherSnapshot, any Error>?
    var failure: WeatherSourceError?
    func setHolding(_ source: WeatherSource?) { holding = source }
    func setFailure(_ value: WeatherSourceError?) { failure = value }
    func count() -> Int { sources.count }
    func calledSources() -> [WeatherSource] { sources }
    func calledKeys() -> [String?] { keys }
    func fetch(_ source: WeatherSource, _ location: WeatherLocation, _ language: String, _ key: String?) async throws -> WeatherSnapshot {
        sources.append(source); keys.append(key)
        if source == holding { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }
        return try Self.snapshot(source, location)
    }
    static func snapshot(_ source: WeatherSource, _ location: WeatherLocation) throws -> WeatherSnapshot {
        try WeatherProviderClient.decode([Data(#"{"current":{"temperature_2m":12}}"#.utf8)], source: .openMeteo, location: location)
    }
    func release(_ location: WeatherLocation) throws {
        let value = try Self.snapshot(.visualCrossing, location)
        pending?.resume(returning: value); pending = nil
    }
}

@MainActor final class WeatherServiceTests: XCTestCase {
    private let location = WeatherLocation(name: "İstanbul", latitude: 41.0082, longitude: 28.9784)
    private func defaults() -> UserDefaults {
        let name = "com.doancan.MacPocket.WeatherTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    private func wait(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    private func service(_ defaults: UserDefaults, keys: WeatherCredentialFixture, fetch: WeatherFetchFixture,
                         now: @escaping () -> Date = Date.init) -> WeatherService {
        WeatherService(defaults: defaults, credentials: keys, now: now, client: { try await fetch.fetch($0, $1, $2, $3) })
    }
    func testBasketAndLocationPersistWithoutFetchingWhileDisabled() async throws {
        let preferences = defaults(), keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        let service = service(preferences, keys: keys, fetch: fetch)
        service.select(location); service.include(.gfs, included: true); service.selectSource(.gfs)
        let count = await fetch.count()
        XCTAssertEqual(count, 0); XCTAssertEqual(keys.reads, 0)
        let restored = self.service(preferences, keys: keys, fetch: fetch)
        XCTAssertEqual(restored.location, location); XCTAssertEqual(restored.basket, service.basket)
        XCTAssertEqual(restored.activeSource, .gfs)
    }
    func testExistingLocationKeepsLegacyUntilUserChoosesPublicSource() throws {
        let preferences = defaults(), keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        preferences.set(try JSONEncoder().encode(location), forKey: "MacPocket.weather.location")
        let service = service(preferences, keys: keys, fetch: fetch)
        XCTAssertEqual(service.activeSource, .istatLegacy)
        service.selectSource(.visualCrossing)
        XCTAssertEqual(self.service(preferences, keys: keys, fetch: fetch).activeSource, .visualCrossing)
    }
    func testOnlyChosenSourceFetchesAndSwitchingBackUsesSeparateCache() async throws {
        let keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        let service = service(defaults(), keys: keys, fetch: fetch)
        service.select(location); service.setEnabled(true)
        let first = await wait { service.snapshot?.source == .visualCrossing }; XCTAssertTrue(first)
        service.include(.gfs, included: true)
        service.selectSource(.metNorway)
        let second = await wait { service.snapshot?.source == .metNorway }; XCTAssertTrue(second)
        service.selectSource(.visualCrossing); service.refresh(manual: true)
        let sources = await fetch.calledSources()
        XCTAssertEqual(sources, [.visualCrossing, .metNorway])
        XCTAssertEqual(service.snapshot?.source, .visualCrossing)
        XCTAssertFalse(service.canRefresh); XCTAssertEqual(keys.reads, 0)
        service.setEnabled(false)
    }
    func testProviderMinimumIntervalsCannotBeBypassedByManualRefreshOrSwitching() async throws {
        let keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        var date = Date(timeIntervalSince1970: 1_794_182_400)
        let service = service(defaults(), keys: keys, fetch: fetch, now: { date })
        service.selectSource(.metNorway); service.select(location); service.setEnabled(true)
        let first = await wait { service.snapshot != nil }; XCTAssertTrue(first)
        date += 3_601; service.refresh(manual: true)
        var count = await fetch.count(); XCTAssertEqual(count, 1); XCTAssertFalse(service.canRefresh)
        service.selectSource(.visualCrossing)
        let second = await wait { service.snapshot?.source == .visualCrossing }; XCTAssertTrue(second)
        service.selectSource(.metNorway); service.refresh(manual: true)
        count = await fetch.count(); XCTAssertEqual(count, 2)
        date += 7_200; service.refresh(manual: true)
        let refreshed = await wait { await fetch.count() == 3 && !service.loading }; XCTAssertTrue(refreshed)
        service.setEnabled(false)
    }
    func testRefreshButtonUsesScheduledDateWithoutBypassingRequestLimits() async throws {
        let date = Date(timeIntervalSince1970: 1_794_182_400), fetch = WeatherFetchFixture()
        let service = service(defaults(), keys: WeatherCredentialFixture(), fetch: fetch, now: { date })
        service.select(location); service.setEnabled(true)
        let loaded = await wait { service.snapshot != nil }; XCTAssertTrue(loaded)
        let deadline = try XCTUnwrap(service.nextRefreshAt)
        XCTAssertFalse(service.canRefresh(at: deadline.addingTimeInterval(-0.001)))
        XCTAssertTrue(service.canRefresh(at: deadline))
        XCTAssertFalse(service.canRefresh)
        service.refresh(manual: true)
        let count = await fetch.count(); XCTAssertEqual(count, 1)
        service.setEnabled(false)
        XCTAssertFalse(service.canRefresh(at: .distantFuture))
    }
    func testFailureRetryDeadlineEnablesButtonBeforeAutomaticRefresh() async throws {
        var date = Date(timeIntervalSince1970: 1_794_182_400)
        let fetch = WeatherFetchFixture(); await fetch.setFailure(.unavailable)
        let service = service(defaults(), keys: WeatherCredentialFixture(), fetch: fetch, now: { date })
        service.select(location); service.setEnabled(true)
        let failed = await wait { service.error != nil && !service.loading }; XCTAssertTrue(failed)
        let deadline = try XCTUnwrap(service.nextRefreshAt)
        XCTAssertEqual(deadline.timeIntervalSince(date), 60)
        XCTAssertFalse(service.canRefresh(at: date))
        XCTAssertTrue(service.canRefresh(at: deadline))
        date = deadline; service.refresh(manual: true)
        let retried = await wait { await fetch.count() == 2 && !service.loading }; XCTAssertTrue(retried)
        service.setEnabled(false)
    }
    func testLatePreviousSourceResponseCannotOverwriteNewSource() async throws {
        let fetch = WeatherFetchFixture(); await fetch.setHolding(.visualCrossing)
        let service = service(defaults(), keys: WeatherCredentialFixture(), fetch: fetch)
        service.select(location); service.setEnabled(true)
        let started = await wait { await fetch.count() == 1 }; XCTAssertTrue(started)
        XCTAssertFalse(service.canRefresh(at: .distantFuture))
        service.selectSource(.metNorway)
        let changed = await wait { service.snapshot?.source == .metNorway }; XCTAssertTrue(changed)
        try await fetch.release(location)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(service.snapshot?.source, .metNorway); XCTAssertFalse(service.loading)
        service.setEnabled(false)
    }
    func testDisablingModuleRejectsLateResultAndDoesNotFetchNewSelection() async throws {
        let fetch = WeatherFetchFixture(); await fetch.setHolding(.visualCrossing)
        let service = service(defaults(), keys: WeatherCredentialFixture(), fetch: fetch)
        service.select(location); service.setEnabled(true)
        let started = await wait { await fetch.count() == 1 }; XCTAssertTrue(started)
        service.setEnabled(false); try await fetch.release(location)
        service.selectSource(.gfs); service.refresh(manual: true)
        try await Task.sleep(for: .milliseconds(30))
        let count = await fetch.count()
        XCTAssertEqual(count, 1); XCTAssertNil(service.snapshot); XCTAssertFalse(service.loading)
    }
    func testMissingKeyPreventsTransportAndSavedKeyNeverEntersPreferences() async throws {
        let preferences = defaults(), keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        let service = service(preferences, keys: keys, fetch: fetch)
        service.selectSource(.weatherAPI); service.select(location); service.setEnabled(true)
        var count = await fetch.count(); XCTAssertEqual(count, 0); XCTAssertNotNil(service.error)
        XCTAssertTrue(service.saveKey("owned-fixture", for: .weatherAPI))
        let loaded = await wait { service.snapshot?.source == .weatherAPI }; XCTAssertTrue(loaded)
        let transportedKeys = await fetch.calledKeys(); XCTAssertEqual(transportedKeys, ["owned-fixture"])
        XCTAssertNil(preferences.string(forKey: "MacPocket.weather.apiKey"))
        let basket = try XCTUnwrap(preferences.data(forKey: "MacPocket.weather.sources"))
        XCTAssertFalse(String(decoding: basket, as: UTF8.self).contains("owned-fixture"))
        XCTAssertTrue(service.saveKey(nil, for: .weatherAPI))
        XCTAssertFalse(service.configuredKeys.contains(.weatherAPI)); XCTAssertNil(service.snapshot)
        count = await fetch.count(); XCTAssertEqual(count, 1)
        service.setEnabled(false)
    }
    func testKeychainFailureAndInvalidKeysDoNotStartTransport() async throws {
        let keys = WeatherCredentialFixture(), fetch = WeatherFetchFixture()
        let service = service(defaults(), keys: keys, fetch: fetch)
        XCTAssertFalse(service.saveKey("invalid/key", for: .weatherAPI)); XCTAssertEqual(keys.saves, 0)
        keys.rejects = true
        XCTAssertFalse(service.saveKey("owned-fixture", for: .weatherAPI)); XCTAssertNotNil(service.credentialError)
        XCTAssertFalse(service.configuredKeys.contains(.weatherAPI))
        let count = await fetch.count(); XCTAssertEqual(count, 0)
    }
    func testFailurePreservesSameSourceDataAndDoesNotFallBackSilently() async throws {
        let fetch = WeatherFetchFixture()
        var date = Date()
        let service = service(defaults(), keys: WeatherCredentialFixture(), fetch: fetch, now: { date })
        service.select(location); service.setEnabled(true)
        let loaded = await wait { service.snapshot != nil }; XCTAssertTrue(loaded)
        let fetchedAt = service.snapshot?.fetchedAt
        await fetch.setFailure(.rateLimited); date += 3_601
        service.refresh(manual: true)
        let failed = await wait { service.error != nil && !service.loading }; XCTAssertTrue(failed)
        XCTAssertEqual(service.snapshot?.fetchedAt, fetchedAt); XCTAssertEqual(service.activeSource, .visualCrossing)
        let sources = await fetch.calledSources(); XCTAssertEqual(sources, [.visualCrossing, .visualCrossing])
        service.refresh(manual: true)
        let count = await fetch.count(); XCTAssertEqual(count, 2)
        service.setEnabled(false)
    }
}
