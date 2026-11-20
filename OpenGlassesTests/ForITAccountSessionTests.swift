import XCTest
import ForITCommon
@testable import OpenGlasses

/// Actual account transitions with isolated stores and transports; no live token or key mint.
@MainActor
final class ForITAccountSessionTests: XCTestCase {
    private let identity = SignInIdentity(idToken: "fixture-identity-token", email: "person@example.test")
    private let credential = ForITAccountSession(key: "dol_fixture", email: "person@example.test")

    private func account(store: TasksFeedbackKey.Store = .memory(),
                         installationStore: TasksFeedbackKey.Store = .memory(),
                         engine: ((String, String, String, String) async throws -> ForITAccountSession)? = nil,
                         feedback: @escaping (String) async throws -> String = { _ in "feedback_fixture" }) -> AppAccount {
        let credential = credential
        return AppAccount(store: store, installationStore: installationStore,
                          engineMint: engine ?? { _, _, _, _ in credential },
                          feedbackMint: feedback, forgetLegacyFeedback: {}, forgetLegacyCredentials: {},
                          retireAccountWork: {}, resumeAccountWork: {})
    }

    private func completeSignIn(_ account: AppAccount) async throws {
        try await account.completeSignIn(code: "fixture-code", codeVerifier: "fixture-verifier", nonce: "fixture-nonce")
    }

    func testCentralAuthMintRejectsWrongKeyKindLabelAndBlankEmail() throws {
        let key = "dol_" + String(repeating: "a", count: 32)
        for (badKey, email, label) in [(" ", "person@example.test", "Phone"),
                                       ("dols_" + String(repeating: "a", count: 32), "person@example.test", "Phone"),
                                       (key, " ", "Phone"), (key, "person@example.test", "Another phone")] {
            let response = try JSONSerialization.data(withJSONObject: ["key": badKey, "email": email, "label": label])
            XCTAssertThrowsError(try ForITAccountSession.decodeMint(response, status: 201, label: "Phone"))
        }
    }

    func testCentralAuthCodeUsesOnlyTheEngineRelyingAppRoute() throws {
        let request = try ForITAccountSession.appSessionRequest(
            code: "fixture-code", codeVerifier: "fixture-verifier", nonce: "fixture-nonce", label: "Fixture iPhone")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://forit-ai-engine.azurewebsites.net/api/api-keys/app-session")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["app": "openglasses", "code": "fixture-code",
                              "codeVerifier": "fixture-verifier", "nonce": "fixture-nonce", "label": "Fixture iPhone"])
    }

    func testCentralAuthRefusalNeverCreatesALocalSession() throws {
        let response = try JSONSerialization.data(withJSONObject: [
            "key": "dol_" + String(repeating: "a", count: 32), "email": "person@example.test", "label": "Phone"
        ])
        for status in [400, 401, 502, 503] {
            XCTAssertThrowsError(try ForITAccountSession.decodeMint(response, status: status, label: "Phone"))
        }
        let session = try ForITAccountSession.decodeMint(response, status: 201, label: "Phone")
        let store = TasksFeedbackKey.Store.memory()
        try session.save(to: store)
        let persisted = try XCTUnwrap(store.load())
        for forbidden in ["fixture-code", "fixture-verifier", "fixture-nonce", "idToken"] {
            XCTAssertFalse(persisted.contains(forbidden))
        }
        XCTAssertEqual(ForITAccountSession.load(from: store), session)
    }

    func testAcceptedIdentityIsPersistedWithoutTheIdentityToken() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store)
        try await self.completeSignIn(account)
        XCTAssertTrue(account.signedIn)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertEqual(account.email, identity.email)
        let raw = try XCTUnwrap(store.load())
        XCTAssertFalse(raw.contains(identity.idToken))
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
        XCTAssertTrue(self.account(store: store).signedIn, "restores the app session without a browser or mint")
    }

    func testFeedbackFailurePreservesSuccessfulEngineLogin() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store, feedback: { _ in throw ForITAccountError.unavailable })
        try await self.completeSignIn(account)
        try await account.connectFeedback(identity)
        XCTAssertTrue(account.signedIn)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNotNil(account.feedbackProblem)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
    }

    func testStorageFailureNeverPublishesSuccessfulLogin() async {
        let store = TasksFeedbackKey.Store(load: { nil }, save: { _ in })
        let account = account(store: store)
        do {
            try await self.completeSignIn(account)
            XCTFail("failed persistence must be a sign-in error")
        } catch { XCTAssertFalse(account.signedIn) }
    }

    func testSignOutClearsBothCredentialsButPreservesInstallationLabel() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let installation = TasksFeedbackKey.Store.memory()
        let account = account(store: store, installationStore: installation)
        try await self.completeSignIn(account)
        try await account.connectFeedback(identity)
        let label = try XCTUnwrap(installation.load())
        XCTAssertLessThanOrEqual(label.count, 64)
        account.signOut()
        XCTAssertFalse(account.signedIn)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNil(store.load())
        XCTAssertEqual(installation.load(), label)
        try await self.completeSignIn(account)
        XCTAssertEqual(installation.load(), label)
    }

    func testLateEngineCompletionCannotRestoreASignedOutAccount() async throws {
        var pending: CheckedContinuation<ForITAccountSession, Error>?
        let started = AsyncStream<Void>.makeStream()
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store, engine: { _, _, _, _ in
            try await withCheckedThrowingContinuation {
                pending = $0
                started.continuation.yield(())
            }
        })
        let task = Task { try await self.completeSignIn(account) }
        var ready = started.stream.makeAsyncIterator()
        _ = await ready.next()
        let continuation = try XCTUnwrap(pending)
        account.signOut()
        continuation.resume(returning: credential)
        do { try await task.value; XCTFail("late completion must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(account.signedIn)
        XCTAssertNil(store.load())
    }

    func testLateFeedbackCompletionCannotRestoreASignedOutAccount() async throws {
        var pending: CheckedContinuation<String, Error>?
        let started = AsyncStream<Void>.makeStream()
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store, feedback: { _ in
            try await withCheckedThrowingContinuation {
                pending = $0
                started.continuation.yield(())
            }
        })
        try await self.completeSignIn(account)
        let task = Task { try await account.connectFeedback(identity) }
        var ready = started.stream.makeAsyncIterator()
        _ = await ready.next()
        let continuation = try XCTUnwrap(pending)
        XCTAssertTrue(account.signedIn)
        account.signOut()
        continuation.resume(returning: "feedback_fixture")
        do { try await task.value; XCTFail("late feedback must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(account.signedIn)
        XCTAssertNil(store.load())
    }

    func testOldUnauthorizedRequestCannotSignOutANewerAccount() throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = account(store: store)
        account.invalidate(key: "older-fixture")
        XCTAssertTrue(account.signedIn)
        account.invalidate(key: credential.key)
        XCTAssertFalse(account.signedIn)
        XCTAssertNil(store.load())
    }

    func testChangingAccountDiscardsThePreviousFeedbackCredential() async throws {
        let store = TasksFeedbackKey.Store.memory()
        try ForITAccountSession(key: "old-engine", email: "old@example.test", feedbackKey: "old-feedback").save(to: store)
        let account = account(store: store, feedback: { _ in throw ForITAccountError.unavailable })
        try await self.completeSignIn(account)
        XCTAssertEqual(account.email, identity.email)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNil(ForITAccountSession.load(from: store)?.feedbackKey)
    }

    func testFeedbackReconnectDoesNotRotateTheEngineKey() async throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = account(store: store, engine: { _, _, _, _ in
            XCTFail("feedback retry must not revoke the engine key")
            throw ForITAccountError.unavailable
        })
        try await account.connectFeedback(identity)
        XCTAssertTrue(account.signedIn)
        XCTAssertTrue(account.feedbackSignedIn)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
    }

    func testFeedbackRefusesADifferentForITAccountBeforeMint() async throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = account(store: store, feedback: { _ in
            XCTFail("feedback must not be minted for another account")
            return "unexpected"
        })
        do {
            try await account.connectFeedback(SignInIdentity(idToken: "fixture-token", email: "other@example.test"))
            XCTFail("expected account mismatch")
        } catch ForITAccountError.identityMismatch {}
        XCTAssertEqual(ForITAccountSession.load(from: store), credential)
    }

    func testOld401DuringReplacementDoesNotCancelTheNewLogin() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let old = ForITAccountSession(key: "old-fixture", email: "old@example.test")
        try old.save(to: store)
        var subject: AppAccount!
        let current = credential
        subject = account(store: store, engine: { _, _, _, _ in
            subject.invalidate(key: old.key)
            return current
        })
        try await self.completeSignIn(subject)
        XCTAssertTrue(subject.signedIn)
        XCTAssertEqual(subject.email, identity.email)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == current.key)
    }

    func testFailedCheckedDeleteIsNotReportedAsSuccessfulSignOut() throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = AppAccount(store: store, installationStore: .memory(),
                                 engineMint: { _, _, _, _ in throw ForITAccountError.unavailable },
                                 feedbackMint: { _ in throw ForITAccountError.unavailable },
                                 forgetLegacyFeedback: {}, forgetLegacyCredentials: {},
                                 deleteSession: { throw ForITAccountError.storage },
                                 retireAccountWork: {}, resumeAccountWork: {})
        account.signOut()
        XCTAssertTrue(account.signedIn)
        XCTAssertNotNil(account.problem)
    }

    func testNativeAppDoesNotEmbedTheFormerSecretsResource() {
        XCTAssertNil(Bundle.main.path(forResource: "Secrets", ofType: "plist"))
    }

    func testAnOldCompletionCannotReleaseANewerAccountTransition() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let started = AsyncStream<Int>.makeStream()
        var first: CheckedContinuation<ForITAccountSession, Error>?
        var second: CheckedContinuation<ForITAccountSession, Error>?
        var calls = 0
        let account = account(store: store, engine: { _, _, _, _ in
            calls += 1
            let call = calls
            return try await withCheckedThrowingContinuation { continuation in
                if call == 1 { first = continuation } else { second = continuation }
                started.continuation.yield(call)
            }
        })
        var ready = started.stream.makeAsyncIterator()
        let oldTask = Task { try await self.completeSignIn(account) }
        _ = await ready.next()
        account.signOut()
        let newTask = Task { try await self.completeSignIn(account) }
        _ = await ready.next()
        try XCTUnwrap(first).resume(returning: credential)
        do { try await oldTask.value; XCTFail("old login must remain cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(account.isChangingCredentials, "the new login still owns its transition")
        try XCTUnwrap(second).resume(returning: credential)
        try await newTask.value
        XCTAssertTrue(account.signedIn)
        XCTAssertFalse(account.isChangingCredentials)
    }
}
