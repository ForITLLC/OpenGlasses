import AuthenticationServices
import ForITCommon
import SwiftUI
import UIKit

/// The Bernard account uses central Auth. Feedback has a separate Tasks credential.
@MainActor
final class AppAccount: ObservableObject {
    static let shared = AppAccount(deleteSession: ForITAccountSession.deletePersistedSession)

    nonisolated static let epicId = "08106FD9-AFFA-4041-90B5-F50B4BBD308F"
    /// The existing Tasks feedback browser registration keeps this callback.
    nonisolated static let redirectURI = URL(string: "io.forit.glasses://oauth/callback")!
    static let authConfiguration = try! CentralAuthConfiguration(
        authority: URL(string: "https://auth.forit.io")!, app: "openglasses",
        callback: URL(string: "https://ai.forit.io/glasses/auth/callback")!, provider: "microsoft")
    let signIn = CentralAuthBrowserSignIn(configuration: authConfiguration)
    private let feedbackSignIn = BrowserSignIn(configuration: .forIT(redirectURI: AppAccount.redirectURI))
    let center: FeedbackCenter
    @Published private(set) var session: ForITAccountSession?
    @Published private(set) var isSigningIn = false
    @Published private(set) var isChangingCredentials = false
    @Published var feedbackProblem: String?
    private let store: TasksFeedbackKey.Store
    private let installationStore: TasksFeedbackKey.Store
    private let engineMint: (String, String, String, String) async throws -> ForITAccountSession
    private let feedbackMint: (String) async throws -> String
    private let forgetLegacyFeedback: () -> Void
    private let forgetLegacyCredentials: () -> Void
    private let deleteSession: () throws -> Void
    private let retireAccountWork: @MainActor () -> Void
    private let resumeAccountWork: @MainActor () -> Void
    private var rejectedWhileChanging: String?
    private var generation = UUID()
    private var signInTask: Task<Void, Never>?

    var signedIn: Bool { session != nil }
    var email: String? { session?.email }
    var feedbackSignedIn: Bool { session?.feedbackKey != nil }

    var profileAccount: ForITProfileAccount? {
        guard signedIn else { return nil }
        return ForITProfileAccount(id: email ?? "forit-feedback", name: email ?? "ForIT account")
    }

    /// Why sign-in didn't work, shown in an alert.
    @Published var problem: String?
    @Published var askingSignIn = false
    @Published var confirmingSignOut = false

    init(store: TasksFeedbackKey.Store = ForITAccountSession.store,
         installationStore: TasksFeedbackKey.Store = ForITAccountSession.installationStore,
         engineMint: @escaping (String, String, String, String) async throws -> ForITAccountSession = ForITAccountSession.mintAppSession,
         feedbackMint: @escaping (String) async throws -> String = { token in
             // Stage in memory so a late completion cannot restore a signed-out account.
             try await TasksFeedbackKey(store: .memory()).mint(idToken: token, appLabel: "ForIT Glasses (feedback)")
         }, forgetLegacyFeedback: @escaping () -> Void = {
             TasksFeedbackKey.shared.forget()
             UserDefaults.standard.removeObject(forKey: "feedbackAccountEmail")
         }, forgetLegacyCredentials: @escaping () -> Void = {
             for key in ["doloresAPIKey", "userEmail", "doloresBaseURL"] {
                 UserDefaults.standard.removeObject(forKey: key)
             }
         }, deleteSession: (() throws -> Void)? = nil,
         retireAccountWork: (@MainActor () -> Void)? = nil,
         resumeAccountWork: (@MainActor () -> Void)? = nil) {
        self.store = store
        self.installationStore = installationStore
        self.engineMint = engineMint
        self.feedbackMint = feedbackMint
        self.forgetLegacyFeedback = forgetLegacyFeedback
        self.forgetLegacyCredentials = forgetLegacyCredentials
        self.deleteSession = deleteSession ?? {
            store.save(nil)
            guard store.load() == nil else { throw ForITAccountError.storage }
        }
        self.retireAccountWork = retireAccountWork ?? { AppStateProvider.shared?.suspendForSignOut() }
        self.resumeAccountWork = resumeAccountWork ?? {
            AppStateProvider.shared?.locationService.startTracking()
            AppStateProvider.shared?.startMetaVoiceLaunch()
        }
        #if DEBUG
        let restored = OpenGlassesScreenshotFixture.isActive ? nil : ForITAccountSession.load(from: store)
        #else
        let restored = ForITAccountSession.load(from: store)
        #endif
        center = FeedbackCenter(
            sender: TasksFeedbackSender(epicId: Self.epicId, laneName: "OpenGlasses", credential: {
                #if DEBUG
                guard !OpenGlassesScreenshotFixture.isActive else { return nil }
                #endif
                return ForITAccountSession.load(from: store)?.feedbackKey.map(TasksCredential.apiKey)
            }),
            shakeToReport: restored?.feedbackKey != nil)
        session = restored
    }

    func signInAccount(from window: UIWindow?) {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return }
        #endif
        guard !isSigningIn else { return }
        guard let window else {
            problem = CentralAuthError.browserUnavailable.localizedDescription
            return
        }
        let anchor = AuthWindowProvider(window: window)
        startSignIn { attempt in
            let grant = try await self.signIn.signIn(presentationContextProvider: anchor)
            try await self.completeSignIn(code: grant.code, codeVerifier: grant.codeVerifier,
                                                 nonce: grant.nonce, attempt: attempt)
        }
    }

    /// The injected exchange lets tests exercise account transitions without a browser.
    func completeSignIn(code: String, codeVerifier: String, nonce: String, attempt: UUID? = nil) async throws {
        let attempt = attempt ?? generation
        guard generation == attempt, !Task.isCancelled else { throw CancellationError() }
        let label: String
        if let existing = installationStore.load(), !existing.isEmpty {
            label = existing
        } else {
            label = "ForIT Glasses iPhone " + UUID().uuidString
            installationStore.save(label)
            guard installationStore.load() == label else { throw ForITAccountError.storage }
        }

        isChangingCredentials = true
        center.close()
        retireAccountWork()
        defer {
            if generation == attempt {
                isChangingCredentials = false
                if let rejected = rejectedWhileChanging {
                    rejectedWhileChanging = nil
                    invalidate(key: rejected)
                }
                if signedIn { resumeAccountWork() }
            }
        }

        var minted = try await engineMint(code, codeVerifier, nonce, label)
        guard generation == attempt, !Task.isCancelled else { throw CancellationError() }
        if let current = session, Self.sameAccount(current.email, minted.email) {
            minted.feedbackKey = current.feedbackKey
        }
        try minted.save(to: store)
        session = minted
        center.shakeToReport = minted.feedbackKey != nil
        feedbackProblem = nil
        forgetLegacyCredentials()
    }

    func signInForFeedback() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return }
        #endif
        guard signedIn, !isSigningIn else { return }
        startSignIn { attempt in
            let identity = try await self.feedbackSignIn.signIn { url in await UIApplication.shared.open(url) }
            try await self.connectFeedback(identity, attempt: attempt, presentFeedback: true)
        }
    }

    func connectFeedback(_ identity: SignInIdentity, attempt: UUID? = nil, presentFeedback: Bool = false) async throws {
        let attempt = attempt ?? generation
        guard generation == attempt, !Task.isCancelled else { throw CancellationError() }
        guard let current = session, let email = identity.email, Self.sameAccount(email, current.email) else {
            throw ForITAccountError.identityMismatch
        }
        feedbackProblem = nil
        do {
            let key = try await feedbackMint(identity.idToken)
            guard generation == attempt, !Task.isCancelled, session?.key == current.key else {
                throw CancellationError()
            }
            guard !key.isEmpty else { throw ForITAccountError.unavailable }
            var connected = current
            connected.feedbackKey = key
            try connected.save(to: store)
            session = connected
            center.shakeToReport = true
            if presentFeedback { center.present() }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard generation == attempt, session?.key == current.key else { throw CancellationError() }
            if ForITAccountSession.load(from: store) != current {
                do { try current.save(to: store) }
                catch {
                    session = nil
                    center.shakeToReport = false
                    retireAccountWork()
                    throw ForITAccountError.storage
                }
            }
            feedbackProblem = "Feedback couldn’t connect. Try signing in for feedback again."
        }
    }

    private func startSignIn(_ action: @escaping (UUID) async throws -> Void) {
        problem = nil
        isSigningIn = true
        let attempt = UUID()
        generation = attempt
        signInTask = Task {
            defer { if generation == attempt { isSigningIn = false; signInTask = nil } }
            do {
                try Task.checkCancellation()
                try await action(attempt)
            } catch CentralAuthError.cancelled {
            } catch SignInError.cancelled {
            } catch is CancellationError {
            } catch {
                guard generation == attempt else { return }
                problem = (error as? ForITAccountError)?.localizedDescription
                    ?? (error as? CentralAuthError)?.localizedDescription
                    ?? "Couldn’t finish signing you in. Try again."
            }
        }
    }

    private static func sameAccount(_ first: String, _ second: String) -> Bool {
        first.caseInsensitiveCompare(second) == .orderedSame
    }

    /// An old request must never sign out a newer account that has replaced its key.
    func invalidate(key: String) {
        guard session?.key == key else { return }
        if isChangingCredentials { rejectedWhileChanging = key; return }
        signOut()
        if !signedIn { problem = "Please sign in with your ForIT account again." }
    }

    /// The sign-in redirect; false for any other link.
    func handle(_ url: URL) -> Bool {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return false }
        #endif
        return feedbackSignIn.handle(url)
    }

    func signOut() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return }
        #endif
        generation = UUID()
        isChangingCredentials = false
        rejectedWhileChanging = nil
        signInTask?.cancel()
        signInTask = nil
        signIn.cancel()
        feedbackSignIn.cancel()
        center.close()
        retireAccountWork()
        do { try deleteSession() }
        catch {
            problem = "Couldn't clear your saved sign-in. Try signing out again."
            isSigningIn = false
            if signedIn { resumeAccountWork() }
            return
        }
        forgetLegacyFeedback()
        session = nil
        isSigningIn = false
        problem = nil
        feedbackProblem = nil
        rejectedWhileChanging = nil
        center.shakeToReport = false
    }

    /// True for a link on the sign-in redirect's scheme. Those never go to the Meta SDK.
    nonisolated static func isSignInLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURI.scheme
    }
}

/// Settings' Feedback section: Send feedback, and Sign out of ForIT once signed in. The list that
/// holds it carries `feedbackDialogs()`.
struct FeedbackSection: View {
    @ObservedObject private var account = AppAccount.shared

    var body: some View {
        Section {
            if account.feedbackSignedIn {
                ForITFeedbackButton()
                    .environment(\.forITFeedback, account.center)
                    .foregroundColor(Color(hex: "E1EFF3"))
            } else {
                Button {
                    account.askingSignIn = true
                } label: {
                    Label("Send feedback", systemImage: "exclamationmark.bubble")
                        .foregroundColor(Color(hex: "E1EFF3"))
                }
            }
        } header: {
            Text("Feedback")
        } footer: {
            Text(account.signedIn
                ? account.feedbackProblem ?? (account.feedbackSignedIn
                    ? "Shake your phone to send feedback from any screen."
                    : "Sign in for feedback to send it under your name.")
                : "Feedback goes to ForIT's board under your name, so it needs your ForIT account.")
                .foregroundColor(Color(hex: "E1EFF3").opacity(0.4))
        }
    }
}

/// The dialogs FeedbackSection opens. On the List that holds the section, not on its rows.
private struct FeedbackDialogs: ViewModifier {
    let isEnabled: Bool
    @ObservedObject private var account = AppAccount.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Send feedback", isPresented: presentation($account.askingSignIn), titleVisibility: .visible) {
                Button("Sign in with ForIT") { account.signInForFeedback() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use the same ForIT account to connect feedback.")
            }
            .confirmationDialog("Sign out of ForIT?", isPresented: presentation($account.confirmingSignOut), titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { account.signOut() }
            } message: {
                Text("This iPhone will stop listening and ask you to sign in again.")
            }
            .alert("ForIT account", isPresented: Binding(get: { isEnabled && account.problem != nil },
                                                         set: { if isEnabled && !$0 { account.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(account.problem ?? "")
            }
    }

    private func presentation(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { isEnabled && value.wrappedValue },
                set: { if isEnabled { value.wrappedValue = $0 } })
    }
}

extension View {
    func feedbackDialogs(isEnabled: Bool = true) -> some View {
        modifier(FeedbackDialogs(isEnabled: isEnabled))
    }
}
