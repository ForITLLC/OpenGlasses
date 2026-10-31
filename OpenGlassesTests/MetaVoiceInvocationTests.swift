import XCTest
import MWDATCore
@testable import OpenGlasses

/// No SDK transport, permissions or glasses are touched. Only injected launch
/// callbacks and response handles are used; this does not prove hardware launch.
@MainActor
final class MetaVoiceInvocationTests: XCTestCase {
    private actor ReplyHandle: ResponseHandle {
        private var success = 0
        private var failure = 0
        let delivered: Bool
        init(delivered: Bool = true) { self.delivered = delivered }
        func sendSuccess(actionOutput: String?) async -> Bool { success += 1; return delivered }
        func sendFailure(actionOutput: String?) async -> Bool { failure += 1; return delivered }
        func counts() -> [Int] { [success, failure] }
    }

    private func unconfigured(_ body: () async throws -> Void) async rethrows {
        let saved = WearablesRuntime.isConfigured
        WearablesRuntime.isConfigured = false
        defer { WearablesRuntime.isConfigured = saved }
        try await body()
    }

    func testLaunchAcknowledgesOnlyAfterListeningStarts() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            var started = false
            service.start { started = true }
            let reply = ReplyHandle()
            await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            XCTAssertTrue(started)
            let counts = await reply.counts()
            XCTAssertEqual(counts, [1, 0])
            service.stop()
        }
    }

    func testFailedListeningGetsExactlyOneFailure() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            service.start { throw NSError(domain: "synthetic-microphone", code: 1) }
            let reply = ReplyHandle()
            await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            let counts = await reply.counts()
            XCTAssertEqual(counts, [0, 1])
            service.stop()
        }
    }

    func testStoppedServiceDoesNotStartAndDoesNotClaimSuccess() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            var started = false
            service.start { started = true }
            service.stop()
            let reply = ReplyHandle()
            await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            XCTAssertFalse(started)
            let counts = await reply.counts()
            XCTAssertEqual(counts, [0, 1])
        }
    }

    func testFailedAcknowledgementIsNotRetriedOrReportedDelivered() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            service.start { }
            let reply = ReplyHandle(delivered: false)
            await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            let counts = await reply.counts()
            XCTAssertEqual(counts, [1, 0])
            XCTAssertEqual(service.lastError, "The launch reply did not reach Meta.")
            service.stop()
        }
    }

    func testUnconfiguredURLHandlingDoesNotTouchSDK() async throws {
        try await unconfigured {
            let service = MetaVoiceInvocationService()
            let handled = try await service.handleURL(URL(string: "mwdat-688603774243722://launch")!)
            XCTAssertFalse(handled)
            XCTAssertFalse(MetaVoiceInvocationService.isDATURL(URL(string: "https://example.invalid/callback")!))
        }
    }

    func testResponseStopRecognizerDoesNotStartAnIdleWakeListener() async throws {
        let service = WakeWordService()
        service.listenForStop = false
        try await service.startListening()
        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.getAudioEngine())
    }
}
