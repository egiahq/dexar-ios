import SwiftUI

struct TimerRingView: View {
    let progress: Double   // 0 = start, 1 = done
    let isWork: Bool
    let remainingTime: TimeInterval

    @State private var pulsing = false

    private var isOvertime: Bool { remainingTime < 0 }
    private var remaining: Double { max(0, min(1, 1 - progress)) }

    private var arcColor: Color {
        if isOvertime { return Color.appDestructive }
        return isWork
            ? Color(hue: 0.06, saturation: 0.70, brightness: 0.92)
            : Color(hue: 0.36, saturation: 0.42, brightness: 0.70)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * 0.10

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: lineWidth)

                TimerArc(remaining: remaining)
                    .stroke(
                        arcColor.opacity(pulsing ? 0.78 : 1.0),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .animation(.linear(duration: 0.25), value: remaining)
                    .animation(
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                        value: pulsing
                    )

                Text(formattedTime)
                    .font(.system(size: size * 0.17, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOvertime ? Color.appDestructive : .secondary)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pulsing = true
            }
        }
    }

    private var formattedTime: String {
        let negative = remainingTime < 0
        let total = Int(abs(remainingTime).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return (negative ? "-" : "") + String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TimerArc: Shape {
    var remaining: Double

    var animatableData: Double {
        get { remaining }
        set { remaining = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(1, remaining))
        guard r > 0 else { return Path() }
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + r * 360),
            clockwise: false
        )
        return path
    }
}

#Preview {
    HStack(spacing: 40) {
        TimerRingView(progress: 0.25, isWork: true, remainingTime: 18 * 60 + 42)
            .frame(width: 220, height: 220)
        TimerRingView(progress: 0.6, isWork: false, remainingTime: 2 * 60 + 15)
            .frame(width: 220, height: 220)
    }
    .padding(40)
    .background(Color.appBackground)
}
