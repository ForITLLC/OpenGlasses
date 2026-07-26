import XCTest
@testable import OpenGlasses

// NOTE: the former ToolResult tests were removed — ToolResult itself was deleted
// in ffd3276 (Dolores-only rework, stripping the multi-provider tool plumbing).
// They never failed only because no test target existed to compile them.

final class ToolCallModelsTests: XCTestCase {

    // MARK: - ToolCallStatus

    func testToolCallStatusDisplayText() {
        XCTAssertEqual(ToolCallStatus.idle.displayText, "")
        XCTAssertEqual(ToolCallStatus.calling("search").displayText, "Running: search...")
        XCTAssertEqual(ToolCallStatus.completed("search").displayText, "Done: search")
        XCTAssertEqual(ToolCallStatus.failed("search").displayText, "Failed: search")
    }

    func testToolCallStatusIsActive() {
        XCTAssertFalse(ToolCallStatus.idle.isActive)
        XCTAssertTrue(ToolCallStatus.calling("search").isActive)
        XCTAssertFalse(ToolCallStatus.completed("search").isActive)
        XCTAssertFalse(ToolCallStatus.failed("search").isActive)
    }

    func testToolCallStatusEquatable() {
        XCTAssertEqual(ToolCallStatus.idle, ToolCallStatus.idle)
        XCTAssertEqual(ToolCallStatus.calling("x"), ToolCallStatus.calling("x"))
        XCTAssertNotEqual(ToolCallStatus.calling("x"), ToolCallStatus.calling("y"))
        XCTAssertNotEqual(ToolCallStatus.idle, ToolCallStatus.calling("x"))
        XCTAssertNotEqual(ToolCallStatus.completed("x"), ToolCallStatus.failed("x"))
    }
}
