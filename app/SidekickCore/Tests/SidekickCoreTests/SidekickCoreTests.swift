import XCTest
@testable import SidekickCore

final class SidekickCoreTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(SidekickCore.moduleName, "SidekickCore")
    }
}
