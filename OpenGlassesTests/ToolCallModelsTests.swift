import XCTest
@testable import OpenGlasses

final class ToolCallModelsTests: XCTestCase {

    // MARK: - ToolResult

    func testToolResultSuccessResponseValue() {
        let result = ToolResult.success("Task completed successfully")
        let response = result.responseValue
        XCTAssertEqual(response["result"] as? String, "Task completed successfully")
        XCTAssertNil(response["error"])
    }

    func testToolResultFailureResponseValue() {
        let result = ToolResult.failure("Connection timeout")
        let response = result.responseValue
        XCTAssertEqual(response["error"] as? String, "Connection timeout")
        XCTAssertNil(response["result"])
    }

    // MARK: - ToolCallStatus

    func testToolCallStatusDisplayText() {
        XCTAssertEqual(ToolCallStatus.idle.displayText, "")
        XCTAssertEqual(ToolCallStatus.executing("search").displayText, "Running: search...")
        XCTAssertEqual(ToolCallStatus.completed("search").displayText, "Done: search")
        XCTAssertEqual(ToolCallStatus.failed("search", "timeout").displayText, "Failed: search -- timeout")
        XCTAssertEqual(ToolCallStatus.cancelled("search").displayText, "Cancelled: search")
    }

    func testToolCallStatusIsActive() {
        XCTAssertFalse(ToolCallStatus.idle.isActive)
        XCTAssertTrue(ToolCallStatus.executing("search").isActive)
        XCTAssertFalse(ToolCallStatus.completed("search").isActive)
        XCTAssertFalse(ToolCallStatus.failed("search", "err").isActive)
        XCTAssertFalse(ToolCallStatus.cancelled("search").isActive)
    }

    func testToolCallStatusEquatable() {
        XCTAssertEqual(ToolCallStatus.idle, ToolCallStatus.idle)
        XCTAssertEqual(ToolCallStatus.executing("x"), ToolCallStatus.executing("x"))
        XCTAssertNotEqual(ToolCallStatus.executing("x"), ToolCallStatus.executing("y"))
        XCTAssertNotEqual(ToolCallStatus.idle, ToolCallStatus.executing("x"))
    }
}
