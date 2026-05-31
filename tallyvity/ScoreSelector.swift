import SwiftUI
import UIKit

struct ScoreSelector: View {
    var onSelect: (Int) -> Void
    var onTapRate: (() -> Void)? = nil

    @State private var selected: Int? = nil
    @State private var submitted = false
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 36) {
            Text("Rate your output")
                .font(.caption)
                .kerning(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                ForEach(1...5, id: \.self) { i in
                    let filled = selected != nil && i <= selected!
                    Circle()
                        .fill(filled ? Color.primary : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(filled ? 0 : 0.28), lineWidth: 1.5)
                        )
                        .frame(width: 38, height: 38)
                        .scaleEffect(scale(for: i))
                        .opacity(opacity(for: i))
                        .animation(.bouncySpring, value: selected)
                        .onTapGesture {
                            guard !submitted else { return }
                            tap(i)
                            onTapRate?()
                        }
                }
            }

            if let s = selected {
                VStack(spacing: 4) {
                    Text(label(s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(anchor(s))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
                .animation(.bouncySpring, value: selected)
            }
        }
    }

    private func tap(_ i: Int) {
        haptic.selectionChanged()
        withAnimation(.bouncySpring) {
            selected = i
        }
        submitted = true
        onSelect(i)
    }

    private func scale(for i: Int) -> CGFloat {
        guard let selected else { return 1.0 }
        return selected == i ? 1.25 : 0.9
    }

    private func opacity(for i: Int) -> Double {
        guard let selected else { return 1.0 }
        return selected == i ? 1.0 : 0.45
    }

    private func label(_ score: Int) -> String {
        switch score {
        case 1: return "didn't start"
        case 2: return "partial start"
        case 3: return "meaningful progress"
        case 4: return "substantially complete"
        case 5: return "task complete"
        default: return ""
        }
    }

    private func anchor(_ score: Int) -> String {
        switch score {
        case 1: return "did not start stated task"
        case 2: return "started, less than half done"
        case 3: return "meaningful progress made"
        case 4: return "task substantially complete"
        case 5: return "task complete, possibly exceeded"
        default: return ""
        }
    }
}

#Preview {
    ScoreSelector { score in print("Selected: \(score)") }
        .padding(40)
}
