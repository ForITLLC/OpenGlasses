import ForITCommon
import SwiftUI

struct LaunchScreen: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Spacer()

                // Dolores avatar
                Image("DoloresAvatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color(hex: "8EDCEF").opacity(0.5), lineWidth: 2)
                    )
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0)

                // The package owns the mark's geometry and white ink.
                ForITMark(size: 40, surface: .dark)
                    .opacity(isAnimating ? 1.0 : 0)

                Spacer()
            }
        }
        .forITScreenBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    LaunchScreen()
}
