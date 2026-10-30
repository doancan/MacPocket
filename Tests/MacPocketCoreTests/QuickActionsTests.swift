import XCTest
@testable import MacPocketCore

final class QuickActionsTests: XCTestCase {
    private func volume(_ path: String, ejectable: Bool = false, removable: Bool = false, inside: Bool = true,
                        root: Bool = false) -> MountedVolume {
        MountedVolume(url: URL(fileURLWithPath: path), name: (path as NSString).lastPathComponent, isEjectable: ejectable,
                      isRemovable: removable, isInternal: inside, isRoot: root)
    }

    func testStartupAndSystemVolumesAreNeverEjected() {
        XCTAssertFalse(volume("/", inside: true, root: true).canEject)
        XCTAssertFalse(volume("/System/Volumes/Data", ejectable: true).canEject)
        XCTAssertFalse(volume("/Volumes/Recovery").canEject, "internal, fixed partition")
    }

    func testExternalDisksCardsAndImagesAreEjectable() {
        XCTAssertTrue(volume("/Volumes/USB", ejectable: true, removable: true, inside: false).canEject)
        XCTAssertTrue(volume("/Volumes/SD", removable: true).canEject, "built-in card reader media")
        XCTAssertTrue(volume("/Volumes/Docker", ejectable: true).canEject, "mounted disk image")
        XCTAssertTrue(volume("/Volumes/Thunderbolt SSD", inside: false).canEject)
    }

    func testOnlyDisruptiveActionsAskFirst() {
        XCTAssertEqual(QuickAction.allCases.filter(\.needsConfirmation), [.sleepMac, .emptyTrash])
    }
}
