import XCTest
@testable import MacPocketCore

final class SwitcherNavigationTests: XCTestCase {
    private func resolve(_ code: UInt16, _ text: String = "", options: SwitcherNavigationOptions = .init(arrows: true,vim: true),
                         modifiers: SwitcherModifiers = .option, held: SwitcherModifiers = .option, shift: Bool = false,
                         searching: Bool = false, bindings: [SwitcherActionBinding] = SwitcherActionBinding.defaults) -> SwitcherPanelKeyCommand? {
        SwitcherPanelInput.command(keyCode: code,characters: text,modifiers: modifiers,shift: shift,held: held,
                                  isSearching: searching,options: options,bindings: bindings)
    }
    func testLegacyDefaultsRetainArrowsAndDoNotEnableVimOrWritePreferences() {
        let name = "SwitcherNavigationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SwitcherNavigationOptions.load(defaults),.init(arrows: true,vim: false))
        XCTAssertNil(defaults.object(forKey: SwitcherNavigationOptions.arrowsKey))
        XCTAssertNil(defaults.object(forKey: SwitcherNavigationOptions.vimKey))
        defaults.set(false,forKey: SwitcherNavigationOptions.arrowsKey);defaults.set(true,forKey: SwitcherNavigationOptions.vimKey)
        XCTAssertEqual(SwitcherNavigationOptions.load(defaults),.init(arrows: false,vim: true))
        defaults.set("invalid",forKey: SwitcherNavigationOptions.arrowsKey);defaults.set([],forKey: SwitcherNavigationOptions.vimKey)
        XCTAssertEqual(SwitcherNavigationOptions.load(defaults),.init())
    }
    func testArrowAndVimOptionsAreIndependent() {
        XCTAssertEqual(resolve(124,options: .init(arrows: true,vim: false)),.move(backwards: false,count: 1))
        XCTAssertNil(resolve(4,"h",options: .init(arrows: true,vim: false)))
        XCTAssertEqual(resolve(124,options: .init(arrows: false,vim: true)),.ignore)
        XCTAssertEqual(resolve(4,"h",options: .init(arrows: false,vim: true)),.move(backwards: true,count: 1))
    }
    func testDirectionsDistinguishRowsFromLinearCycling() {
        XCTAssertEqual(resolve(4,"h"),.move(backwards: true,count: 1))
        XCTAssertEqual(resolve(37,"l"),.move(backwards: false,count: 1))
        XCTAssertEqual(resolve(123),.move(backwards: true,count: 1))
        XCTAssertEqual(resolve(124),.move(backwards: false,count: 1))
        XCTAssertEqual(resolve(38,"j"),.row(backwards: false));XCTAssertEqual(resolve(40,"k"),.row(backwards: true))
        XCTAssertEqual(resolve(125),.row(backwards: false));XCTAssertEqual(resolve(126),.row(backwards: true))
    }
    func testVimUsesLogicalCharactersRatherThanUSPhysicalPositions() {
        XCTAssertEqual(resolve(6,"h"),.move(backwards: true,count: 1))
        XCTAssertNil(resolve(4,"x"))
        XCTAssertNil(resolve(4,"H"))
        XCTAssertNil(resolve(6,"ş"))
        XCTAssertNil(resolve(6,"hj"))
    }
    func testSearchLeavesVimLettersSlashAndShiftedLettersAsText() {
        for (code,text) in [(UInt16(4),"h"),(38,"j"),(40,"k"),(37,"l"),(44,"/")] {
            XCTAssertNil(resolve(code,text,searching: true))
        }
        XCTAssertNil(resolve(4,"H",shift: true))
        XCTAssertEqual(resolve(44,"/"),.action(.search))
        XCTAssertEqual(resolve(26,"/",shift: true),.action(.search))
        XCTAssertEqual(resolve(26,"/",shift: true,bindings: [.init(action: .close,keyCode: 26,shift: true)]),.action(.close))
        XCTAssertNil(resolve(44,"/",options: .init()))
    }
    func testOpeningModifiersAreConsumedButExtraModifiersDoNotNavigate() {
        XCTAssertEqual(resolve(4,"h",modifiers: [.control,.option],held: [.control,.option]),.move(backwards: true,count: 1))
        XCTAssertNil(resolve(4,"h",modifiers: [.control,.option]))
        XCTAssertEqual(resolve(124,modifiers: [.control,.option]),.ignore)
        XCTAssertEqual(resolve(48,modifiers: [.control,.option]),.ignore)
        XCTAssertEqual(resolve(125,shift: true),.row(backwards: false))
    }
    func testTabShiftTabAndEscapeStayReachableWithBothNavigationOptionsOff() {
        let off = SwitcherNavigationOptions(arrows: false,vim: false)
        XCTAssertEqual(resolve(48,options: off,bindings: []),.move(backwards: false,count: 1))
        XCTAssertEqual(resolve(48,options: off,shift: true,bindings: []),.move(backwards: true,count: 1))
        XCTAssertEqual(resolve(53,options: off,bindings: []),.action(.cancel))
    }
    func testExplicitBareLetterActionPrecedesVimButNeverConsumesSearchText() {
        let bindings = [SwitcherActionBinding(action: .hide,keyCode: 4)]
        XCTAssertTrue(SwitcherActionBindings.problems(bindings).isEmpty)
        XCTAssertEqual(resolve(4,"h",bindings: bindings),.action(.hide))
        XCTAssertNil(resolve(4,"h",searching: true,bindings: bindings))
        XCTAssertEqual(resolve(44,"/",bindings: [.init(action: .close,keyCode: 44)]),.action(.close))
    }
    func testCustomArrowActionCanReplaceNavigationEvenWhenArrowsAreOff() {
        let bindings = [SwitcherActionBinding(action: .choose,keyCode: 124)]
        XCTAssertTrue(SwitcherActionBindings.problems(bindings).isEmpty)
        XCTAssertEqual(resolve(124,options: .init(arrows: false),bindings: bindings),.action(.choose))
        XCTAssertEqual(resolve(124,searching: true,bindings: bindings),.action(.choose))
        XCTAssertFalse(SwitcherActionBindings.problems([.init(action: .close,keyCode: 48)]).isEmpty)
    }
    func testKeypadEnterAliasOnlyExistsForTheUnmodifiedReturnChoiceBinding() {
        XCTAssertEqual(resolve(76),.action(.choose))
        XCTAssertNil(resolve(76,bindings: [.init(action: .choose,keyCode: nil)]))
        XCTAssertNil(resolve(76,bindings: [.init(action: .choose,keyCode: 36,modifiers: .control)]))
        XCTAssertNil(resolve(76,shift: true))
    }
    func testConflictWarningsFollowTheCurrentLayoutAndDoNotChangeBindings() {
        let bindings: [SwitcherActionBinding] = [.init(action: .close,keyCode: 6),.init(action: .hide,keyCode: 4),
            .init(action: .previous,keyCode: 123,shift: true),.init(action: .quit,keyCode: 37,modifiers: .command)]
        let options = SwitcherNavigationOptions(arrows: true,vim: true)
        XCTAssertEqual(options.overriddenBindings(bindings,characters: [6:"h",4:"d",37:"l"]).map(\.action),[.close,.previous])
        XCTAssertTrue(SwitcherNavigationOptions(arrows: false,vim: false).overriddenBindings(bindings,characters: [6:"h"]).isEmpty)
        XCTAssertEqual(options.overriddenBindings([.init(action: .search,keyCode: 26,shift: true)],characters: [26:"7"],shiftedCharacters: [26:"/"]).map(\.action),[.search])
        XCTAssertEqual(bindings[0].keyCode,6)
    }
    func testIncompleteRowsClampColumnsAndWrapRowsInsteadOfFlatWindowCount() {
        let down = (0..<5).map { WindowSwitchSelection.rowDestination(index: $0,windowCount: 5,columns: 3,backwards: false) }
        let up = (0..<5).map { WindowSwitchSelection.rowDestination(index: $0,windowCount: 5,columns: 3,backwards: true) }
        XCTAssertEqual(down,[3,4,4,0,1]);XCTAssertEqual(up,[3,4,4,0,1])
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: 7,windowCount: 8,columns: 3,backwards: false),1)
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: 4,windowCount: 8,columns: 3,backwards: true),1)
    }
    func testRowGeometryHandlesEmptySingleColumnSingleRowAndExtremeInputs() {
        XCTAssertNil(WindowSwitchSelection.rowDestination(index: 0,windowCount: 0,columns: 3,backwards: false))
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: 2,windowCount: 5,columns: 1,backwards: false),3)
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: 0,windowCount: 5,columns: 0,backwards: true),4)
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: 2,windowCount: 5,columns: .max,backwards: false),2)
        XCTAssertEqual(WindowSwitchSelection.rowDestination(index: .max - 1,windowCount: .max,columns: .max,backwards: false),.max - 1)
    }
    func testQueuedMixedDirectionsReplayAgainstTheFreshListWithoutLosingOrder() {
        let windows = (0..<5).map { index in SwitchableWindow(id: "w\(index)",processID: 1,application: "Fixture",title: "",applicationURL: nil,
            minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,
            canFullScreen: false,launchedAt: nil,lastFocusedAt: nil,windowID: UInt32(index+1)) }
        XCTAssertEqual(WindowSwitchSelection.applying([.row(backwards: false),.linear(-1)],to: windows,preserving: "w2",columns: 3),"w3")
        XCTAssertEqual(WindowSwitchSelection.applying([.linear(-1),.row(backwards: false)],to: windows,preserving: "w2",columns: 3),"w4")
        XCTAssertEqual(WindowSwitchSelection.applying([.linear(.min)],to: windows,preserving: "w0",columns: 3),"w2")
        XCTAssertNil(WindowSwitchSelection.applying([.row(backwards: false)],to: [],preserving: nil,columns: 3))
    }

}
