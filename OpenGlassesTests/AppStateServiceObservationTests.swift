import XCTest
import MWDATCore
@testable import OpenGlasses

/// Exercises the real service publishers and AppState subscriptions, without
/// configuring DAT, opening a microphone or making a provider request.
@MainActor
final class AppStateServiceObservationTests: XCTestCase {
    private actor ReplyHandle: ResponseHandle {
        func sendSuccess(actionOutput: String?) async -> Bool { true }
        func sendFailure(actionOutput: String?) async -> Bool { true }
    }

    private actor PendingReplyHandle: ResponseHandle {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Bool, Never>?
        private var releasedDelivery: Bool?

        init(entered: XCTestExpectation) { self.entered = entered }

        func sendSuccess(actionOutput: String?) async -> Bool { await wait() }
        func sendFailure(actionOutput: String?) async -> Bool { await wait() }

        private func wait() async -> Bool {
            await withCheckedContinuation { continuation in
                if let releasedDelivery { continuation.resume(returning: releasedDelivery) }
                else { self.continuation = continuation }
                entered.fulfill()
            }
        }

        func release(delivered: Bool) {
            releasedDelivery = delivered
            continuation?.resume(returning: delivered)
            continuation = nil
        }
    }

    @MainActor
    private final class PendingLaunch {
        let entered = XCTestExpectation(description: "Launch callback entered")
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            await withCheckedContinuation { continuation in
                if released { continuation.resume() }
                else { self.continuation = continuation }
                entered.fulfill()
            }
        }

        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func withState(_ body: (AppState) async -> Void) async {
        let configured = WearablesRuntime.isConfigured
        let sharedState = AppStateProvider.shared
        let registered = UserDefaults.standard.object(forKey: "hasRegisteredWithMeta")
        WearablesRuntime.isConfigured = false
        defer {
            WearablesRuntime.isConfigured = configured
            AppStateProvider.shared = sharedState
            if let registered {
                UserDefaults.standard.set(registered, forKey: "hasRegisteredWithMeta")
            } else {
                UserDefaults.standard.removeObject(forKey: "hasRegisteredWithMeta")
            }
        }
        // The hosted-test fixture skips startup effects, but not service bindings.
        let state = AppState()
        state.listeningEnabled = true
        await body(state)
        state.metaVoiceService.stop()
    }

    func testRegistrationDoesNotClaimALinkAndDisconnectReachesAppState() async {
        await withState { state in
            state.updateRegistrationState(.registered)
            XCTAssertEqual(state.registrationStateRaw, RegistrationState.registered.rawValue)
            XCTAssertFalse(state.isConnected, "Registration alone cannot turn the connection light green")

            state.glassesService.isConnected = true
            XCTAssertTrue(state.isConnected)
            state.glassesService.disconnect()
            XCTAssertFalse(state.isConnected, "The actual service's disconnect must reach the UI")

            state.updateRegistrationState(.registered)
            XCTAssertFalse(state.isConnected, "A later registration refresh cannot hide a lost link")
        }
    }

    func testUnregistrationDoesNotReplaceTheObservedDeviceLink() async {
        await withState { state in
            state.glassesService.isConnected = true
            state.updateRegistrationState(.available)
            XCTAssertEqual(state.registrationStateRaw, RegistrationState.available.rawValue)
            XCTAssertTrue(state.isConnected, "Registration and the physical link are separate states")
            state.glassesService.disconnect()
            XCTAssertFalse(state.isConnected)
        }
    }

    func testMetaFailureAppearsAndSuccessfulLaunchClearsIt() async {
        await withState { state in
            state.metaVoiceService.start { }
            XCTAssertEqual(state.errorMessage, "Meta voice launch: Meta SDK not registered")
            await state.metaVoiceService.handleLaunch(
                LaunchApp(responseHandle: ReplyHandle(), deviceIdentifier: "synthetic"))
            XCTAssertNil(state.metaVoiceService.lastError)
            XCTAssertNil(state.errorMessage)
        }
    }

    func testStoppingMetaClearsItsDisplayedFailure() async {
        await withState { state in
            state.metaVoiceService.start { }
            XCTAssertNotNil(state.errorMessage)
            state.metaVoiceService.stop()
            XCTAssertNil(state.metaVoiceService.lastError)
            XCTAssertNil(state.errorMessage)
        }
    }

    func testRecoveryAndStopPreserveAnUnrelatedError() async {
        await withState { state in
            state.metaVoiceService.start { }
            state.errorMessage = "The camera could not capture a photo."
            await state.metaVoiceService.handleLaunch(
                LaunchApp(responseHandle: ReplyHandle(), deviceIdentifier: "synthetic"))
            XCTAssertEqual(state.errorMessage, "The camera could not capture a photo.")
            state.metaVoiceService.stop()
            XCTAssertEqual(state.errorMessage, "The camera could not capture a photo.")
        }
    }

    func testAnotherWriterOwnsEvenIdenticalErrorText() async {
        await withState { state in
            state.metaVoiceService.start { }
            let independentlyReportedError = state.errorMessage
            state.errorMessage = independentlyReportedError
            state.metaVoiceService.stop()
            XCTAssertEqual(state.errorMessage, independentlyReportedError,
                           "String equality alone must not grant Meta ownership of another writer's error")
        }
    }

    func testMetaFailureDoesNotReplaceAnExistingUnrelatedError() async {
        await withState { state in
            state.errorMessage = "Bernard is unavailable."
            state.metaVoiceService.start { }
            XCTAssertNotNil(state.metaVoiceService.lastError)
            XCTAssertEqual(state.errorMessage, "Bernard is unavailable.")
            state.metaVoiceService.stop()
            XCTAssertEqual(state.errorMessage, "Bernard is unavailable.")
        }
    }

    func testStoppedSuspendedFailureCannotReturnAfterRecovery() async {
        await withState { state in
            let pending = PendingLaunch()
            state.metaVoiceService.start {
                await pending.wait()
                throw NSError(domain: "stale-launch", code: 1)
            }
            let oldLaunch = Task {
                await state.metaVoiceService.handleLaunch(
                    LaunchApp(responseHandle: ReplyHandle(), deviceIdentifier: "synthetic"))
            }
            await fulfillment(of: [pending.entered], timeout: 5)
            state.metaVoiceService.stop()
            state.metaVoiceService.start { }
            await state.metaVoiceService.handleLaunch(
                LaunchApp(responseHandle: ReplyHandle(), deviceIdentifier: "synthetic"))
            XCTAssertNil(state.errorMessage)

            pending.release()
            await oldLaunch.value
            XCTAssertNil(state.metaVoiceService.lastError)
            XCTAssertNil(state.errorMessage, "A retired launch cannot republish its failure")
        }
    }

    func testOldAcknowledgementCannotClearOrReplaceANewerServiceError() async {
        for delivered in [true, false] {
            await withState { state in
                state.metaVoiceService.start { }
                let entered = XCTestExpectation(description: "Launch acknowledgement suspended")
                let reply = PendingReplyHandle(entered: entered)
                let launch = Task {
                    await state.metaVoiceService.handleLaunch(
                        LaunchApp(responseHandle: reply, deviceIdentifier: "synthetic"))
                }
                await fulfillment(of: [entered], timeout: 5)
                // A new start attempt reports a current failure while the previous
                // response is in flight. Its text can match the previous failure.
                state.metaVoiceService.start { }
                let currentError = state.metaVoiceService.lastError
                XCTAssertNotNil(currentError)
                await reply.release(delivered: delivered)
                await launch.value
                XCTAssertEqual(state.metaVoiceService.lastError, currentError)
                XCTAssertEqual(state.errorMessage, "Meta voice launch: Meta SDK not registered")
            }
        }
    }
}
