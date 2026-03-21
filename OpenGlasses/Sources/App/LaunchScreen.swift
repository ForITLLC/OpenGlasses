import SwiftUI

struct LaunchScreen: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color(hex: "0A1A26").ignoresSafeArea()

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

                // ForIT logo
                Image("ForITLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(hex: "E1EFF3"))
                    .frame(height: 40)
                    .opacity(isAnimating ? 1.0 : 0)

                Spacer()
            }
        }
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
