import ForITCommon
import SwiftUI
import UIKit

/// Send feedback (FB-1, task 942E1773; for-iCommon docs/feedback.md).
///
/// A report is a tasks.forit.io task under the app's feedback epic, authored by the person who
/// sent it, so sending needs a ForIT account. Bernard doesn't: the app runs on its engine API key,
/// and ForIT Sign-in is asked for only the first time someone taps Send feedback. The id_token it
/// hands back lives about an hour; while it is fresh, TasksFeedbackKey mints the board key the
/// sender uses from then on and keeps it in the Keychain. Sign out forgets it.
@MainActor
final class FeedbackAccount: ObservableObject {
    static let shared = FeedbackAccount()

    /// ForIT Glasses' feedback epic; the task-feedback rail takes what lands under it to OpenGlasses.
    nonisolated static let epicId = "08106FD9-AFFA-4041-90B5-F50B4BBD308F"
    /// Must be in CFBundleURLTypes (project.yml) and enrolled on the ForIT Sign-in registration.
    nonisolated static let redirectURI = URL(string: "io.forit.glasses://oauth/callback")!
    private static let emailKey = "feedbackAccountEmail"

    let signIn = BrowserSignIn(configuration: .forIT(redirectURI: FeedbackAccount.redirectURI))
    let center: FeedbackCenter
    @Published private(set) var signedIn: Bool
    @Published private(set) var email: String?

    /// The feedback identity only; the engine account in Settings is independent.
    var profileAccount: ForITProfileAccount? {
        guard signedIn else { return nil }
        return ForITProfileAccount(id: email ?? "forit-feedback", name: email ?? "ForIT account")
    }

    /// Why sign-in didn't work, shown in an alert.
    @Published var problem: String?
    @Published var askingSignIn = false
    @Published var confirmingSignOut = false

    private init() {
        let key = TasksFeedbackKey.shared
        #if DEBUG
        let signedIn = !OpenGlassesScreenshotFixture.isActive && key.current != nil
        #else
        let signedIn = key.current != nil
        #endif
        center = FeedbackCenter(
            sender: TasksFeedbackSender(epicId: Self.epicId, laneName: "OpenGlasses", credential: {
                #if DEBUG
                guard !OpenGlassesScreenshotFixture.isActive else { return nil }
                #endif
                return key.credential
            }),
            shakeToReport: signedIn)
        self.signedIn = signedIn
        email = signedIn ? UserDefaults.standard.string(forKey: Self.emailKey) : nil
    }

    /// Sign in in the browser, mint the board key, then open the feedback sheet. Tapping again
    /// while the browser is still open starts over (BrowserSignIn cancels the waiting attempt).
    func signInForFeedback() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return }
        #endif
        Task {
            do {
                let identity = try await signIn.signIn { url in await UIApplication.shared.open(url) }
                try await TasksFeedbackKey.shared.mint(idToken: identity.idToken, appLabel: "ForIT Glasses (feedback)")
                UserDefaults.standard.set(identity.email, forKey: Self.emailKey)
                email = identity.email
                signedIn = true
                center.shakeToReport = true
                center.present()
            } catch SignInError.cancelled {
            } catch FeedbackError.unauthorized {
                problem = "Feedback from the app is for ForIT accounts."
            } catch {
                problem = "Couldn't sign in (\(error.localizedDescription))."
            }
        }
    }

    /// The sign-in redirect; false for any other link.
    func handle(_ url: URL) -> Bool {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return false }
        #endif
        return signIn.handle(url)
    }

    func signOut() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.isActive else { return }
        #endif
        TasksFeedbackKey.shared.forget()
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        email = nil
        signedIn = false
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
    @ObservedObject private var account = FeedbackAccount.shared

    var body: some View {
        Section {
            if account.signedIn {
                ForITFeedbackButton()
                    .environment(\.forITFeedback, account.center)
                    .foregroundColor(Color(hex: "E1EFF3"))
                Button {
                    account.confirmingSignOut = true
                } label: {
                    Label("Sign out of ForIT", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(Color(hex: "E1EFF3"))
                }
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
                ? "\(account.email.map { "Signed in as \($0). " } ?? "")Shake your phone to send feedback from any screen."
                : "Feedback goes to ForIT's board under your name, so it needs your ForIT account.")
                .foregroundColor(Color(hex: "E1EFF3").opacity(0.4))
        }
    }
}

/// The dialogs FeedbackSection opens. On the List that holds the section, not on its rows.
private struct FeedbackDialogs: ViewModifier {
    let isEnabled: Bool
    @ObservedObject private var account = FeedbackAccount.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Send feedback", isPresented: presentation($account.askingSignIn), titleVisibility: .visible) {
                Button("Sign in with ForIT") { account.signInForFeedback() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Feedback goes to ForIT's board under your name, so it needs your ForIT account. Bernard works without one.")
            }
            .confirmationDialog("Sign out of ForIT?", isPresented: presentation($account.confirmingSignOut), titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { account.signOut() }
            } message: {
                Text("Sending feedback will ask you to sign in again. Bernard keeps working.")
            }
            .alert("Send feedback", isPresented: Binding(get: { isEnabled && account.problem != nil },
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
