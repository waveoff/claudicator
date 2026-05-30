import SwiftUI

struct UsageRowView: View {
    let label: String
    let percent: Double    // 0–100, used
    let resetDate: Date?   // when this window resets

    private var barColor: Color { UsageStore.quotaColor(used: percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(String(format: "%.0f%% used", percent))
                    .fontWeight(.medium)
                    .fixedSize()
                // Live countdown inline, re-rendered locally each minute.
                // TimelineView only updates this subtree — it never republishes
                // UsageStore, so the MenuBarExtra popover stays stable.
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text("· \(UsageStore.compactResetString(to: resetDate))")
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .font(.caption)

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
        }
    }
}
