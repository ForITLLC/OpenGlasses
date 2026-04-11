import SwiftUI

struct RootView: View {
    @State private var showLaunchScreen = true
    @State private var needsOnboarding = Config.doloresAPIKey.isEmpty

    var body: some View {
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
}

/// First-launch onboarding — just API key
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var apiKey = ""

    var body: some View {
        ZStack {
            Color(hex: "0A1A26").ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image("DoloresAvatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                Text("Welcome to ForIT Glasses")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Ask Dolores in Teams for your API key.")
                    .font(.body)
                    .foregroundColor(Color(hex: "8EDCEF").opacity(0.7))
                    .multilineTextAlignment(.center)

                TextField("Dolores API Key", text: $apiKey)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)

                Button {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Config.setAPIKey(trimmed)
                    onComplete()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "8EDCEF"))
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
                Spacer()
            }
        }
    }
}
