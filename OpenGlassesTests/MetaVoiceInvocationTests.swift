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

    @MainActor
    private final class SuspendedStartup {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        init(_ description: String) { entered = XCTestExpectation(description: description) }

        func wait() async {
            await withCheckedContinuation { continuation in
                if released { continuation.resume() }
                else { self.continuation = continuation }
                entered.fulfill()
            }
        }

        func release() {
            released = true
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
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

    func testStoppedPendingLaunchGetsOneFailureWithoutChangingCurrentError() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            let startup = SuspendedStartup("Launch startup suspended")
            service.start { await startup.wait() }
            let reply = ReplyHandle(delivered: false)
            let launch = Task {
                await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            }
            await fulfillment(of: [startup.entered], timeout: 5)
            service.stop()
            let currentError = service.lastError
            startup.release()
            await launch.value

            let counts = await reply.counts()
            XCTAssertEqual(counts, [0, 1])
            XCTAssertEqual(service.lastError, currentError)
        }
    }

    func testRestartedLaunchKeepsOwnershipWhenOldStartupCompletes() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            let oldStartup = SuspendedStartup("Old launch suspended")
            service.start { await oldStartup.wait() }
            let oldReply = ReplyHandle()
            let oldLaunch = Task {
                await service.handleLaunch(LaunchApp(responseHandle: oldReply, deviceIdentifier: "synthetic"))
            }
            await fulfillment(of: [oldStartup.entered], timeout: 5)
            service.stop()

            let newStartup = SuspendedStartup("New launch suspended")
            var starts = 0
            service.start {
                starts += 1
                guard starts == 1 else { return }
                await newStartup.wait()
            }
            let newReply = ReplyHandle()
            let newLaunch = Task {
                await service.handleLaunch(LaunchApp(responseHandle: newReply, deviceIdentifier: "synthetic"))
            }
            await fulfillment(of: [newStartup.entered], timeout: 5)
            oldStartup.release()
            await oldLaunch.value
            guard starts == 1 else {
                XCTFail("A stopped launch must not block the next lifecycle")
                newStartup.release()
                await newLaunch.value
                service.stop()
                return
            }

            // An old invocation's defer must not clear the new launch's busy state.
            let busyReply = ReplyHandle()
            await service.handleLaunch(LaunchApp(responseHandle: busyReply, deviceIdentifier: "synthetic"))
            let busyCounts = await busyReply.counts()
            XCTAssertEqual(busyCounts, [0, 1])
            XCTAssertEqual(starts, 1)

            newStartup.release()
            await newLaunch.value
            let oldCounts = await oldReply.counts()
            let newCounts = await newReply.counts()
            XCTAssertEqual(oldCounts, [0, 1])
            XCTAssertEqual(newCounts, [1, 0])
            service.stop()
        }
    }

    func testStoppedPendingLaunchErrorCannotReplaceRestartedState() async {
        await unconfigured {
            let service = MetaVoiceInvocationService()
            let startup = SuspendedStartup("Failing launch suspended")
            service.start {
                await startup.wait()
                throw NSError(domain: "stale-microphone", code: 1)
            }
            let reply = ReplyHandle()
            let launch = Task {
                await service.handleLaunch(LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
            }
            await fulfillment(of: [startup.entered], timeout: 5)
            service.stop()
            service.start { }
            let currentError = service.lastError
            startup.release()
            await launch.value

            let counts = await reply.counts()
            XCTAssertEqual(counts, [0, 1])
            XCTAssertEqual(service.lastError, currentError)
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
