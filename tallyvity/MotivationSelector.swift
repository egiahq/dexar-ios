import SwiftUI
import UIKit

struct MotivationSelector: View {
    var onSelect: (Int) -> Void
    var onTapAdjust: (() -> Void)? = nil

    @State private var selectedLevel: Int?
    @State private var submitted = false
    @State private var animationTask: Task<Void, Never>?
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 30) {
            Text("Motivation level")
                .font(.caption)
                .kerning(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { level in
                    Circle()
                        .fill(fillColor(for: level))
                        .overlay(
                            Circle()
                                .strokeBorder(borderColor(for: level), lineWidth: 1.5)
                        )
                        .frame(width: 38, height: 38)
                        .scaleEffect(scale(for: level))
                        .opacity(opacity(for: level))
                        .contentShape(Circle())
                        .animation(.bouncySpring, value: selectedLevel)
                        .onTapGesture {
                            guard !submitted else { return }
                            onTapAdjust?()
                            animateSelection(level)
                        }
                }
            }

            if let selectedLevel {
                Text(label(for: selectedLevel))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func animateSelection(_ level: Int) {
        haptic.selectionChanged()
        animationTask?.cancel()
        withAnimation(.bouncySpring) {
            selectedLevel = level
        }

        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.18))
            if Task.isCancelled { return }
            submitted = true
            onSelect(level)
        }
    }

    private func fillColor(for level: Int) -> Color {
        guard let selectedLevel else { return .clear }
        return level <= selectedLevel ? .primary : .clear
    }

    private func scale(for level: Int) -> CGFloat {
        guard let selectedLevel else { return 1.0 }
        return selectedLevel == level ? 1.25 : 0.9
    }

    private func opacity(for level: Int) -> Double {
        guard let selectedLevel else { return 1.0 }
        return selectedLevel == level ? 1.0 : 0.45
    }

    private func borderColor(for level: Int) -> Color {
        guard let selectedLevel else { return Color.primary.opacity(0.28) }
        return level <= selectedLevel ? Color.primary.opacity(0.0) : Color.primary.opacity(0.28)
    }

    private func label(for level: Int) -> String {
        switch level {
        case 1: return "low"
        case 2: return "warming up"
        case 3: return "steady"
        case 4: return "locked in"
        case 5: return "all in"
        default: return ""
        }
    }
}

#Preview {
    MotivationSelector { _ in }
        .padding(30)
}
