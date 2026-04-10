import SwiftUI

struct RootView: View {
    @State private var showLaunchScreen = true
    @State private var needsOnboarding = Config.userEmail.isEmpty

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

/// First-launch onboarding — just asks for email
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var email = ""

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

                Text("Enter your ForIT email to get started.")
                    .font(.body)
                    .foregroundColor(Color(hex: "8EDCEF").opacity(0.7))

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)

                Button {
                    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !trimmed.isEmpty, trimmed.contains("@") else { return }
                    Config.setUserEmail(trimmed)
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
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
                Spacer()
            }
        }
    }
}
