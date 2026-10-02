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
        // Founders, before anything else writes: the first time this build
        // runs, a completed first run or any history in the App Group can only
        // have been left by 1.0 or 1.0.1. After `ContentView` builds the day's
        // store, every install holds history — so this is the one moment the
        // question can be asked. See `Founder`.
        if Founder.recordOnFirstLaunch(in: ForgeShared.defaults) {
            ForgeTelemetry.send(.founderDetected)
        }
        ForgeNotifications.shared.register()
        // Apple Health's observers, and only for somebody who has already said
        // Continue on the primer: this asks nothing and shows nothing. A new
        // install is never asked at launch (DIRECTION_1_1 §8). Registered this
        // early because a background delivery launches the app to hear it.
        if HealthLedger.read(from: ForgeShared.defaults).observesAtLaunch {
            HealthBridge.shared.startObserving()
        }
        // A Live Activity outlives the process that started it.
        ForgePresence.shared.adoptRunningActivity()
        // The first week's five tips: TipKit is configured once, here, before
        // anything that shows a tip is drawn. See `ForgeTips`.
        ForgeTips.configure()
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
