import SwiftUI
import ForITCommon

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLaunchScreen = true
    @ObservedObject private var account = AppAccount.shared

    var body: some View {
        Group {
            #if DEBUG
            if let scene = OpenGlassesScreenshotFixture.scene {
                fixtureContent(scene)
                    .onAppear { OpenGlassesScreenshotFixture.prepare(appState) }
            } else {
                liveContent
            }
            #else
            liveContent
            #endif
        }
        .forITScreenBackground()
        .forITScreenHarness()
    }

    private var liveContent: some View {
        ZStack {
            if !account.signedIn {
                OnboardingView(onComplete: {})
            } else {
                MainView()
            }

            if showLaunchScreen {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private func fixtureContent(_ scene: OpenGlassesScreenshotFixture.Scene) -> some View {
        switch scene {
        case .gate:
            OnboardingView(onComplete: {})
        case .home, .detail, .settings:
            MainView()
        case .launch:
            LaunchScreen()
        }
    }
    #endif
}

/// The shared native Central Auth gate.
@MainActor
struct OnboardingView: View {
    let onComplete: () -> Void
    @ObservedObject private var account = AppAccount.shared
    @State private var windowSource = AuthWindowReader.WindowSource()

    var body: some View {
        ForITCentralAuthSignInGate(signIn: account.signIn,
                        subtitle: "Sign in to talk to Bernard on your glasses.",
                        error: account.problem, isBusy: account.isSigningIn) {
            account.signInAccount(from: windowSource.window)
        }
        .background(AuthWindowReader(source: windowSource))
        .onChange(of: account.signedIn) { _, signedIn in if signedIn { onComplete() } }
    }
}
