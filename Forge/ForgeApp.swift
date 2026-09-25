import SwiftUI

@main
struct ForgeApp: App {

    /// Claimed here rather than from a view. A tap on a notification that
    /// launches Forge from cold is delivered while the app is still starting up,
    /// and by the time `ContentView` exists it is already too late to hear about
    /// it.
    init() {
        // First, and before anything reads a default. Every store below now
        // opens the App Group suite, and on the launch after an update that
        // suite is empty until this has run.
        ForgeShared.migrateIfNeeded()
        // Anonymous usage, if the switch in Settings is on. Inert in tests and
        // when it is off — see `ForgeTelemetry`.
        ForgeTelemetry.start()
        ForgeNotifications.shared.register()
        // A Live Activity outlives the process that started it.
        ForgePresence.shared.adoptRunningActivity()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                // Brand tint applied once at the root, so every native
                // control — toggles, buttons, links, progress views — picks it
                // up instead of each call site setting its own.
                .tint(ForgeTheme.accent)
        }
    }
}
