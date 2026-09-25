import SwiftUI

/// The preferences that are genuinely preferences.
///
/// Everything with real machinery behind it lives elsewhere and is a section of
/// its own on the screen: notifications own a permission and a wake time, the
/// account owns a session, the appearance owns a colour every view reads. What
/// is left here is the two switches that turn cues off — and until this was
/// written, **neither of them did anything.**
///
/// That is worth recording rather than quietly fixing. `ForgeAudio.isEnabled`
/// and `ForgeHaptics.isEnabled` both existed, both were honoured by every call
/// site inside those two files, and nothing on any screen ever wrote to them.
/// So the app shipped two switches that moved, persisted nothing, and silenced
/// nothing — which is worse than not offering the setting, because somebody who
/// turns sound off and still hears the stone grind concludes the app is broken
/// rather than that the switch is decorative.
@Observable
final class SettingsViewModel {
    private let progress: ProgressStore

    /// Every cue the scene makes: the grind, the seat, the chip, the unlock.
    var sound: Bool = true {
        didSet { store(sound, as: Key.sound, was: oldValue) }
    }

    /// Every haptic in the app, including the continuous scrape under a pull.
    var haptics: Bool = true {
        didSet { store(haptics, as: Key.haptics, was: oldValue) }
    }

    /// Guards the two `didSet`s while `init` is filling them in from disk.
    /// Without it, loading a stored `false` would write it straight back — which
    /// is harmless here and is exactly the shape of bug that is not harmless the
    /// first time one of these gains a side effect.
    private var isLoaded = false

    private enum Key {
        static let sound = "forge.sound.v1"
        static let haptics = "forge.haptics.v1"
    }

    init(progress: ProgressStore) {
        self.progress = progress
        // `object(forKey:) == nil` rather than `bool(forKey:)`, so an install
        // that has never touched these gets `true` rather than the `false` a
        // missing bool decodes as.
        let defaults = ForgeShared.defaults
        sound = defaults.object(forKey: Key.sound) as? Bool ?? true
        haptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        isLoaded = true
        push()
    }

    private func store(_ value: Bool, as key: String, was: Bool) {
        guard isLoaded, value != was else { return }
        ForgeShared.defaults.set(value, forKey: key)
        push()
    }

    /// Hand both answers to the two objects that act on them.
    ///
    /// Pushed rather than read: `ForgeAudio` and `ForgeHaptics` are called from
    /// inside a drag at sixty frames a second and from a `CHHapticEngine`
    /// callback, and neither should be reaching back through a view model to ask
    /// whether it is allowed to make a noise.
    ///
    /// Hopped onto the main actor rather than isolating this whole type to it.
    /// `ForgeAudio` and `ForgeHaptics` are `@MainActor`, this view model is
    /// built inside `ContentView.init` — which is not — and a runloop of latency
    /// on a preference switch is invisible where a whole isolated view model
    /// would not be.
    private func push() {
        let sound = self.sound
        let haptics = self.haptics
        Task { @MainActor in
            ForgeAudio.shared.isEnabled = sound
            ForgeHaptics.shared.isEnabled = haptics
        }
    }

    /// Sunday first, matching the picker. Kept in the history store rather than
    /// here, because the streak has to honour it — the footer under this control
    /// promises that a rest day does not break the chain, and now something
    /// actually reads it.
    var restDays: [Bool] {
        get { (0..<7).map { progress.restWeekdays.contains($0 + 1) } }
        set {
            progress.restWeekdays = Set(
                newValue.enumerated().compactMap { index, isRest in isRest ? index + 1 : nil }
            )
        }
    }

    var activeDayCount: Int { restDays.filter { !$0 }.count }

    /// The rest days, named, for the line under the picker.
    ///
    /// Written out rather than counted. "Two rest days" is a number about a
    /// setting; "Saturday and Sunday" is the thing somebody actually chose, and
    /// it is the only version that can be checked at a glance against the row of
    /// circles above it.
    var restDaySummary: String {
        let symbols = Calendar.current.weekdaySymbols
        var names = restDays.enumerated()
            .compactMap { index, isRest in isRest ? symbols[index] : nil }
        switch names.count {
        case 0: return "No rest days. Every day asks for the same list."
        case 1: return "\(names[0]) is a rest day."
        case 7: return "Every day is a rest day, so nothing is ever asked of you."
        default:
            let final = names.removeLast()
            return "\(names.joined(separator: ", ")) and \(final) are rest days."
        }
    }

    struct SettingsGroup: Identifiable {
        let id = UUID()
        let title: String
        var hint: String = ""
        var rows: [SettingsRow]
    }

    struct SettingsRow: Identifiable {
        let id = UUID()
        let key: String
        var sub: String = ""
        var kind: RowKind = .value("")
        var isDestructive: Bool = false
    }

    enum RowKind {
        case toggle(Bool)
        case value(String)
        case chevron
    }

    /// Notifications are deliberately not here. They own real state — a wake
    /// time and a permission — so they are a section of their own driven by
    /// `ForgeNotifications`, rather than a row in a list of preferences.
    ///
    /// Account is not here either, and for the same reason: restoring a purchase
    /// and managing a subscription both talk to StoreKit and both can fail, so
    /// they are real controls in the view rather than rows in a table of strings
    /// whose buttons did nothing.
    ///
    /// Each row carries a subtitle now. Two words on a switch — "Sound",
    /// "Haptics" — leave somebody guessing what they cover, and in an app whose
    /// most distinctive moment is a stone grinding under a thumb, "does this
    /// turn off the sword?" is a fair question for a settings screen to answer.
    var groups: [SettingsGroup] {
        [
            SettingsGroup(title: "SOUND AND FEEL", rows: [
                SettingsRow(
                    key: "Sound",
                    sub: "The stone, the pull, the blade coming free",
                    kind: .toggle(sound)
                ),
                SettingsRow(
                    key: "Haptics",
                    sub: "Taps, detents, and the drag of the pull",
                    kind: .toggle(haptics)
                ),
            ]),
        ]
    }

    func toggleSetting(_ key: String) {
        switch key {
        case "Sound": sound.toggle()
        case "Haptics": haptics.toggle()
        default: break
        }
    }
}
