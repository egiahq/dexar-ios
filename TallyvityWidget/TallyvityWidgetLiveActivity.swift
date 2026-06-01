import ActivityKit
import WidgetKit
import SwiftUI

struct DexarWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DexarAttributes.self) { context in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(context.state.isWork ? "Focus" : "Break")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: context.state.isWork ? "brain.head.profile" : "cup.and.saucer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(context.attributes.goal)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if context.state.isOvertime {
                        Text("00:00")
                            .font(.title2.weight(.light).monospacedDigit())
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(context.state.endDate, style: .timer)
                            .font(.title2.weight(.light).monospacedDigit())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                    }

                    Text("Loop \(context.state.loopNumber) of \(context.attributes.totalLoops)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GOAL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.goal)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 10)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    let overtime = context.state.isOvertime
                    let phaseColor: Color = overtime ? .red : (context.state.isWork ? .orange : .cyan)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(overtime ? "OVERTIME" : (context.state.isWork ? "FOCUS" : "BREAK"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(phaseColor)

                        HStack(spacing: 8) {
                            Image(systemName: context.state.isWork ? "brain.head.profile" : "cup.and.saucer")
                                .font(.title3)
                            if overtime {
                                Text("00:00")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                            } else {
                                Text(context.state.endDate, style: .timer)
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .foregroundStyle(phaseColor)
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 10)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Text("Loop \(context.state.loopNumber) of \(context.attributes.totalLoops)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                } compactLeading: {
                    Image(systemName: context.state.isWork ? "brain.head.profile" : "cup.and.saucer")
                        .foregroundStyle(context.state.isOvertime ? .red : (context.state.isWork ? .orange : .cyan))
                        .font(.caption2.weight(.bold))
                } compactTrailing: {
                    if context.state.isOvertime {
                        Text("00:00")
                            .monospacedDigit()
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 44, alignment: .trailing)
                    } else {
                        Text(context.state.endDate, style: .timer)
                            .monospacedDigit()
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(context.state.isWork ? .orange : .cyan)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 44, alignment: .trailing)
                    }
                } minimal: {
                Image(systemName: context.state.isWork ? "brain.head.profile" : "cup.and.saucer")
                    .foregroundStyle(context.state.isOvertime ? .red : (context.state.isWork ? .orange : .cyan))
                    .font(.caption2.weight(.bold))
            }
        }
    }
}

extension DexarAttributes {
    fileprivate static var preview: DexarAttributes {
        DexarAttributes(goal: "Write the proposal", shortGoal: "Proposal", totalLoops: 4)
    }
}

extension DexarAttributes.ContentState {
    fileprivate static var working: DexarAttributes.ContentState {
        DexarAttributes.ContentState(endDate: Date().addingTimeInterval(1200), isWork: true, loopNumber: 2)
    }

    fileprivate static var onBreak: DexarAttributes.ContentState {
        DexarAttributes.ContentState(endDate: Date().addingTimeInterval(300), isWork: false, loopNumber: 2)
    }
}

#Preview("Notification", as: .content, using: DexarAttributes.preview) {
    DexarWidgetLiveActivity()
} contentStates: {
    DexarAttributes.ContentState.working
    DexarAttributes.ContentState.onBreak
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: DexarAttributes.preview) {
    DexarWidgetLiveActivity()
} contentStates: {
    DexarAttributes.ContentState.working
    DexarAttributes.ContentState.onBreak
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: DexarAttributes.preview) {
    DexarWidgetLiveActivity()
} contentStates: {
    DexarAttributes.ContentState.working
    DexarAttributes.ContentState.onBreak
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: DexarAttributes.preview) {
    DexarWidgetLiveActivity()
} contentStates: {
    DexarAttributes.ContentState.working
    DexarAttributes.ContentState.onBreak
}