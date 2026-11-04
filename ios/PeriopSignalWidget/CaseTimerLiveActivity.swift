import ActivityKit
import SwiftUI
import WidgetKit

/// The next case timer on the lock screen and in the Dynamic Island: what, where, and a countdown that keeps counting
/// once it is due. Started by the app (CaseTimerNotifier) while a case timer runs.
struct CaseTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaseTimerActivityAttributes.self) { ctx in
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PS.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.state.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(ctx.state.caseLabel + (ctx.state.more > 0 ? " · \(ctx.state.more) more" : ""))
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ctx.state.due, style: .timer)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(ctx.state.due < .now ? PS.coralLight : .white)
                        .multilineTextAlignment(.trailing)
                    Text(ctx.state.due, style: .time).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(hex: "111722"))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.state.caseLabel, systemImage: "timer").font(.system(size: 14, weight: .semibold)).foregroundStyle(PS.coral)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.due, style: .timer).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ctx.state.title + (ctx.state.more > 0 ? " · \(ctx.state.more) more" : ""))
                        .font(.system(size: 14)).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(PS.coral)
            } compactTrailing: {
                Text(ctx.state.due, style: .timer).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(PS.coral)
            }
        }
    }
}
