import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                Circle()
                    .fill(usage.statusColor)
                    .frame(width: 9, height: 9)
                Text("Claudicator")
                    .font(.headline)
                Spacer()
                Button(action: usage.refresh) {
                    if usage.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(usage.isRefreshing)
                .help("Refresh now")

                Menu {
                    if let sub = usage.subscriptionType {
                        Text("Plan: \(sub.capitalized)")
                    }
                    Button(usage.needsLogin ? "Connect to Claude…" : "Reconnect…") {
                        ConnectWindowController.shared.show(store: usage)
                    }
                    if !usage.needsLogin {
                        Button("Disconnect", action: usage.disconnect)
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Account")
            }

            Divider()

            // Session row
            if let pct = usage.sessionUsed {
                UsageRowView(
                    label: "5-hour session",
                    percent: pct,
                    resetDate: usage.sessionResetDate
                )
            } else {
                placeholderRow(label: "5-hour session")
            }

            Divider()

            // Weekly row
            if let pct = usage.weekUsed {
                UsageRowView(
                    label: "This week",
                    percent: pct,
                    resetDate: usage.weekResetDate
                )
            } else {
                placeholderRow(label: "This week")
            }

            // Error state
            if let error = usage.lastError {
                Divider()
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Connect button when not signed in
            if usage.needsLogin {
                Button("Connect to Claude…") {
                    ConnectWindowController.shared.show(store: usage)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            Divider()

            // Footer
            HStack {
                if let t = usage.lastFetchedAt {
                    Text("Updated \(t, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(usage.lastError == nil ? "Loading…" : "Not connected")
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

    private func placeholderRow(label: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            ProgressView().controlSize(.mini)
        }
    }
}
