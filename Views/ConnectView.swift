import AppKit
import SwiftUI

// MARK: - Connect window controller
//
// Hosts ConnectView in a standalone NSWindow. Used instead of putting the
// flow in the MenuBarExtra popover, which dismisses when the user switches
// to the browser.

final class ConnectWindowController {
    static let shared = ConnectWindowController()
    private init() {}

    private var window: NSWindow?

    func show(store: UsageStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ConnectView(store: store) { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Connect to Claude — Claudicator"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 360))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Connect flow view model

@MainActor
final class ConnectModel: ObservableObject {
    @Published var pastedCode = ""
    @Published var error: String?
    @Published var isExchanging = false
    @Published var didOpenBrowser = false

    func openAuthPage() {
        let url = OAuthService.shared.beginAuthorization()
        NSWorkspace.shared.open(url)
        didOpenBrowser = true
        error = nil
    }

    func connect(onSuccess: @escaping () -> Void) {
        let code = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { error = "Paste the code from the browser first."; return }
        isExchanging = true
        error = nil
        Task {
            do {
                _ = try await OAuthService.shared.exchange(pastedCode: code)
                isExchanging = false
                onSuccess()
            } catch {
                isExchanging = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Connect view

struct ConnectView: View {
    let store: UsageStore
    let onClose: () -> Void
    @StateObject private var model = ConnectModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Claudicator to your Claude account")
                .font(.headline)

            Text("This uses the same secure sign-in as Claude Code. You'll authorize in your browser — Claudicator never sees your password.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Step 1
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("1.").bold()
                Button("Open authorization page") { model.openAuthPage() }
            }

            // Step 2
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("2.").bold()
                    Text("Approve access, then copy the code shown and paste it here:")
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Paste authorization code", text: $model.pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.didOpenBrowser)
            }

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button {
                    model.connect {
                        store.refresh()
                        onClose()
                    }
                } label: {
                    if model.isExchanging {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isExchanging || model.pastedCode.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }
}
