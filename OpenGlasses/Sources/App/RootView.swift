import SwiftUI
import ForITCommon

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLaunchScreen = true
    @State private var needsOnboarding = Config.doloresAPIKey.isEmpty

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
            if needsOnboarding {
                OnboardingView(onComplete: {
                    withAnimation { needsOnboarding = false }
                })
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

/// First-launch onboarding — just API key
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var apiKey = ""

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                onboardingContent
                    .frame(minHeight: viewport.size.height)
            }
        }
        .forITScreenBackground()
    }

    private var onboardingContent: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()

                Image("DoloresAvatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                Text("Welcome to ForIT Glasses")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text("Ask Bernard in Teams for your API key.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Bernard API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .forITField(on: .navy)

                Button {
                    #if DEBUG
                    guard !OpenGlassesScreenshotFixture.isActive else { return }
                    #endif
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Config.setAPIKey(trimmed)
                    onComplete()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.forITPrimaryOnNavy)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
        }
    }
}
