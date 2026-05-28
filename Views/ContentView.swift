import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(usage.statusColor)
                    .frame(width: 9, height: 9)
                Text("Claudicator")
                    .font(.headline)
                Spacer()
                Button(action: usage.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Divider()

            if let remaining = usage.fiveHourRemaining {
                UsageRowView(
                    label: "5-hour session",
                    percent: remaining,
                    timeLeft: UsageStore.format(duration: usage.fiveHourSecondsLeft)
                )
            } else {
                Text("5-hour session unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let remaining = usage.weekRemaining {
                UsageRowView(
                    label: "This week",
                    percent: remaining,
                    timeLeft: UsageStore.format(duration: usage.weekSecondsLeft)
                )
            } else {
                Text("Weekly quota unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = usage.lastError {
                Divider()
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                if let fetchedAt = usage.lastFetchedAt {
                    Text("Updated \(fetchedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not fetched yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
    }
}
