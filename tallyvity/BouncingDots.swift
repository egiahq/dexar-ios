import SwiftUI

struct BouncingDots: View {
    var dotSize: CGFloat = 7
    var spacing: CGFloat = 7
    var lift: CGFloat = 11
    var color: Color = .primary

    @State private var animating = false

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animating ? -lift : 0)
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.13),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

#Preview {
    VStack(spacing: 40) {
        BouncingDots()
        BouncingDots(dotSize: 5, spacing: 5, lift: 8, color: .secondary)
        BouncingDots(dotSize: 10, spacing: 10, lift: 14)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.appBackground)
}
