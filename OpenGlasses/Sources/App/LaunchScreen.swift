import SwiftUI

struct LaunchScreen: View {
    @State private var isAnimating = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            // Dark background matching the crab image
            Color(red: 0.14, green: 0.14, blue: 0.14)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Crab mascot image from intro video
                ZStack {
                    // Glow effect behind the crab
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(glowPulse ? 0.3 : 0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: glowPulse
                        )

                    Image("LaunchImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .scaleEffect(isAnimating ? 1.0 : 0.85)
                        .opacity(isAnimating ? 1.0 : 0)
                }

                Spacer()
                    .frame(height: 32)

                // App name
                Text("OpenGlasses")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(isAnimating ? 1.0 : 0)

                // Tagline
                Text("Voice-Powered AI Assistant")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 8)
                    .opacity(isAnimating ? 1.0 : 0)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
            glowPulse = true
        }
    }
}

#Preview {
    LaunchScreen()
}
