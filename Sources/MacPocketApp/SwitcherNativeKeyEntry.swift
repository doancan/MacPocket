import Darwin
import Foundation
import MacPocketCore

@MainActor enum SwitcherNativeKeyEntry {
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--switcher-native-key-guard"] { exit(SwitcherNativeKeyGuard.run()) }
        #if DEBUG
        if args.count == 3,args[0] == "--switcher-native-key-guard-fixture",let timeout = Double(args[2]) {
            exit(SwitcherNativeKeyFixture.run(file: URL(fileURLWithPath: args[1]),timeout: timeout))
        }
        SwitcherNativeKeyRuntimeAudit.runIfRequested(args)
        #endif
    }
}
