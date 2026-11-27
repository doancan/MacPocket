import XCTest
import MacPocketCore
import MacPocketTestSupport
@testable import MacPocketApp

final class LanguageDefaultTests: XCTestCase {
    func testFreshInstallFollowsTheSystemLanguageInsteadOfPinningTurkish() throws {
        let store = temporaryDefaultsStore()
        PocketDefaults.applyLanguageDefault(store.defaults, domain: store.suiteName)
        XCTAssertEqual(AppLanguage.load(from: store.defaults, domain: store.suiteName), .system)
        XCTAssertNil(store.defaults.persistentDomain(forName: store.suiteName)?[AppLanguage.defaultsKey],
                     "no AppleLanguages override: macOS picks from the user's language order")
    }

    func testAnExplicitLanguageChoiceIsKept() throws {
        for choice in [AppLanguage.english, .turkish] {
            let store = temporaryDefaultsStore()
            choice.save(to: store.defaults, systemLocale: "en_TR")
            PocketDefaults.applyLanguageDefault(store.defaults, domain: store.suiteName)
            XCTAssertEqual(AppLanguage.load(from: store.defaults, domain: store.suiteName), choice)
        }
    }

    func testChoosingTheSystemLanguageAgainRemovesTheOverride() throws {
        let store = temporaryDefaultsStore()
        AppLanguage.turkish.save(to: store.defaults, systemLocale: "en_TR")
        AppLanguage.system.save(to: store.defaults, systemLocale: "en_TR")
        PocketDefaults.applyLanguageDefault(store.defaults, domain: store.suiteName)
        XCTAssertEqual(AppLanguage.load(from: store.defaults, domain: store.suiteName), .system)
    }
}
