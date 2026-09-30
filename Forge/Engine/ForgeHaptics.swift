import CoreHaptics
import Foundation
import UIKit

/// Core Haptics patterns for the whole app (spec §1.6).
///
/// One engine, built lazily and restarted after interruptions. Everything falls
/// back to `UIFeedbackGenerator` when Core Haptics is unavailable (older or
/// non-Taptic hardware, or the simulator), so no call site needs to branch.
@MainActor
final class ForgeHaptics {

    static let shared = ForgeHaptics()

    /// Gated by the Haptics setting.
    var isEnabled: Bool = true

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// The continuous scrape that runs for the duration of a drag.
    private var scrapePlayer: CHHapticAdvancedPatternPlayer?

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    // MARK: - Lifecycle

    func prepare() {
        guard isEnabled else { return }
        impactLight.prepare()
        impactHeavy.prepare()
        impactRigid.prepare()
        selection.prepare()

        guard supportsHaptics, engine == nil else { return }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = true
            // The engine stops on interruption (a call, a Siri invocation) and
            // must be explicitly revived or every later pattern silently fails.
            e.resetHandler = { [weak e] in try? e?.start() }
            e.stoppedHandler = { _ in }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    // MARK: - Discrete cues

    /// Tap a row, open a sheet, toggle — 5–8ms.
    func tap() {
        guard isEnabled else { return }
        transient(intensity: 0.5, sharpness: 0.5, fallback: { impactLight.impactOccurred(intensity: 0.5) })
    }

    /// A wheel detent — 3ms.
    func detent() {
        guard isEnabled else { return }
        transient(intensity: 0.3, sharpness: 0.9, fallback: { selection.selectionChanged() })
    }

    /// A catch during the pull — 17ms, sharp. The stone cracks.
    func catchTick() {
        guard isEnabled else { return }
        transient(intensity: 0.85, sharpness: 1.0, fallback: { impactRigid.impactOccurred(intensity: 0.9) })
    }

    /// One friction tick per 30pt of finger travel — 4ms.
    func frictionTick() {
        guard isEnabled else { return }
        transient(intensity: 0.28, sharpness: 0.7, fallback: { impactLight.impactOccurred(intensity: 0.3) })
    }

    /// An assessment answer recorded — a light tick, lighter than a row being
    /// chosen, because seven of them arrive in under a minute.
    func answered() {
        guard isEnabled else { return }
        transient(intensity: 0.38, sharpness: 0.65, fallback: { impactLight.impactOccurred(intensity: 0.4) })
    }

    /// One vertex of the starting shape coming on. `step` of `count`, and each
    /// one a little stronger than the last, so the six read as one rising
    /// sequence under the drawing rather than six identical taps.
    func shapeRising(step: Int, of count: Int) {
        guard isEnabled else { return }
        let progress = count > 1 ? Float(step) / Float(count - 1) : 1
        transient(
            intensity: 0.25 + 0.55 * progress,
            sharpness: 0.35 + 0.35 * progress,
            fallback: { impactLight.impactOccurred(intensity: CGFloat(0.3 + 0.6 * progress)) }
        )
    }

    /// Ritual verified — 14ms.
    func ritualVerified() {
        guard isEnabled else { return }
        transient(intensity: 0.6, sharpness: 0.6, fallback: { notification.notificationOccurred(.success) })
    }

    /// The spring bottoming out at 0 — 20ms, heavy.
    func bottomOut() {
        guard isEnabled else { return }
        transient(intensity: 0.9, sharpness: 0.3, fallback: { impactHeavy.impactOccurred(intensity: 0.9) })
    }

    // MARK: - Multi-event patterns

    /// The last ritual verified — a double knock, `[12, 30, 16]`.
    func lastRitualVerified() {
        guard isEnabled else { return }
        play(events: [
            (time: 0.00, intensity: 0.6, sharpness: 0.6),
            (time: 0.03, intensity: 0.75, sharpness: 0.5),
        ], fallback: { notification.notificationOccurred(.success) })
    }

    /// **Break free** — `[22, 44, 26, 70]`: two sharp cracks, then two heavier
    /// thuds, across ~0.16s.
    func breakFree() {
        guard isEnabled else { return }
        play(events: [
            (time: 0.00, intensity: 0.70, sharpness: 1.00),
            (time: 0.045, intensity: 1.00, sharpness: 0.90),
            (time: 0.095, intensity: 0.80, sharpness: 0.35),
            (time: 0.160, intensity: 1.00, sharpness: 0.20),
        ], fallback: { impactHeavy.impactOccurred(intensity: 1.0) })
    }

    /// A new sword unlocked — the same shape, softer and warmer.
    func swordUnlocked() {
        guard isEnabled else { return }
        play(events: [
            (time: 0.00, intensity: 0.55, sharpness: 0.45),
            (time: 0.045, intensity: 0.80, sharpness: 0.40),
            (time: 0.090, intensity: 0.60, sharpness: 0.25),
            (time: 0.155, intensity: 0.85, sharpness: 0.15),
        ], fallback: { impactHeavy.impactOccurred(intensity: 0.8) })
    }

    /// The sword returning to the stone — `[18, 30]`, two heavy transients.
    func swordReseated() {
        guard isEnabled else { return }
        play(events: [
            (time: 0.00, intensity: 0.70, sharpness: 0.25),
            (time: 0.050, intensity: 0.90, sharpness: 0.15),
        ], fallback: { impactHeavy.impactOccurred(intensity: 0.85) })
    }

    // MARK: - Continuous drag scrape

    /// Intensity ramps 0.15 → 0.5 with the pull; sharpness stays at 0.7.
    func startDragScrape() {
        guard isEnabled, supportsHaptics else { return }
        prepare()
        guard let engine else { return }

        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
                ],
                relativeTime: 0,
                duration: 30
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            scrapePlayer = player
        } catch {
            scrapePlayer = nil
        }
    }

    func updateDragScrape(pull: Double) {
        guard isEnabled, let player = scrapePlayer else { return }
        let intensity = Float(0.15 + min(max(pull, 0), 1) * 0.35)
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: intensity,
            relativeTime: 0
        )
        try? player.sendParameters([parameter], atTime: CHHapticTimeImmediate)
    }

    func stopDragScrape() {
        try? scrapePlayer?.stop(atTime: CHHapticTimeImmediate)
        scrapePlayer = nil
    }

    // MARK: - Plumbing

    private typealias Beat = (time: TimeInterval, intensity: Float, sharpness: Float)

    private func transient(intensity: Float, sharpness: Float, fallback: () -> Void) {
        play(events: [(time: 0, intensity: intensity, sharpness: sharpness)], fallback: fallback)
    }

    private func play(events: [Beat], fallback: () -> Void) {
        guard supportsHaptics else {
            fallback()
            return
        }
        prepare()
        guard let engine else {
            fallback()
            return
        }
        do {
            let hapticEvents = events.map { beat in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness),
                    ],
                    relativeTime: beat.time
                )
            }
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }
}
