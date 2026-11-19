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
                         engine: ((String, String?, String) async throws -> ForITAccountSession)? = nil,
                         feedback: @escaping (String) async throws -> String = { _ in "feedback_fixture" }) -> AppAccount {
        let credential = credential
        return AppAccount(store: store, installationStore: installationStore,
                          engineMint: engine ?? { _, _, _ in credential },
                          feedbackMint: feedback, forgetLegacyFeedback: {}, forgetLegacyCredentials: {},
                          retireAccountWork: {}, resumeAccountWork: {})
    }

    func testMintUsesSharedBearerContractAndFixedProductionOrigin() throws {
        let request = try ForITAccountSession.mintRequest(idToken: "fixture-token", label: "Fixture iPhone")
        XCTAssertEqual(request.url?.absoluteString, "https://forit-ai-engine.azurewebsites.net/api/api-keys")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["label": "Fixture iPhone"])
    }

    func testMintRejectsDeniedOrMismatchedIdentityAndBlankKey() {
        let good = Data(#"{"key":"dol_fixture","email":"person@example.test"}"#.utf8)
        XCTAssertThrowsError(try ForITAccountSession.decodeMint(good, status: 401, expectedEmail: identity.email))
        XCTAssertThrowsError(try ForITAccountSession.decodeMint(good, status: 201, expectedEmail: "other@example.test"))
        let blank = Data(#"{"key":" ","email":"person@example.test"}"#.utf8)
        XCTAssertThrowsError(try ForITAccountSession.decodeMint(blank, status: 201, expectedEmail: identity.email))
    }

    func testAcceptedIdentityIsPersistedWithoutTheIdentityToken() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store)
        try await account.completeSignIn(identity)
        XCTAssertTrue(account.signedIn)
        XCTAssertTrue(account.feedbackSignedIn)
        XCTAssertEqual(account.email, identity.email)
        let raw = try XCTUnwrap(store.load())
        XCTAssertFalse(raw.contains(identity.idToken))
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
        XCTAssertTrue(self.account(store: store).signedIn, "restores the app session without a browser or mint")
    }

    func testFeedbackFailurePreservesSuccessfulEngineLogin() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store, feedback: { _ in throw ForITAccountError.unavailable })
        try await account.completeSignIn(identity)
        XCTAssertTrue(account.signedIn)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNotNil(account.feedbackProblem)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
    }

    func testStorageFailureNeverPublishesSuccessfulLogin() async {
        let store = TasksFeedbackKey.Store(load: { nil }, save: { _ in })
        let account = account(store: store)
        do {
            try await account.completeSignIn(identity)
            XCTFail("failed persistence must be a sign-in error")
        } catch { XCTAssertFalse(account.signedIn) }
    }

    func testSignOutClearsBothCredentialsButPreservesInstallationLabel() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let installation = TasksFeedbackKey.Store.memory()
        let account = account(store: store, installationStore: installation)
        try await account.completeSignIn(identity)
        let label = try XCTUnwrap(installation.load())
        XCTAssertLessThanOrEqual(label.count, 64)
        account.signOut()
        XCTAssertFalse(account.signedIn)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNil(store.load())
        XCTAssertEqual(installation.load(), label)
        try await account.completeSignIn(identity)
        XCTAssertEqual(installation.load(), label)
    }

    func testLateEngineCompletionCannotRestoreASignedOutAccount() async throws {
        var pending: CheckedContinuation<ForITAccountSession, Error>?
        let started = AsyncStream<Void>.makeStream()
        let store = TasksFeedbackKey.Store.memory()
        let account = account(store: store, engine: { _, _, _ in
            try await withCheckedThrowingContinuation {
                pending = $0
                started.continuation.yield(())
            }
        })
        let task = Task { try await account.completeSignIn(identity) }
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
        let task = Task { try await account.completeSignIn(identity) }
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
        try await account.completeSignIn(identity)
        XCTAssertEqual(account.email, identity.email)
        XCTAssertFalse(account.feedbackSignedIn)
        XCTAssertNil(ForITAccountSession.load(from: store)?.feedbackKey)
    }

    func testFeedbackReconnectDoesNotRotateTheEngineKey() async throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = account(store: store, engine: { _, _, _ in
            XCTFail("feedback retry must not revoke the engine key")
            throw ForITAccountError.unavailable
        })
        try await account.completeSignIn(identity, presentFeedback: true)
        XCTAssertTrue(account.signedIn)
        XCTAssertTrue(account.feedbackSignedIn)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == credential.key)
    }

    func testOld401DuringReplacementDoesNotCancelTheNewLogin() async throws {
        let store = TasksFeedbackKey.Store.memory()
        let old = ForITAccountSession(key: "old-fixture", email: "old@example.test")
        try old.save(to: store)
        var subject: AppAccount!
        let current = credential
        subject = account(store: store, engine: { _, _, _ in
            subject.invalidate(key: old.key)
            return current
        })
        try await subject.completeSignIn(identity)
        XCTAssertTrue(subject.signedIn)
        XCTAssertEqual(subject.email, identity.email)
        XCTAssertTrue(ForITAccountSession.load(from: store)?.key == current.key)
    }

    func testFailedCheckedDeleteIsNotReportedAsSuccessfulSignOut() throws {
        let store = TasksFeedbackKey.Store.memory()
        try credential.save(to: store)
        let account = AppAccount(store: store, installationStore: .memory(),
                                 engineMint: { _, _, _ in throw ForITAccountError.unavailable },
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
}
