import XCTest
@testable import OpenGlasses

@MainActor
final class ToolCallRouterTests: XCTestCase {

    private let configKeys = [
        "openClawEnabled",
        "openClawConnectionMode",
        "openClawLanHost",
        "openClawPort",
        "openClawGatewayToken",
    ]

    override func setUp() {
        super.setUp()
        for key in configKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in configKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Initialization

    func testRouterInitialization() {
        let bridge = OpenClawBridge()
        let router = ToolCallRouter(bridge: bridge)
        // Should not crash
        _ = router
    }

    // MARK: - Cancel Operations

    func testCancelAllWithNoInFlightTasks() {
        let bridge = OpenClawBridge()
        let router = ToolCallRouter(bridge: bridge)

        // Should not crash when nothing to cancel
        router.cancelAll()
    }

    func testCancelToolCallsWithUnknownIds() {
        let bridge = OpenClawBridge()
        let router = ToolCallRouter(bridge: bridge)

        // Should not crash with unknown IDs
        router.cancelToolCalls(ids: ["unknown-1", "unknown-2"])
        XCTAssertEqual(bridge.lastToolCallStatus, .cancelled("unknown-1"))
    }

    func testCancelToolCallsSetsStatusToCancelled() {
        let bridge = OpenClawBridge()
        let router = ToolCallRouter(bridge: bridge)

        router.cancelToolCalls(ids: ["call-abc"])
        XCTAssertEqual(bridge.lastToolCallStatus, .cancelled("call-abc"))
    }

    // MARK: - Handle Tool Call

    func testHandleToolCallSendsResponse() async {
        // Set up config so bridge attempts a request
        Config.setOpenClawEnabled(true)
        Config.setOpenClawGatewayToken("test-token")
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("http://127.0.0.1")
        Config.setOpenClawPort(1)  // Port 1 — will fail fast

        let bridge = OpenClawBridge()
        bridge.clearCachedEndpoint()
        let router = ToolCallRouter(bridge: bridge)

        let call = GeminiFunctionCall(
            id: "test-call-1",
            name: "execute",
            args: ["task": "add milk to shopping list"]
        )

        let expectation = expectation(description: "response sent")
        var receivedResponse: [String: Any]?

        router.handleToolCall(call) { response in
            receivedResponse = response
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        // Verify response structure
        XCTAssertNotNil(receivedResponse)
        let toolResponse = receivedResponse?["toolResponse"] as? [String: Any]
        XCTAssertNotNil(toolResponse)
        let functionResponses = toolResponse?["functionResponses"] as? [[String: Any]]
        XCTAssertNotNil(functionResponses)
        XCTAssertEqual(functionResponses?.count, 1)
        XCTAssertEqual(functionResponses?.first?["id"] as? String, "test-call-1")
        XCTAssertEqual(functionResponses?.first?["name"] as? String, "execute")
    }

    func testCancelInFlightTask() async {
        Config.setOpenClawEnabled(true)
        Config.setOpenClawGatewayToken("test-token")
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("http://10.255.255.1")  // Non-routable — will hang
        Config.setOpenClawPort(18789)

        let bridge = OpenClawBridge()
        bridge.clearCachedEndpoint()
        let router = ToolCallRouter(bridge: bridge)

        let call = GeminiFunctionCall(
            id: "cancel-me",
            name: "execute",
            args: ["task": "slow task"]
        )

        // Start the tool call (it will hang trying to connect)
        router.handleToolCall(call) { _ in
            // Should not be called due to cancellation
        }

        // Give it a moment to register in-flight
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Cancel it
        router.cancelToolCalls(ids: ["cancel-me"])
        XCTAssertEqual(bridge.lastToolCallStatus, .cancelled("cancel-me"))
    }
}
