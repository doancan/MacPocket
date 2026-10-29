import XCTest
@testable import MacPocketCore

final class PowerCommandTests: XCTestCase {
    func testValidCommandsBuildExactLines() throws {
        let display = try PMSetCommand(scope: .charger, key: .displaysleep, value: 10)
        XCTAssertEqual(display.commandLine, "/usr/bin/pmset -c displaysleep 10")
        XCTAssertEqual(display.arguments, ["-c", "displaysleep", "10"])
        XCTAssertEqual(try display.validatedCommandLine(), display.commandLine)
        XCTAssertEqual(try display.appleScriptSource(),
                       "do shell script \"/usr/bin/pmset -c displaysleep 10\" with administrator privileges")

        XCTAssertEqual(try PMSetCommand(scope: .battery, key: .powernap, value: 0).commandLine, "/usr/bin/pmset -b powernap 0")
        XCTAssertEqual(try PMSetCommand(scope: .all, key: .hibernatemode, value: 25).commandLine, "/usr/bin/pmset -a hibernatemode 25")
        XCTAssertEqual(try PMSetCommand(scope: .ups, keyName: "standbydelayhigh", value: 86_400).commandLine,
                       "/usr/bin/pmset -u standbydelayhigh 86400")
    }

    func testRejectsUnknownKeys() {
        for name in ["", "displaysleep; rm -rf /", "DisplaySleep", "boot", "hibernatefile ", "sleep\n", "$(id)"] {
            XCTAssertThrowsError(try PMSetCommand(scope: .all, keyName: name, value: 1)) { error in
                XCTAssertEqual(error as? PMSetCommandError, .unknownKey(name))
            }
        }
    }

    func testRejectsReadOnlyKeys() {
        for key in PMSettingKey.allCases where !key.isEditable {
            XCTAssertThrowsError(try PMSetCommand(scope: .all, key: key, value: 0)) { error in
                XCTAssertEqual(error as? PMSetCommandError, .notEditable(key.rawValue))
            }
        }
        XCTAssertFalse(PMSettingKey.networkoversleep.isEditable)
        XCTAssertFalse(PMSettingKey.hibernatefile.isEditable)
        XCTAssertFalse(PMSettingKey.disablesleep.isEditable)
    }

    func testRejectsOutOfRangeValues() {
        let cases: [(PMSettingKey, Int)] = [
            (.displaysleep, -1), (.displaysleep, 1441), (.sleep, Int.max), (.womp, 2), (.powernap, -1),
            (.hibernatemode, 1), (.hibernatemode, 7), (.gpuswitch, 3), (.highstandbythreshold, 101),
            (.standbydelay, 604_801), (.powermode, 3), (.lowpowermode, 2), (.haltlevel, -5),
        ]
        for (key, value) in cases {
            XCTAssertThrowsError(try PMSetCommand(scope: .charger, key: key, value: value), "\(key) \(value)") { error in
                XCTAssertEqual(error as? PMSetCommandError, .valueOutOfRange(key: key.rawValue, value: value))
            }
        }
    }

    func testEveryEditableKeyProducesAGrammarConformingCommand() throws {
        for key in PMSettingKey.allCases where key.isEditable {
            let value: Int
            switch key.kind {
            case let .minutes(range), let .seconds(range): value = range.upperBound
            case .percent: value = 100
            case .toggle: value = 1
            case let .choice(choices): value = try XCTUnwrap(choices.last).value
            case .raw: XCTFail("raw keys must not be editable"); continue
            }
            for scope in PMSetScope.allCases {
                let command = try PMSetCommand(scope: scope, key: key, value: value)
                XCTAssertNoThrow(try command.validatedCommandLine(), command.commandLine)
            }
        }
    }

    func testProfileScopesAndDisplayValues() {
        XCTAssertEqual(PMPowerProfile.ac.scope, .charger)
        XCTAssertEqual(PMPowerProfile.battery.scope, .battery)
        XCTAssertEqual(PMPowerProfile.ups.scope, .ups)
        XCTAssertEqual(PMSettingKey.sleep.display(0), "Hiçbir zaman")
        XCTAssertEqual(PMSettingKey.sleep.display(15), "15 dk")
        XCTAssertEqual(PMSettingKey.womp.display(1), "Açık")
        XCTAssertEqual(PMSettingKey.standbydelay.display(90), "90 sn")
        XCTAssertEqual(PMSettingKey.gpuswitch.display(2), "Otomatik")
    }

    func testFakeRunnerReceivesValidatedCommand() async throws {
        actor Recorder: PMSetPrivilegedRunning {
            var lines: [String] = []
            func run(_ command: PMSetCommand) async throws { lines.append(try command.validatedCommandLine()) }
        }
        let recorder = Recorder()
        try await recorder.run(PMSetCommand(scope: .battery, key: .lowpowermode, value: 1))
        let lines = await recorder.lines
        XCTAssertEqual(lines, ["/usr/bin/pmset -b lowpowermode 1"])
    }

    func testRunErrorsAreTurkish() {
        XCTAssertEqual(PMSetRunError.cancelled.errorDescription, "Yönetici onayı iptal edildi; ayar değişmedi.")
        XCTAssertNotNil(PMSetCommandError.malformed.errorDescription)
    }
}
