import Foundation
import QuartzCore
import Observation

/// Frame-by-frame physics for the sword pull (spec §5.6).
///
/// The drag is integrated manually rather than handed to a SwiftUI spring so
/// that the grind audio and the haptic scrape can read `pos` and `vel` on every
/// single frame. `pos` is published at display rate; the scene reads it directly
/// with no `withAnimation` anywhere, which is what gives the drag zero lag.
@MainActor
@Observable
final class SwordEngine {

    // MARK: - Model constants (§5.6)

    /// Spring: stiffness 190, damping 27.6, mass 1.
    /// Damping ratio = 27.6 / (2·√190) ≈ 1.00 — critically damped, so the
    /// blade never overshoots or wobbles. It is heavy and it *arrives*.
    static let stiffness: Double = 190
    static let damping: Double = 27.6

    /// How much finger travel a full pull is worth.
    ///
    /// # Why this is 150 and not 250
    ///
    /// Because at 250 the app's own instruction could not be followed. The
    /// prompt says **"Press the grip and drag up"**, and when the blade is loose
    /// the grip sits at y ≈ 150…235pt. Breaking free needs `raw` ≈ 0.79 — where
    /// the resistance curve reaches the 0.66 threshold — which at 250 is **198pt
    /// of travel**. From the grip that finishes at y ≈ 0: the very top of the
    /// screen, past the status bar, with the finger off the glass. Measured, not
    /// guessed: a deliberate 151pt haul from the grip reached 0.52 and slipped
    /// back, every time.
    ///
    /// So the one gesture the whole product is built around could only be
    /// completed by ignoring the instruction and starting halfway down the
    /// blade. At 150 the break lands at 118pt and a full pull at 150 — from the
    /// grip that finishes around y ≈ 70, well inside the screen, and from
    /// anywhere lower there is room to spare.
    ///
    /// **Nothing about the feel changes.** The resistance curve, both catches,
    /// the spring, the friction ticks, the grind and the break are untouched;
    /// this is the distance they are mapped over, and the weight was always in
    /// the mapping rather than in the distance. The two catches still land at
    /// 60pt and 116pt, so it is still a two-stage haul against something that
    /// does not want to move. A casual 60pt flick reaches 0.30 and slips back,
    /// which is the property that has to survive a shorter travel.
    static let travel: Double = 150

    /// The two mechanical catches, in *output* (post-resistance) space.
    static let catches: [Double] = [0.32, 0.66]

    /// Release above this and the blade rips free; below and it slips back.
    static let breakThreshold: Double = 0.66

    /// One friction tick per 30pt of finger travel.
    static let frictionTickDistance: Double = 30

    private static let maxTimestep: Double = 0.034

    // MARK: - Tunable

    /// 0.5–2.0. Higher means a longer drag is required.
    var resistanceMultiplier: Double = 1.0

    // MARK: - Published state

    private(set) var pos: Double = 0
    private(set) var vel: Double = 0
    private(set) var isDragging: Bool = false

    // MARK: - Callbacks

    var onCatch: (() -> Void)?
    var onBottomOut: (() -> Void)?
    var onFrictionTick: (() -> Void)?
    var onFrame: ((_ pos: Double, _ vel: Double) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onBreakFree: (() -> Void)?
    var onSlipBack: (() -> Void)?

    // MARK: - Internals

    private var target: Double = 0
    private var lastCatch: Double = 0
    private var frictionAccumulator: Double = 0
    private var dragOriginY: Double = 0
    private var lastMoveY: Double = 0

    private var link: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Resistance curve (§5.6)

    /// Piecewise-linear resistance — the heart of the feel.
    ///
    /// The first 30% of hand travel yields 26% (it gives easily), then
    /// 0.30→0.43 yields only 8% (**the first catch, it goes stiff**), then it
    /// frees up to roughly 1:1 again, then 0.67→0.79 yields 8% again (**the
    /// second catch**), and finally the last 21% of travel yields 32% — it runs
    /// away from you into the break.
    private static let resistInput: [Double] = [0, 0.30, 0.43, 0.67, 0.79, 1.00]
    private static let resistOutput: [Double] = [0, 0.26, 0.34, 0.60, 0.68, 1.00]

    static func mapResist(_ raw: Double) -> Double {
        let x = min(max(raw, 0), 1)
        for i in 1..<resistInput.count where x <= resistInput[i] {
            let span = resistInput[i] - resistInput[i - 1]
            guard span > 0 else { return resistOutput[i] }
            let t = (x - resistInput[i - 1]) / span
            return resistOutput[i - 1] + t * (resistOutput[i] - resistOutput[i - 1])
        }
        return 1
    }

    // MARK: - Drag lifecycle

    func dragBegan(atY y: Double) {
        dragOriginY = y
        lastMoveY = y
        frictionAccumulator = 0
        lastCatch = target
        isDragging = true
        onDragBegan?()
        startLoop()
    }

    func dragChanged(toY y: Double) {
        guard isDragging else { return }

        let raw = min(max((dragOriginY - y) / (Self.travel * max(resistanceMultiplier, 0.1)), 0), 1)
        let newTarget = Self.mapResist(raw)

        // A catch fires when the target crosses it going up. `lastCatch` is
        // rewritten every move, so sliding back down re-arms both catches.
        for c in Self.catches where lastCatch < c && newTarget >= c {
            onCatch?()
        }
        lastCatch = newTarget

        // Friction scales with hand speed, not with position.
        frictionAccumulator += abs(y - lastMoveY)
        lastMoveY = y
        if frictionAccumulator >= Self.frictionTickDistance {
            frictionAccumulator = 0
            onFrictionTick?()
        }

        target = newTarget
    }

    func dragEnded() {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()

        if pos > Self.breakThreshold {
            // A deliberate kick so the last third rips rather than eases.
            target = 1
            vel = max(vel, 2.6)
            onBreakFree?()
        } else {
            target = 0
            lastCatch = 0
            onSlipBack?()
        }
        startLoop()
    }

    /// Hand the blade back to the stone (§5.10).
    ///
    /// Deliberately *not* a hard reset. Snapping `pos` to 0 snapped everything
    /// that reads it in the same frame — 46pt of blade lift, the stone's sag,
    /// every stress crack on the crown — which is a visible jolt at the one
    /// moment the scene is supposed to be releasing. Releasing the spring to 0
    /// instead unwinds all of it through the same physics that drove it, in
    /// about half a second, and the loop still stops cleanly with `pos` at
    /// exactly 0 so nothing stays pinned.
    func release() {
        isDragging = false
        target = 0
        lastCatch = 0
        frictionAccumulator = 0
        startLoop()
    }

    // MARK: - Integration loop

    private func startLoop() {
        guard link == nil else { return }
        lastFrameTime = CACurrentMediaTime()
        let proxy = DisplayLinkProxy { [weak self] in
            guard let self else { return false }
            self.step()
            return true
        }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        proxy.link = l
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLoop() {
        link?.invalidate()
        link = nil
    }

    private func step() {
        let now = CACurrentMediaTime()
        var dt = now - lastFrameTime
        lastFrameTime = now
        guard dt > 0 else { return }
        dt = min(dt, Self.maxTimestep)

        let a = Self.stiffness * (target - pos) - Self.damping * vel
        vel += a * dt
        pos += vel * dt

        if pos < 0 {
            pos = 0
            // Only announce the bottom-out if it actually arrived with weight.
            if vel < -0.4 { onBottomOut?() }
            vel = 0
        }
        if pos > 1 {
            pos = 1
            vel *= 0.25
        }

        onFrame?(pos, vel)

        if !isDragging && abs(target - pos) < 0.0008 && abs(vel) < 0.004 {
            pos = target
            vel = 0
            onFrame?(pos, 0)
            stopLoop()
        }
    }
}

/// CADisplayLink retains its target, so the engine cannot be the target without
/// creating a cycle. This proxy holds only a weak-capturing closure, and tears
/// the link down itself once the engine is gone.
private final class DisplayLinkProxy: NSObject {
    private let handler: () -> Bool
    weak var link: CADisplayLink?

    init(_ handler: @escaping () -> Bool) { self.handler = handler }

    @objc func tick() {
        if !handler() { link?.invalidate() }
    }
}
