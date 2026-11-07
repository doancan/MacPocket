import XCTest
@testable import MacPocketCore

final class WindowKeyEventRecordTests: XCTestCase {
    func testWindowServerRecordHasDeclaredLengthAndZeroedTail() {
        let record = WindowKeyEventRecord.make(windowID: 42)
        XCTAssertEqual(record.count,256);XCTAssertEqual(record[4],248)
        XCTAssertTrue(record[248..<256].allSatisfy { $0 == 0 })
        XCTAssertEqual(record[8],1) // Targeted down only; no release completes a content click.
    }
    func testTargetIDRoundTripsAtTheObservedABIFieldIncludingAllBits() {
        for id: UInt32 in [1,42,.max] {
            let record = WindowKeyEventRecord.make(windowID: id)
            let decoded = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0x3c,as: UInt32.self) }
            XCTAssertEqual(UInt32(littleEndian: decoded),id);XCTAssertEqual(record[0x3a],0x10)
        }
    }
    func testSyntheticLocationIsFiniteAndBeyondContentAndResizeEdges() {
        let record = WindowKeyEventRecord.make(windowID: 42)
        let point = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0x20,as: CGPoint.self) }
        XCTAssertTrue(point.x.isFinite && point.y.isFinite)
        for frame in [CGRect(x: 0,y: 0,width: 3008,height: 1692),CGRect(x: 0,y: 0,width: 10000,height: 10000)] {
            XCTAssertFalse(frame.insetBy(dx: -100,dy: -100).contains(point))
        }
    }
}
