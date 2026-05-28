import SwiftUI

@main
struct ClaudicatorApp: App {
    @StateObject private var usageStore = UsageStore()

    var body: some Scene {
        MenuBarExtra("Claude Quota", systemImage: "brain.head.profile") {
            ContentView()
                .environmentObject(usageStore)
                .frame(width: 280)
                .onAppear {
                    usageStore.startPolling()
                }
        }
    }
}
