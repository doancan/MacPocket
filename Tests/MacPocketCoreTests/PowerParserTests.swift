import XCTest
@testable import MacPocketCore

/// Fixtures are captured from `pmset` on a Mac Studio (macOS 27) plus a MacBook-style battery profile.
final class PowerParserTests: XCTestCase {
    static let customDesktop = """
    AC Power:
     Sleep On Power Button 1
     autorestartatconnect 0
     lowpowermode         0
     standby              0
     ttyskeepawake        1
     powernap             1
     displaysleep         0
     womp                 1
     networkoversleep     0
     sleep                0
     tcpkeepalive         1
     autorestart          1
     disksleep            0
    """

    static let customLaptop = """
    Battery Power:
     lidwake              1
     standbydelayhigh     86400
     standbydelaylow      10800
     highstandbythreshold 50
     displaysleep         2
     sleep                1
     hibernatemode        3
     hibernatefile        /var/vm/sleepimage
     powernap             0
     lowpowermode         1
    AC Power:
     lidwake              1
     displaysleep         10
     sleep                1
     hibernatemode        3
     powernap             1
     acwake               0
    """

    static let live = """
    System-wide power settings:
    Currently in use:
     standby              0
     Sleep On Power Button 1
     autorestartatconnect 0
     autorestart          1
     powernap             1
     networkoversleep     0
     disksleep            0
     sleep                0 (sleep prevented by bluetoothd, caffeinate, sharingd, useractivityd, powerd, caffeinate)
     ttyskeepawake        1
     displaysleep         0
     tcpkeepalive         1
     lowpowermode         0
     womp                 1
    """

    static let assertions = """
    2026-10-29 11:15:01 +0300
    Assertion status system-wide:
       BackgroundTask                 0
       ApplePushServiceTask           0
       UserIsActive                   1
       PreventUserIdleDisplaySleep    0
       SoftwareUpdateTask             0
       PreventSystemSleep             0
       PreventSystemSleepSecurityIndicator 0
       ExternalMedia                  0
       PreventUserIdleSystemSleep     1
       NetworkClientActive            0
    Listed by owning process:
       pid 412(bluetoothd): [0x0000166a00018df7] 00:00:10 PreventUserIdleSystemSleep named: "com.apple.BTStack"
       pid 412(bluetoothd): [0x0000004d000982f0] 01:34:31 UserIsActive named: "Bluetooth LE HID Activity"
       pid 1591(caffeinate): [0x0000159200018d9e] 00:03:46 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
    \tDetails: caffeinate asserting for 300 secs
    \tLocalized=THE CAFFEINATE TOOL IS PREVENTING SLEEP.
    \tTimeout will fire in 73 secs Action=TimeoutActionRelease
       pid 682(sharingd): [0x0000165700018dd4] 00:00:29 PreventUserIdleSystemSleep named: "Handoff"
       pid 419(WindowServer): [0x0000003b0009804f] 00:00:00 UserIsActive named: "com.apple.iohideventsystem.queue.tickle serviceID:10000156d product:MX Master 4 M eventType:17"
       pid 363(powerd): [0x0000003500018006] 01:34:55 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
       pid 900(Google Chrome Helper (Renderer)): [0x0000003500018099] 1d 02:00:05 PreventUserIdleDisplaySleep named: "Video Wake Lock"
    Kernel Assertions: 0x104=USB,MAGICWAKE
       id=582  level=255 0x4=USB creat=29.10.2026, 09:46 description=com.apple.usb.externaldevice.00100000 owner=USB2.1 Hub
       id=591  level=255 0x100=MAGICWAKE creat=29.10.2026, 09:44 description=en1 owner=IOSkywalkNetworkBSDClient
    """

    static let thermalEmpty = """
    Note: No thermal warning level has been recorded
    Note: No performance warning level has been recorded
    Note: No CPU power status has been recorded
    """

    static let thermalThrottled = """
    2026-10-29 12:00:00 +0300 CPU Power notify
    \tCPU_Scheduler_Limit \t= 100
    \tCPU_Available_CPUs \t= 12
    \tCPU_Speed_Limit \t= 72
    """

    static let log = """
    PM ASL data store: /var/log/powermanagement
    2026-10-22 11:17:18 +0300 Assertions          \tPID 72992(Caffeine) TimedOut PreventUserIdleDisplaySleep "Caffeine prevents sleep" 00:00:08  id:0x0x500009dba [System: PrevIdle PrevDisp DeclUser IntPrevDisp kDisp]
    2026-10-29 09:40:04 +0300 Start               \tpowerd process is started                                                  \t
    2026-10-29 09:40:05 +0300 Notification        \tDisplay is turned on                                                       \t
    2026-10-29 22:10:31 +0300 Sleep               \tEntering Sleep state due to 'Idle Sleep':TCPKeepAlive=active Using AC (Charge:100%)          \t1 secs
    2026-10-29 23:05:02 +0300 DarkWake            \tDarkWake from Deep Idle [CDN] : due to NUB.SPMI0.SW3 SMC.OutboxNotEmpty/Maintenance Using AC (Charge:100%)          \t45 secs
    2026-10-30 07:58:44 +0300 Wake                \tWake from Deep Idle [CDNVA] : due to EC.LidOpen/Lid Open Using BATT (Charge:95%)          \t
    2026-10-30 07:58:45 +0300 Kernel Client Acks  \tDelays to Wake notifications: [AppleDisplay driver took 0.12 secs]
    2026-10-30 08:00:00 +0300 Notification        \tDisplay is turned off                                                      \t
    2026-10-30 08:00:01 +0300 Wake Requests       \t[*process=dasd request=Maintenance deltaSecs=1800]
    """

    static let schedule = """
    Repeating power events:
      wakepoweron at 8:00AM weekdays only
      sleep at 11:00PM every day
    Scheduled power events:
     [0]  wake at 10/30/2026 08:00:00 by 'com.apple.alarm.user-visible-Weekly Usage Report'
     [1]  wakeorpoweron at 11/01/26 09:00:00 by 'pmset'
    """

    // MARK: settings

    func testCustomDesktopProfile() {
        let profiles = PMSettingsParser.parseCustom(Self.customDesktop)
        XCTAssertEqual(profiles.map(\.profile), [.ac])
        let ac = profiles[0]
        XCTAssertEqual(ac.values.count, 13)
        XCTAssertEqual(ac.value(.womp)?.number, 1)
        XCTAssertEqual(ac.value(.sleepOnPowerButton)?.number, 1)
        XCTAssertEqual(ac.value(.sleepOnPowerButton)?.name, "Sleep On Power Button")
        XCTAssertEqual(ac.value(.displaysleep)?.displayValue, "Hiçbir zaman")
        // Catalog order: displaysleep is the first known key.
        XCTAssertEqual(ac.values.first?.key, .displaysleep)
    }

    func testCustomLaptopProfilesAndStringValues() {
        let profiles = PMSettingsParser.parseCustom(Self.customLaptop)
        XCTAssertEqual(profiles.map(\.profile), [.battery, .ac])
        let battery = profiles[0]
        XCTAssertEqual(battery.value(.standbydelayhigh)?.displayValue, "24 sa")
        XCTAssertEqual(battery.value(.standbydelaylow)?.displayValue, "3 sa")
        XCTAssertEqual(battery.value(.highstandbythreshold)?.displayValue, "%50")
        XCTAssertEqual(battery.value(.hibernatemode)?.displayValue, "Bellek + disk (3)")
        XCTAssertEqual(battery.value(.hibernatefile)?.rawValue, "/var/vm/sleepimage")
        XCTAssertNil(battery.value(.hibernatefile)?.number)
        XCTAssertEqual(battery.value(.displaysleep)?.displayValue, "2 dk")
        XCTAssertEqual(profiles[1].value(.displaysleep)?.number, 10)
    }

    func testLiveSettingsAndSleepPreventers() {
        let live = PMSettingsParser.parseLive(Self.live)
        XCTAssertEqual(live.values.count, 13)
        XCTAssertEqual(live.value(.sleep)?.number, 0)
        XCTAssertEqual(live.sleepPreventedBy, ["bluetoothd", "caffeinate", "sharingd", "useractivityd", "powerd", "caffeinate"])
        XCTAssertTrue(PMSettingsParser.parseLive("garbage\n").values.isEmpty)
    }

    func testPanelListsOnlySettingsMissingFromSystemSettings() {
        let ac = PMSettingsParser.parseCustom(Self.customDesktop)[0]
        // Sleep, display sleep, Power Nap, wake for network, restart after power failure, low power and disk
        // sleep all have controls in System Settings; the rest exist only in pmset.
        XCTAssertEqual(Set(ac.terminalOnlyValues.map(\.name)),
                       ["Sleep On Power Button", "autorestartatconnect", "standby", "ttyskeepawake", "networkoversleep", "tcpkeepalive"])
        XCTAssertTrue(PMSettingKey.hibernatemode.isEditable && !PMSettingKey.hibernatemode.hasSystemSettingsControl)
        XCTAssertTrue(PMSettingKey.powernap.hasSystemSettingsControl)
    }

    func testUnknownKeysStayVisibleInThePanel() {
        let profile = PMSettingsParser.parseCustom("AC Power:\n futurekey            7\n sleep 1\n")[0]
        XCTAssertEqual(profile.terminalOnlyValues.map(\.name), ["futurekey"])
    }

    func testUnknownKeysStayReadable() {
        let profiles = PMSettingsParser.parseCustom("AC Power:\n futurekey            7\n")
        XCTAssertEqual(profiles.first?.values.first?.name, "futurekey")
        XCTAssertNil(profiles.first?.values.first?.key)
        XCTAssertEqual(profiles.first?.values.first?.displayValue, "7")
    }

    // MARK: assertions

    func testAssertionsParse() {
        let report = PMAssertionParser.parse(Self.assertions)
        XCTAssertEqual(report.systemWide["PreventUserIdleSystemSleep"], 1)
        XCTAssertEqual(report.systemWide["UserIsActive"], 1)
        XCTAssertEqual(report.systemWide.count, 10)
        XCTAssertTrue(report.preventsIdleSystemSleep)
        XCTAssertFalse(report.preventsIdleDisplaySleep)
        XCTAssertEqual(report.assertions.count, 7)

        let caffeinate = report.assertions[2]
        XCTAssertEqual(caffeinate.pid, 1591)
        XCTAssertEqual(caffeinate.process, "caffeinate")
        XCTAssertEqual(caffeinate.ageSeconds, 226)
        XCTAssertEqual(caffeinate.type, "PreventUserIdleSystemSleep")
        XCTAssertEqual(caffeinate.name, "caffeinate command-line tool")
        XCTAssertEqual(caffeinate.details.count, 3)
        XCTAssertEqual(caffeinate.timeoutSeconds, 73)
        XCTAssertEqual(caffeinate.effect, .preventsSystemSleep)

        let chrome = report.assertions[6]
        XCTAssertEqual(chrome.process, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(chrome.ageSeconds, 86_400 + 7205)
        XCTAssertEqual(chrome.effect, .preventsDisplaySleep)

        XCTAssertEqual(report.assertions[1].effect, .userActivity)
        XCTAssertEqual(report.sleepBlockers.count, 5)
        XCTAssertEqual(report.kernelAssertions.count, 2)
        XCTAssertEqual(report.kernelAssertions[0].owner, "USB2.1 Hub")
        XCTAssertEqual(report.kernelAssertions[0].type, "USB")
        XCTAssertEqual(report.kernelAssertions[1].detail, "en1")
        XCTAssertEqual(Set(report.assertions.map(\.id)).count, report.assertions.count)
    }

    func testAssertionAgeParsing() {
        XCTAssertEqual(PMAssertionParser.parseAge("01:34:55"), 5695)
        XCTAssertEqual(PMAssertionParser.parseAge("2d 00:00:01"), 172_801)
        XCTAssertNil(PMAssertionParser.parseAge("soon"))
    }

    // MARK: thermal

    func testThermalReports() {
        let empty = PMThermalParser.parse(Self.thermalEmpty)
        XCTAssertEqual(empty.notes.count, 3)
        XCTAssertNil(empty.cpuSpeedLimit)
        XCTAssertFalse(empty.isThrottled)
        let hot = PMThermalParser.parse(Self.thermalThrottled)
        XCTAssertEqual(hot.cpuSpeedLimit, 72)
        XCTAssertEqual(hot.schedulerLimit, 100)
        XCTAssertEqual(hot.availableCPUs, 12)
        XCTAssertTrue(hot.isThrottled)
    }

    // MARK: log

    func testLogParsesSleepWakeAndSkipsNoise() {
        let events = PMLogParser.parse(Self.log)
        XCTAssertEqual(events.map(\.kind), [.start, .displayOn, .sleep, .darkWake, .wake, .displayOff])
        let sleep = events[2]
        XCTAssertEqual(sleep.reason, "Idle Sleep")
        XCTAssertEqual(sleep.powerSource, "AC")
        XCTAssertEqual(sleep.chargePercent, 100)
        XCTAssertEqual(sleep.durationSeconds, 1)
        let dark = events[3]
        XCTAssertEqual(dark.reason, "NUB.SPMI0.SW3 SMC.OutboxNotEmpty/Maintenance")
        XCTAssertEqual(dark.durationSeconds, 45)
        let wake = events[4]
        XCTAssertEqual(wake.reason, "EC.LidOpen/Lid Open")
        XCTAssertEqual(wake.powerSource, "BATT")
        XCTAssertEqual(wake.chargePercent, 95)
        XCTAssertNil(wake.durationSeconds)
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 30
        components.hour = 7; components.minute = 58; components.second = 44
        components.timeZone = TimeZone(secondsFromGMT: 3 * 3600)
        XCTAssertEqual(wake.date, Calendar(identifier: .gregorian).date(from: components))
    }

    func testLogCandidateFilter() {
        let lines = Self.log.split(separator: "\n")
        XCTAssertFalse(PMLogParser.isCandidate(lines[0]))
        XCTAssertFalse(PMLogParser.isCandidate(lines[1]))
        XCTAssertTrue(PMLogParser.isCandidate(lines[2]))
    }

    // MARK: schedule

    func testScheduleParse() {
        let events = PMScheduleParser.parse(Self.schedule)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.filter(\.repeating).count, 2)
        XCTAssertEqual(events[0].type, "wakepoweron")
        XCTAssertEqual(events[0].when, "8:00AM weekdays only")
        XCTAssertEqual(events[0].typeTitle, "Uyan veya aç")
        XCTAssertEqual(events[2].owner, "com.apple.alarm.user-visible-Weekly Usage Report")
        XCTAssertNotNil(events[2].date)
        let year = events[3].date.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
        XCTAssertEqual(year, 2026)
        XCTAssertEqual(events[3].owner, "pmset")
        XCTAssertTrue(PMScheduleParser.parse("").isEmpty)
    }

    // MARK: timeline

    func testTimelineMergeDeduplicatesLocalRecords() throws {
        let events = PMLogParser.parse(Self.log)
        let sleepDate = try XCTUnwrap(events.first { $0.kind == .sleep }?.date)
        func entry(_ date: Date, _ event: String) -> PowerHistoryEntry {
            PowerHistoryEntry(id: UUID(), date: date, source: "AC Power", chargePercent: 80, charging: false,
                              lowPower: false, thermalState: "nominal", event: event)
        }
        let local = [entry(sleepDate.addingTimeInterval(30), "Uyku"),      // duplicate of the system sleep
                     entry(sleepDate.addingTimeInterval(-86_400), "Uyku"),  // unique
                     entry(sleepDate, "sample")]                            // not an event
        let merged = PowerTimeline.merge(log: events, local: local)
        XCTAssertEqual(merged.count, events.count + 1)
        XCTAssertEqual(merged.filter { $0.origin == .local }.count, 1)
        XCTAssertEqual(merged.first?.kind, .displayOff)
        XCTAssertEqual(merged.last?.origin, .local)
        XCTAssertEqual(merged.map(\.date), merged.map(\.date).sorted(by: >))
        XCTAssertEqual(PowerTimeline.merge(log: events, local: [], limit: 2).count, 2)
    }
}
