#if DEBUG
import AppKit
import ApplicationServices
import MacPocketCore
import Darwin

/// Controlled feasibility probe: only events carrying our marker are absorbed. Physical keyboard
/// input is passed through, no symbolic hotkey is disabled, and the tap is always invalidated.
@MainActor enum CommandTabInputProbe {
    private static let marker: Int64 = 0x4D50_4354_5052
    private final class Counters { var forward = 0,reverse = 0,ups = 0,disabled = 0,callbacks = 0;var tabEvents: [[String:Int64]] = [] }
    static func run(fixturePID: Int32,activateFixture: () async throws -> Void) async throws -> ([String:Bool],[String:Any]) {
        var checks: [String:Bool] = [:]
        if CommandLine.arguments.contains("--only-command-tab-reset") {
            let before = CGEventSource.flagsState(.combinedSessionState).rawValue
            guard CGPreflightPostEventAccess() else { return (["commandTabOwnedTrialMayRelease": false],["beforeFlags": before,"postAccess": false]) }
            releaseCommand()
            try await Task.sleep(for: .milliseconds(160))
            let after = CGEventSource.flagsState(.combinedSessionState)
            return (["commandTabOwnedTrialReleasesCommand": !after.contains(.maskCommand)],
                    ["beforeFlags": before,"afterFlags": after.rawValue,"postAccess": true,"nativeSettingsChanged": false])
        }
        let input = SecureKeyboardInputStatus.read()
        guard !input.enabled else {
            return (["commandTabProbeKeyboardInputAvailable": false],
                    ["blockedBySecureKeyboardInput": true, "secureInputOwnerPID": input.processID ?? 0,
                     "input": "none", "nativeSettingsChanged": false, "physicalKeyboardVerified": false])
        }
        let counters = Counters()
        let anchor = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 240,height: 100),styleMask: [.titled],backing: .buffered,defer: false)
        anchor.isReleasedWhenClosed = false;anchor.title = String(localized: "MacPocket · Masaüstü testi")
        anchor.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps: true)
        defer { anchor.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(180))
        try await activateFixture()
        let deadline = ContinuousClock.now + .seconds(2)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != fixturePID,ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        checks["commandTabProbeOwnedFixtureIsForeground"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID
        checks["commandTabProbeMayPostGeneratedEvents"] = CGPreflightPostEventAccess()
        guard CGPreflightPostEventAccess() else { return (checks,["input": "post-access-unavailable","nativeSettingsChanged": false]) }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty else {
            return (["commandTabProbeModifiersAreIdle": false],["input": "modifiers-not-idle","flags": flags.rawValue,"postAccess": true,"nativeSettingsChanged": false])
        }
        defer { releaseCommand() }
        let callback: CGEventTapCallBack = { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let counters = Unmanaged<CommandTabInputProbe.Counters>.fromOpaque(context).takeUnretainedValue()
            let keep = MainActor.assumeIsolated {
                counters.callbacks += 1
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { counters.disabled += 1;return true }
                if event.getIntegerValueField(.keyboardEventKeycode) == 48,counters.tabEvents.count < 8 {
                    counters.tabEvents.append(["type": Int64(type.rawValue),"flags": Int64(event.flags.rawValue),"marker": event.getIntegerValueField(.eventSourceUserData),"sourcePID": event.getIntegerValueField(.eventSourceUnixProcessID)])
                }
                guard event.getIntegerValueField(.eventSourceUserData) == CommandTabInputProbe.marker,event.getIntegerValueField(.keyboardEventKeycode) == 48 else { return true }
                if type == .keyDown { if event.flags.contains(.maskShift) { counters.reverse += 1 } else { counters.forward += 1 } }
                if type == .keyUp { counters.ups += 1 }
                return false
            }
            return keep ? Unmanaged.passUnretained(event) : nil
        }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,place: .headInsertEventTap,options: .defaultTap,eventsOfInterest: mask,
            callback: callback,userInfo: Unmanaged.passUnretained(counters).toOpaque()),let source = CFMachPortCreateRunLoopSource(nil,tap,0) else {
            checks["commandTabProbeCreatesSessionFilter"] = false
            return (checks,["input": "none","nativeSettingsChanged": false])
        }
        checks["commandTabProbeCreatesSessionFilter"] = true
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes);CGEvent.tapEnable(tap: tap,enable: true)
        defer {
            CGEvent.tapEnable(tap: tap,enable: false);CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)
        }
        let baseline = dockWindows(),nativeBefore = nativeEnabled()
        post(shift: false)
        try await Task.sleep(for: .milliseconds(180))
        let afterForward = dockWindows()
        checks["commandTabProbeInterceptsForwardDownAndUp"] = counters.forward == 1 && counters.ups == 1
        checks["commandTabProbeForwardDoesNotActivateAnotherApp"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID
        checks["commandTabProbeForwardDoesNotOpenNativeDockSwitcher"] = afterForward.subtracting(baseline).isEmpty
        if checks.values.allSatisfy({ $0 }) {
            post(shift: true)
            try await Task.sleep(for: .milliseconds(180))
            checks["commandTabProbeInterceptsReverseDownAndUp"] = counters.reverse == 1 && counters.ups == 2
            checks["commandTabProbeReverseDoesNotActivateAnotherApp"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID
            checks["commandTabProbeReverseDoesNotOpenNativeDockSwitcher"] = dockWindows().subtracting(baseline).isEmpty
        }
        checks["commandTabProbeWasNotDisabled"] = counters.disabled == 0
        return (checks,["input": "marked-generated-HID-posts-through-cgSessionEventTap","nativeSettingsChanged": false,
            "physicalKeyboardVerified": false,"forward": counters.forward,"reverse": counters.reverse,"keyUps": counters.ups,
            "callbackCount": counters.callbacks,"tabEvents": counters.tabEvents,"nativeBefore": nativeBefore,"nativeAfter": nativeEnabled(),
            "dockBefore": baseline.sorted(),"dockAfterForward": afterForward.sorted(),"dockAfter": dockWindows().sorted()])
    }
    private static func post(shift: Bool) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true,false] {
            if let event = CGEvent(keyboardEventSource: source,virtualKey: 48,keyDown: down) {
                event.flags = shift ? [.maskCommand,.maskShift] : .maskCommand
                event.setIntegerValueField(.eventSourceUserData,value: marker)
                event.post(tap: .cghidEventTap)
            }
        }
    }
    private static func releaseCommand() {
        if let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),virtualKey: 55,keyDown: false) {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData,value: marker)
            event.post(tap: .cghidEventTap)
        }
    }
    private static func dockWindows() -> Set<UInt32> {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],0) as? [[String:Any]] ?? []
        return Set(rows.filter { $0[kCGWindowOwnerName as String] as? String == "Dock" }.compactMap { $0[kCGWindowNumber as String] as? UInt32 })
    }
    private static func nativeEnabled() -> [String:Bool] {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY | RTLD_LOCAL) else { return [:] }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle,"CGSIsSymbolicHotKeyEnabled") else { return [:] }
        let query = unsafeBitCast(symbol,to: (@convention(c) (Int32) -> Bool).self)
        return ["1": query(1),"2": query(2)]
    }
}
#endif
