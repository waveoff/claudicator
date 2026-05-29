import SwiftUI

struct UsageRowView: View {
    let label: String
    let percent: Double    // 0–100, remaining
    let resetDate: Date?   // when this window resets

    private var barColor: Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geometry.size.width * (percent / 100), height: 6)
                }
            }
            .frame(height: 6)

            // Live countdown, re-rendered locally each minute. TimelineView
            // only updates this subtree — it never republishes UsageStore, so
            // the MenuBarExtra popover stays stable.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(UsageStore.resetString(to: resetDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
