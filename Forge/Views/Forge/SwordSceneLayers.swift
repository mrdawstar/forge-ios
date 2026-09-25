import SwiftUI

// MARK: - Scene geometry (spec §4.2, canvas points on a 402-wide design)

enum SceneGeometry {
    static let canvasWidth: CGFloat = 402
    static let axis: CGFloat = 201
    static let mouth: CGFloat = 392
    static let seatTop: CGFloat = 262

    static let swordWidth: CGFloat = 120.8
    static let swordHeight: CGFloat = 442.9
    static let swordLeft: CGFloat = 140.6

    /// Total lift earned by completing rituals.
    static let travel: CGFloat = 133
    /// Extra lift contributed by the drag itself.
    static let pullLift: CGFloat = 46
    /// Extra lift once the blade is free.
    ///
    /// Carries `outSettle`'s 70pt sink on its back, and then 50pt more of its
    /// own: the point of an earned day is a blade hanging in clear air, and
    /// leaving its tip level with the crown kept it looking seated. The pommel
    /// lands at y≈138, which is still well below the Dynamic Island — that
    /// clearance is the ceiling on this number.
    static let outLift: CGFloat = 154

    /// The freed blade is never scaled up. `travel + pullLift + outLift` already
    /// carries the pommel to y≈95, and a scale-up anchored at the bottom adds
    /// its growth entirely at the tip — at 1.10 that was 44pt, which put the
    /// pommel off the top of the screen and straight under the Dynamic Island.
    /// The blade sells its release by rising and hanging, not by getting bigger.
    static let outSwordScale: CGFloat = 1.0

    /// The freed blade's resting lift, and the only one it ever has.
    ///
    /// One number rather than a sum of live values read at render time. Both of
    /// the values that used to be in that sum stop being stable the moment the
    /// blade is out: the drag reads 1 the instant it breaks and 0 after a
    /// relaunch, and the day's completion is a third on the day the first
    /// pull is granted, whole once the list is finished, and back to a third the
    /// second the first run is marked complete. One earned day had three
    /// resting heights, and this constant is what ends that.
    ///
    /// `pullLift` is deliberately *not* in it. The blade used to keep the drag's
    /// last 46pt for as long as the app stayed open, which is what put the
    /// pommel at y≈95 and crowded the Dynamic Island; every other route to the
    /// same earned day had already dropped it. This is the height `outLift`
    /// was measured for — pommel at y≈138, clear of the top safe area, and still
    /// a long way above the stone.
    static let outRest: CGFloat = travel + outLift

    /// Once the blade is out, the whole physical composition — blade, stone,
    /// contact shadow, floor bounce — eases down together by this much. Applied
    /// to the subjects only: the room behind them never moves, so nothing can
    /// slide out from under the frame.
    ///
    /// This is how the stone gets out of the way of an earned day: it sinks
    /// behind the quote card until only its crown shows, which stops it owning
    /// the middle of the screen and lets the quote take it.
    ///
    /// The whole stack moves rather than the stone alone, because the stone
    /// shares this transform with its own contact shadow and floor bounce —
    /// dropping it by itself would slide it off its shadow, which is the
    /// giveaway that a scene was assembled from layers rather than
    /// photographed. `outLift` absorbs the extra 70 so the blade does not sink
    /// with it.
    static let outSettle: CGFloat = 116

    static let rockWidth: CGFloat = 380
    static let rockHeight: CGFloat = 391
    /// Where the rock frame sits, and it is **not** the frame's centre.
    ///
    /// # The premise this used to be written on was false
    ///
    /// It read `axis - rockWidth/2 - 20`, under a comment saying the rock
    /// silhouette sits dead centre inside `rock-lit.png`, so centring the frame
    /// puts the crown's apex on the sword's axis. Half of that is true and the
    /// half that matters is not. Measured off the asset's alpha channel: the
    /// silhouette's **bulk** is centred (mid-x ≈ 330 of 660), but its **crown
    /// apex is at x ≈ 279** — 51px, or 7.7% of the width, left of centre. The
    /// rock's high point is simply not over its middle.
    ///
    /// So centring the frame put the apex 27pt left of the blade, and the −20
    /// nudge on top of it put the apex 47pt left. Measured on the composed
    /// screen at 402pt wide: **apex 154, blade 196**. That is the whole of "the
    /// sword does not come out of the middle of the stone" — it was entering
    /// the rock's right shoulder, a ninth of the screen off the peak, and the
    /// socket (which is drawn on the axis, correctly) sat there with it.
    ///
    /// # The number
    ///
    /// The apex and the bulk cannot both be on the axis while the asset has them
    /// 26pt apart on screen, so this splits the error evenly between them:
    ///
    ///     apex_screen(d) = 201 + 0.878·d − 43.4      (0.878 = rockScale)
    ///     bulk_screen(d) = 201 + 0.878·d − 17.6
    ///     apex_err = −bulk_err   ⇒   d = +35
    ///
    /// which lands the crown apex ~13pt left of centre and the rock's mass ~13pt
    /// right of it. Both are inside 3.2% of the screen width and neither reads
    /// as off; the blade now enters the middle of the crown's plateau, which is
    /// the thing anybody actually looks at.
    ///
    /// # The last seven points
    ///
    /// The arithmetic above lands on `−20 + 35`, which is the `+15` this read
    /// for the whole of the QA pass. It ships at **+8**, and the seven points
    /// came off it by looking at the composed screen rather than at the algebra.
    /// The derivation splits the error evenly between the apex and the bulk, and
    /// the eye does not weigh those two equally: what it finds is the **apex**,
    /// because that is where the blade enters and where it is already looking.
    /// An offset that is fair to both therefore reads, very slightly, as a stone
    /// sitting to the right of its own sword.
    ///
    /// Eleven points is about 2.7% of the screen — small enough that nothing else
    /// in the composition had to move for it, which is the whole point of a last
    /// nudge. `crackDrift` comes with it, exactly as much, or the fissures come
    /// off the face they were drawn for.
    ///
    /// It went to +8 first and then to +4 on a second look. Measured after:
    /// apex ≈ 193, blade 200, silhouette midpoint ≈ 204, against a screen centre
    /// of 201 — so the crown's high point and the rock's mass now straddle the
    /// blade almost evenly, which is what the derivation was aiming at before
    /// the eye's preference for the apex was weighed in.
    static let rockLeft: CGFloat = axis - rockWidth / 2 + 4
    static let rockTop: CGFloat = 382.2
    static let rockScale: CGFloat = 0.878
    static let rockDrop: CGFloat = 10
    /// The stone settles once the mass of the blade has left it — and only
    /// then. It deliberately does not give during the pull: a stone that sinks
    /// while you are still hauling reads as soft ground rather than as stone,
    /// and the release lands harder when the stone was immovable up to it.
    static let outRockDrop: CGFloat = 20

    /// The crack layers are laid out around `axis`, but the rock's midpoint is
    /// not there — see `rockLeft`. This carries them onto the rock's own centre
    /// line so the fissures belong to the stone rather than to the sword.
    ///
    /// It moves with the rock, and by exactly as much. It was −23 against a rock
    /// midpoint of 181; `rockLeft` has gained 24 since (−20 → +4), so it is
    /// −23 + 24. Anything else would slide the cracks off the face they were
    /// drawn for. Applied inside the stone group, so `rockScale` shrinks it.
    static let crackDrift: CGFloat = 1

    static let bladeWidth: CGFloat = 20
}

// MARK: - Easing

/// Hermite smoothstep, clamped. Used wherever a value has to arrive without a
/// kink at either end — it is what keeps a fade or a draw from showing the
/// moment it starts and the moment it stops.
func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Motion curves (spec §1.5)

extension Animation {
    /// Anything heavy arriving: sword lift, camera dolly, stone drop.
    static func settle(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.26, 1, duration: duration)
    }

    /// Sheet height, row collapse, chevron rotation.
    static func reveal(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// The home panel changing size, and everything inside it that changes size
    /// with it.
    ///
    /// One curve in one place because two of them used to disagree: the panel
    /// grew for the review on this spring while the review's own disclosure
    /// opened on SwiftUI's default, so the card finished arriving before the
    /// panel had finished making room for it.
    static let sheetPanel: Animation = .spring(response: 0.46, dampingFraction: 0.86)

    /// The panel getting out of the way as the blade comes free.
    ///
    /// The same disagreement `sheetPanel` was written to end, one level up. When
    /// the blade is pulled, three things move at once: the subjects settle over
    /// 2.4s on `settle(_:)`, the plate brightens over 1.6s, and the panel drops
    /// from as much as 579pt to 213pt. The panel was doing that on `sheetPanel`
    /// — a 0.46s spring — so it had finished, bounced and come to rest while the
    /// stone was still visibly sinking behind it. The eye reads the fast thing
    /// as the cause and the slow thing as lag, which is exactly backwards: the
    /// pull is the event and the panel is only making room for it.
    ///
    /// So the panel leaves on the scene's own family of curve and takes about
    /// two thirds of its time — long enough to read as one movement with the
    /// settle, short enough that the free state is not kept waiting behind an
    /// animation. Deliberately not a spring: nothing else in this moment
    /// overshoots, and a bounce here would be the one element in the composition
    /// disagreeing about how heavy everything is.
    static let bladeFreed: Animation = .timingCurve(0.22, 1, 0.26, 1, duration: 1.55)

    /// The dash-offset crack draw.
    static func crackDraw(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.3, 1, duration: duration)
    }
}

// MARK: - Stone chips (spec §5.8)

struct StoneChip: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let dx: CGFloat
    let dy: CGFloat
    let rotation: Double
    let opacity: Double
    let duration: Double

    /// `count` chips thrown from the mouth with the given angular `spread`.
    static func burst(count: Int, spread: CGFloat, big: Bool) -> [StoneChip] {
        (0..<count).map { _ in
            let angle = Double.random(in: -1...1) * (big ? 1.05 : 0.6)
            return StoneChip(
                x: SceneGeometry.axis + CGFloat.random(in: -spread / 2...spread / 2),
                y: SceneGeometry.mouth - 6 + CGFloat.random(in: 0...12),
                width: big ? CGFloat.random(in: 1.4...4.8) : CGFloat.random(in: 0.9...2.8),
                height: big ? CGFloat.random(in: 1.2...3.8) : CGFloat.random(in: 0.9...2.8),
                dx: CGFloat(sin(angle)) * (big ? 56 : 26),
                dy: big ? 44 + CGFloat.random(in: 0...130) : 44 + CGFloat.random(in: 0...58),
                rotation: Double.random(in: -130...130),
                opacity: Double.random(in: 0.42...0.92),
                duration: big ? Double.random(in: 0.9...1.7) : Double.random(in: 0.62...1.42)
            )
        }
    }
}

/// One chip: thrown outward, then falling. Fast out, decelerating — the easing
/// is the whole point, so this is a plain animated offset rather than a
/// particle emitter.
struct StoneChipView: View {
    let chip: StoneChip
    let scale: CGFloat

    @State private var t: Double = 0

    var body: some View {
        Rectangle()
            .fill(Color(red: 158 / 255, green: 152 / 255, blue: 143 / 255).opacity(chip.opacity))
            .frame(width: chip.width * scale, height: chip.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 1 * scale))
            .rotationEffect(.degrees(chip.rotation * t))
            .opacity(0.95 * (1 - t))
            .offset(x: chip.dx * scale * t, y: chip.dy * scale * t)
            .position(x: chip.x * scale, y: chip.y * scale)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.timingCurve(0.35, 0.1, 0.85, 0.6, duration: chip.duration)) {
                    t = 1
                }
            }
    }
}

// MARK: - Cracks (spec §4.5)

/// Seven fissures in a 402×230 viewBox anchored at y 362, so they radiate from
/// the mouth. Each carries a lit lower lip, so it reads as a real fissure
/// catching the key light rather than a drawn line.
enum StoneCracks {
    /// Number of completed rituals at which each crack appears. The last one
    /// belongs to the freed state.
    static let thresholds: [Int] = [1, 2, 3, 4, 5, 5, 6]
    static let viewBox = CGSize(width: 402, height: 230)
    static let originY: CGFloat = 362

    static func path(_ index: Int, in size: CGSize) -> Path {
        let sx = size.width / viewBox.width
        let sy = size.height / viewBox.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var path = Path()
        switch index {
        case 0:
            path.move(to: p(196, 32))
            path.addLine(to: p(178, 58))
            path.addLine(to: p(184, 76))
            path.addLine(to: p(166, 104))
        case 1:
            path.move(to: p(208, 34))
            path.addLine(to: p(232, 62))
            path.addLine(to: p(226, 82))
            path.addLine(to: p(248, 112))
        case 2:
            path.move(to: p(190, 44))
            path.addLine(to: p(150, 70))
            path.addLine(to: p(140, 98))
            path.addLine(to: p(112, 124))
        case 3:
            path.move(to: p(214, 46))
            path.addLine(to: p(258, 74))
            path.addLine(to: p(266, 100))
            path.addLine(to: p(296, 126))
        case 4:
            path.move(to: p(200, 40))
            path.addLine(to: p(204, 78))
            path.addLine(to: p(194, 106))
            path.addLine(to: p(202, 142))
        case 5:
            path.move(to: p(184, 52))
            path.addLine(to: p(160, 88))
            path.addLine(to: p(168, 118))
            path.addLine(to: p(146, 152))
        default:
            path.move(to: p(218, 56))
            path.addLine(to: p(246, 96))
            path.addLine(to: p(236, 122))
            path.addLine(to: p(262, 158))
        }
        return path
    }
}

struct CrackOverlay: View {
    let doneCount: Int
    let isOut: Bool
    let scale: CGFloat

    var body: some View {
        let size = CGSize(
            width: StoneCracks.viewBox.width * scale,
            height: StoneCracks.viewBox.height * scale
        )
        ZStack(alignment: .topLeading) {
            ForEach(0..<StoneCracks.thresholds.count, id: \.self) { i in
                let isLast = i == StoneCracks.thresholds.count - 1
                let shown = isLast ? isOut : doneCount >= StoneCracks.thresholds[i]

                StoneCracks.path(i, in: size)
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(
                        Color.black.opacity(0.66),
                        style: StrokeStyle(lineWidth: (isLast ? 0.8 : 1.1) * scale, lineCap: .round)
                    )
                    // A lit lower lip: the crack catches the upper-left key.
                    .shadow(color: .white.opacity(0.075), radius: 0, x: 0.7 * scale, y: 1 * scale)
                    .opacity(shown ? (isLast ? 0.7 : 0.92) : 0)
                    .animation(.crackDraw(1.5), value: shown)
                    .animation(.easeOut(duration: 0.9), value: shown)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Stress cracks

/// Hairline fissures that open across the crown *while the blade is being
/// pulled*.
///
/// These are not the earned cracks of `StoneCracks`. Those record progress and
/// stay. These record **force**: they draw on as the pull deepens and close
/// again if the blade slips back, so the stone reads as loaded and about to go
/// rather than already damaged. Everything about them is generated — angles,
/// kink at every step, segment lengths, line weights, thresholds — so no two
/// are alike and none is straight or mirrored.
enum StressCracks {
    static let viewBox = StoneCracks.viewBox
    static let originY = StoneCracks.originY

    struct Fissure {
        let points: [CGPoint]
        /// Pull at which this fissure begins to open.
        let appear: Double
        /// Pull span over which it finishes drawing.
        let span: Double
        let width: CGFloat
        let opacity: Double

        /// 0…1, eased at both ends, so a fissure never snaps into existence and
        /// never stops growing abruptly.
        func growth(at pull: Double) -> Double {
            smoothstep((pull - appear) / span)
        }
    }

    /// Seven forking fissures on a fixed seed: irregular, but identical every
    /// launch, so the stone is the same stone each day.
    static let fissures: [Fissure] = {
        var s: UInt64 = 0x00C0_FFEE_1234_567
        func rnd() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double((s >> 33) % 1_000_000) / 1_000_000
        }

        /// One irregular walk outward from `start`, turning at every step and
        /// never twice by the same amount. Angles are measured off vertical,
        /// and `side` keeps a walk on its own half of the crown.
        ///
        /// Two things are layered to get a fracture rather than a zigzag: a
        /// small constant `drift`, which gives the whole fissure one gentle
        /// curve, and a larger per-step jitter on top of it. Steps are kept
        /// short and numerous so the jitter actually shows as kinks.
        func walk(from start: CGPoint, angle a0: Double, side: Double, steps: Int) -> [CGPoint] {
            var angle = a0
            let drift = (rnd() - 0.5) * 0.16
            var point = start
            var points = [point]
            for _ in 0..<steps {
                angle += drift + (rnd() - 0.5) * 0.44
                // A fissure may not flatten out or cross the blade's axis: a
                // near-horizontal line across the crown reads as a scratch on
                // the photograph, not as a fracture in the stone. The bounds sit
                // wide of the starting angles so the wander is never clipped —
                // clipping is what flattens a walk back into a straight line.
                angle = side * min(max(abs(angle), 0.10), 1.15)
                let length = 5 + rnd() * 8
                point = CGPoint(
                    x: point.x + CGFloat(sin(angle) * length),
                    // Slightly foreshortened: the crown falls away from the
                    // camera, so a fissure covers less height than length.
                    y: point.y + CGFloat(cos(angle) * length * (0.78 + rnd() * 0.22))
                )
                points.append(point)
            }
            return points
        }

        var out: [Fissure] = []
        let trunks = 7
        for i in 0..<trunks {
            // Sides alternate so the stress spreads across the whole crown, but
            // nothing is mirrored: every angle and length is drawn fresh.
            let side: Double = i.isMultiple(of: 2) ? -1 : 1
            // Spread along the slot rather than all from one point: a perfect
            // fan converging on the axis is the tell of a generated pattern.
            let start = CGPoint(
                x: 201 + CGFloat(side * (2 + rnd() * 12)),
                y: 25 + CGFloat(rnd() * 12)
            )
            let angle = side * (0.25 + rnd() * 0.55)
            let points = walk(from: start, angle: angle, side: side, steps: 3 + Int(rnd() * 5))
            // Staggered across the pull, so there is always another one still to
            // come rather than a single burst.
            let appear = 0.05 + (Double(i) / Double(trunks)) * 0.58 + rnd() * 0.05

            out.append(
                Fissure(
                    points: points,
                    appear: appear,
                    span: 0.15 + rnd() * 0.18,
                    width: 0.55 + CGFloat(rnd()) * 0.55,
                    opacity: 0.50 + rnd() * 0.32
                )
            )

            // Most of them fork. The branch leaves from a vertex partway along
            // its parent and opens a moment later, which is what makes the
            // network read as one fracture spreading rather than seven
            // unrelated lines drawn on the rock.
            if rnd() < 0.62, points.count >= 3 {
                let anchor = points[1 + Int(rnd() * Double(points.count - 2))]
                let branchAngle = side * min(max(abs(angle) + (rnd() - 0.3) * 0.6, 0.15), 1.15)
                out.append(
                    Fissure(
                        points: walk(
                            from: anchor, angle: branchAngle, side: side,
                            steps: 2 + Int(rnd() * 3)
                        ),
                        appear: appear + 0.04 + rnd() * 0.05,
                        span: 0.12 + rnd() * 0.14,
                        width: 0.38 + CGFloat(rnd()) * 0.24,
                        opacity: 0.38 + rnd() * 0.22
                    )
                )
            }
        }
        return out
    }()

    static func path(_ fissure: Fissure, in size: CGSize) -> Path {
        let sx = size.width / viewBox.width
        let sy = size.height / viewBox.height
        var path = Path()
        for (i, point) in fissure.points.enumerated() {
            let p = CGPoint(x: point.x * sx, y: point.y * sy)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// Draws the stress fissures straight off `pull` — no `withAnimation` anywhere,
/// so they track the finger with the same zero lag as the blade itself, and
/// unwind just as smoothly when the spring takes the pull back down.
struct StressCrackOverlay: View {
    let pull: Double
    let scale: CGFloat

    var body: some View {
        let size = CGSize(
            width: StressCracks.viewBox.width * scale,
            height: StressCracks.viewBox.height * scale
        )
        ZStack(alignment: .topLeading) {
            ForEach(Array(StressCracks.fissures.enumerated()), id: \.offset) { _, fissure in
                let t = fissure.growth(at: pull)
                if t > 0.001 {
                    let path = StressCracks.path(fissure, in: size)

                    // The fissure itself: hairline, and only as far along as the
                    // force has taken it.
                    path.trim(from: 0, to: t)
                        .stroke(
                            Color.black.opacity(fissure.opacity),
                            style: StrokeStyle(
                                lineWidth: fissure.width * scale,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        // The same lit lower lip the earned cracks carry, so
                        // both catch the upper-left key identically.
                        .shadow(color: .white.opacity(0.065), radius: 0, x: 0.5 * scale, y: 0.8 * scale)
                        .opacity(t)

                    // A heavier root. A real fissure is widest where it starts
                    // and tapers to nothing; a second short pass buys that taper
                    // without needing a variable-width stroke.
                    path.trim(from: 0, to: t * 0.38)
                        .stroke(
                            Color.black.opacity(fissure.opacity * 0.8),
                            style: StrokeStyle(
                                lineWidth: fissure.width * 1.5 * scale,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .opacity(t)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Dust motes (spec §4.1)

/// 14 motes on deterministic pseudo-random positions. Their opacity rises with
/// `progress`, so the room gets dustier and more alive as the day completes.
struct DustMotes: View {
    let progress: Double
    let scale: CGFloat
    let phase: Double

    private static let seeds: [(x: CGFloat, y: CGFloat, size: CGFloat, seed: Double, period: Double, dx: CGFloat, dy: CGFloat)] = {
        var out: [(CGFloat, CGFloat, CGFloat, Double, Double, CGFloat, CGFloat)] = []
        var s: UInt64 = 0x5DEECE66D
        func rnd() -> Double {
            s = (s &* 6364136223846793005 &+ 1442695040888963407)
            return Double((s >> 33) % 100_000) / 100_000
        }
        for _ in 0..<14 {
            out.append((
                58 + CGFloat(rnd()) * 300,
                110 + CGFloat(rnd()) * 310,
                0.9 + CGFloat(rnd()) * 1.5,
                0.35 + rnd() * 0.65,
                9 + rnd() * 11,
                CGFloat(rnd() * 26 - 13),
                CGFloat(-14 - rnd() * 22)
            ))
        }
        return out
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.seeds.enumerated()), id: \.offset) { index, mote in
                // 0 → 1 → 0 over the mote's period, offset per index.
                let local = ((phase + Double(index) * 0.7) / mote.period)
                    .truncatingRemainder(dividingBy: 1)
                let wave = sin(local * .pi * 2)
                let rise = (1 - cos(local * .pi * 2)) / 2

                Circle()
                    .fill(Color(red: 207 / 255, green: 201 / 255, blue: 190 / 255))
                    .frame(width: mote.size * scale, height: mote.size * scale)
                    .opacity((0.05 + progress * 0.22 * mote.seed) * (1 - rise * 0.9))
                    .offset(x: mote.dx * scale * CGFloat(rise), y: mote.dy * scale * CGFloat(rise))
                    .position(x: mote.x * scale, y: (mote.y + CGFloat(wave) * 2) * scale)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sheen (spec §5.4)

/// One travelling highlight, clocked off the scene's timeline.
///
/// Holding a start time rather than an animated 0→1 scalar is what lets two
/// passes overlap: each keeps its own clock, so a new pass never yanks a
/// running one back to the tip. A run simply reaches 1 and stops.
struct SheenRun: Identifiable {
    let id = UUID()
    /// `timeIntervalSinceReferenceDate`, the same clock `TimelineView` reports.
    let start: Double
    let duration: Double
    /// Brightest this pass ever gets, at the middle of its sweep.
    let peak: Double

    func progress(at phase: Double) -> Double {
        guard duration > 0 else { return 1 }
        return min(max((phase - start) / duration, 0), 1)
    }
}

/// The shape of the light: a soft band that crosses the blade diagonally,
/// entering at the top-left and leaving at the bottom-right.
///
/// It is used as a **mask**, so any straight edge or corner in it would show up
/// as a straight edge or corner in the reflection. There is none: the band is a
/// nine-stop bell that falls off to nothing on both sides, it is blurred once
/// more on top of that, and it is far longer than the blade's diagonal so its
/// own ends are never anywhere near the steel.
struct SheenMask: View {
    let progress: Double
    let width: CGFloat
    let height: CGFloat

    /// Degrees off horizontal. Negative tilts the band counter-clockwise — it
    /// lies low-left to high-right and travels along its own normal, which
    /// carries the catch of light down and to the right across the blade.
    private static let tilt: Double = -34

    /// The band's normal, precomputed. `tilt` is a constant, so this never has
    /// to be evaluated per frame.
    private static let normalX = CGFloat(abs(sin(tilt * .pi / 180)))
    private static let normalY = CGFloat(abs(cos(tilt * .pi / 180)))

    /// Band thickness, as a fraction of the blade's length. Wide and dim beats
    /// narrow and bright: a narrow band reads as a drawn line, not as light.
    private static let thickness: CGFloat = 0.30

    /// The final softening pass, as a fraction of the band's thickness.
    private static let blurFraction: CGFloat = 0.16

    var body: some View {
        let band: CGFloat = height * Self.thickness
        let feather: CGFloat = band * Self.blurFraction
        // Distance the band must cover: the sprite's extent measured along the
        // band's own normal, plus its own thickness and the reach of the blur,
        // so it begins and ends completely clear of the steel. Without the
        // feather allowance the blur's tail would rest on the far corner at
        // either end of the sweep.
        let span: CGFloat = Self.normalX * width + Self.normalY * height
            + band + feather * 3
        let travel: CGFloat = span * (CGFloat(progress) - 0.5)

        LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
            .frame(width: hypot(width, height) * 1.4, height: band)
            .blur(radius: feather)
            // `offset` does not move the layout frame, so the rotation below
            // turns this translation too — the band always slides along its own
            // normal, never straight down.
            .offset(y: travel)
            .rotationEffect(.degrees(Self.tilt))
            .frame(width: width, height: height)
    }

    /// A bell, not a ramp. Sampled densely near the centre so the bright core
    /// has no shoulder, and taken all the way to zero at both ends.
    private static let stops: [Gradient.Stop] = [
        .init(color: .white.opacity(0), location: 0),
        .init(color: .white.opacity(0.04), location: 0.14),
        .init(color: .white.opacity(0.18), location: 0.30),
        .init(color: .white.opacity(0.55), location: 0.42),
        .init(color: .white, location: 0.50),
        .init(color: .white.opacity(0.55), location: 0.58),
        .init(color: .white.opacity(0.18), location: 0.70),
        .init(color: .white.opacity(0.04), location: 0.86),
        .init(color: .white.opacity(0), location: 1),
    ]

    /// Fades the pass in and out so it has neither a start nor a stop: zero at
    /// both ends, full only through the middle, and smooth (not linear) at the
    /// joins, so there is no kink where the ramp meets the plateau.
    static func opacity(for progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        return smoothstep(progress / 0.26) * smoothstep((1 - progress) / 0.46)
    }
}

// MARK: - Soft marks

/// A radial fall-off that always dies **inside** its own footprint.
///
/// # The bug this type exists to make unreachable
///
/// Every soft mark in this scene used to be `Ellipse().fill(RadialGradient(…))`
/// with an off-centre `UnitPoint`. That reads as obviously correct and is not:
/// a `RadialGradient` is a **circle in point space**, so a wide, short ellipse
/// crops it top and bottom — and it crops it while the gradient is still at 40
/// to 70 per cent of its peak. What that actually draws is *the ellipse's own
/// outline*, at 40–70 per cent strength, as a hard arc. Nine of the ten marks
/// around the stone were doing it, and so were the floor bounce and the ground
/// shadow; on a near-black plate a 20 per cent step is a line you can trace
/// with a finger. The scene's own doctrine — nothing may read as composited —
/// was being broken by the layers written to sell the opposite.
///
/// So the fall-off is generated in a **square**, where a circular gradient
/// reaching zero at `side / 2` is exactly zero at every edge, and the oval
/// footprint comes from squashing that square afterwards. There is no shape to
/// crop against and no value at any boundary: the mark cannot have an edge.
///
/// # Why the bias is a position and not a `UnitPoint`
///
/// Because they were two knobs for one fact. Every one of these marks wanted
/// "the density sits a little down-right of the contact", and each expressed
/// part of that as a frame position and part of it as a gradient focus — so the
/// real centre of a mark was `position + (focus − 0.5) × size`, which is not a
/// number anybody was reading. The bias is the position now, and where the
/// darkness is is where the view is.
struct SoftPool: View {
    var colors: [Color]
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        let side = max(width, height)
        RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: side / 2)
            .frame(width: side, height: side)
            .scaleEffect(x: width / side, y: height / side)
            .frame(width: width, height: height)
            .allowsHitTesting(false)
    }
}

// MARK: - Socket (spec §4.4)

/// The opening is carved, not cut out — pure gradients, no blur or shadow
/// primitives, so it renders identically on every device.
///
/// The single most important detail: **the shadow lives inside the hole, never
/// above it.** A shadow above the hole makes the stone look like a decal.
///
/// # Two things were wrong here and both were measurable
///
/// **Every mark was clipped.** They were ellipses filled with circular
/// gradients that were still at 40–70% of peak when the ellipse ended, so what
/// each one drew was its own outline as a hard arc. They are `SoftPool`s now —
/// see that type for the arithmetic — and nothing in this file has an edge.
///
/// **The darkness had drifted off the blade.** Measured off a screenshot, the
/// centre of mass of the shading ran from **+11pt at the mouth to +20pt** forty
/// points below it, against a blade on the axis: the hole read as a smudge
/// beside the sword rather than as a socket around it. Three marks were each
/// carrying a right-bias and they compounded — the lip's shade was +12, the
/// contact occlusion +8, and the cast +7 on top of a 70pt ellipse.
///
/// The rule that sorts it: **occlusion is centred, only the cast is offset.**
/// Ambient occlusion is what light cannot reach, and what light cannot reach is
/// the contact itself — it does not move because the key does. A *cast* shadow
/// does, and it is the only thing here allowed to. The key is still upper-left
/// and everything still falls down-right; it falls by four to seven points
/// rather than by twenty.
struct SocketLayers: View {
    let progress: Double
    let isOut: Bool
    let scale: CGFloat

    private var g: SceneGeometry.Type { SceneGeometry.self }

    var body: some View {
        ZStack(alignment: .topLeading) {
            slotLip
            mouthShade
            contactOcclusion
            bladeCast
            rimLight

            if isOut {
                slotGlow
                emptySlot
                hoverCast
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 1.1), value: isOut)
    }

    /// Lit near lip on the key-light side, pooled dark on the far side.
    ///
    /// Both halves are needed: a bare highlight here reads as fog sitting on
    /// the crown rather than as a lip catching the upper-left key.
    private var slotLip: some View {
        ZStack(alignment: .topLeading) {
            SoftPool(
                colors: [
                    Color(red: 234 / 255, green: 242 / 255, blue: 1).opacity(0.09 + progress * 0.04),
                    .clear,
                ],
                width: 34 * scale, height: 15 * scale
            )
            .position(x: (g.axis - 9) * scale, y: (g.mouth - 6) * scale)

            SoftPool(
                colors: [Color(red: 3 / 255, green: 4 / 255, blue: 6 / 255).opacity(0.32), .clear],
                width: 38 * scale, height: 17 * scale
            )
            .position(x: (g.axis + 6) * scale, y: (g.mouth + 4) * scale)
        }
        .opacity(isOut ? 0.35 : 1)
    }

    /// The blade's base disappears into darkness rather than stopping at an
    /// edge. Kept narrow and feathered so it reads as shading on the blade, not
    /// as a dark rectangle laid on the stone. Dead on the axis: this is the
    /// mouth, and the mouth is where the blade is.
    private var mouthShade: some View {
        SoftPool(
            colors: [
                Color(red: 2 / 255, green: 3 / 255, blue: 5 / 255).opacity(0.92),
                Color(red: 2 / 255, green: 3 / 255, blue: 5 / 255).opacity(0.5),
                .clear,
            ],
            width: (g.bladeWidth + 12) * scale, height: 26 * scale
        )
        .position(x: g.axis * scale, y: (g.mouth + 1) * scale)
        .opacity(isOut ? 0.1 : 1)
    }

    /// Ambient occlusion where blade meets stone. **Centred**, near enough: it
    /// is the contact that is dark, not the side of it the sun is not on.
    ///
    /// Sits 2pt higher than it did, and `bladeCast` came up with it by the same
    /// two. Together they are the dark patch a person actually sees around the
    /// entry point, and it had settled a shade low against the mouth — which
    /// reads as the shadow belonging to the crown rather than to the blade going
    /// into it. Nothing about either mark's size, feathering or opacity changed;
    /// they are the same two pools, two points up.
    private var contactOcclusion: some View {
        SoftPool(
            colors: [Color(red: 4 / 255, green: 5 / 255, blue: 7 / 255).opacity(0.40), .clear],
            width: 58 * scale, height: 24 * scale
        )
        .position(x: (g.axis + 2) * scale, y: g.mouth * scale)
        .opacity(isOut ? 0 : 1)
    }

    /// The blade's own shadow laid across the crown while seated — soft,
    /// down-right, never a hard contact edge. The one mark here that is
    /// *supposed* to be off the axis, and now the only one that is.
    private var bladeCast: some View {
        SoftPool(
            colors: [.black.opacity(0.34), .black.opacity(0.12), .clear],
            width: 72 * scale, height: 30 * scale
        )
        // 2pt up, with `contactOcclusion`. Still down-right of the axis, which
        // is the one thing here that is supposed to be.
        .position(x: (g.axis + 6) * scale, y: (g.mouth + 5) * scale)
        .opacity(isOut ? 0 : 0.35 + progress * 0.25)
    }

    private var rimLight: some View {
        SoftPool(
            colors: [Color(red: 196 / 255, green: 210 / 255, blue: 230 / 255), .clear],
            width: 26 * scale, height: 6 * scale
        )
        .position(x: (g.axis - 2) * scale, y: (g.mouth - 4) * scale)
        .opacity(isOut ? 0.04 : 0.10 + progress * 0.16)
    }

    // MARK: Freed-state layers

    /// Where the blade was.
    ///
    /// Deliberately *not* a black cut-out: a punched hole reads as a sticker on
    /// the photograph. This is a shallow scuff — a soft recess shaded down-right
    /// away from the upper-left key, with a faint polished lip on the lit side.
    /// The cracks radiating from it carry most of the storytelling.
    private var emptySlot: some View {
        ZStack(alignment: .topLeading) {
            SoftPool(
                colors: [
                    Color(red: 6 / 255, green: 7 / 255, blue: 10 / 255).opacity(0.30),
                    Color(red: 6 / 255, green: 7 / 255, blue: 10 / 255).opacity(0.12),
                    .clear,
                ],
                width: 44 * scale, height: 20 * scale
            )
            .position(x: (g.axis + 3) * scale, y: (g.mouth + 2) * scale)

            SoftPool(
                colors: [
                    Color(red: 226 / 255, green: 236 / 255, blue: 252 / 255).opacity(0.10),
                    .clear,
                ],
                width: 32 * scale, height: 13 * scale
            )
            .position(x: (g.axis - 6) * scale, y: (g.mouth - 4) * scale)
        }
        .transition(.opacity.animation(.easeOut(duration: 1.3).delay(0.28)))
    }

    /// The shadow of the blade now hovering above the stone — proof it floats.
    /// Soft, offset down-right, laid across the crown.
    private var hoverCast: some View {
        SoftPool(
            colors: [.black.opacity(0.32), .black.opacity(0.1), .clear],
            width: 94 * scale, height: 34 * scale
        )
        .position(x: (g.axis + 8) * scale, y: (g.mouth + 12) * scale)
        .transition(.opacity.animation(.easeOut(duration: 1.4).delay(0.30)))
    }

    private var slotGlow: some View {
        SoftPool(
            colors: [
                Color(red: 214 / 255, green: 226 / 255, blue: 240 / 255).opacity(0.05),
                .clear,
            ],
            width: 130 * scale, height: 70 * scale
        )
        .position(x: g.axis * scale, y: (g.mouth + 2) * scale)
        .transition(.opacity.animation(.easeOut(duration: 1.4).delay(0.28)))
    }
}

// MARK: - Grip affordance (spec §5.5)

// `GripRing` used to live here: a 44×66 rounded rectangle, stroked half a point
// of white and pulsed, laid over the grip to say where the thumb goes.
//
// It was the single most visible compositing artifact in the app. Measured off
// a screenshot, its left edge stood **+18/255 brighter than the plate beside
// it** — a hard vertical line with a semicircular cap, hanging in the room to
// the left of the blade, ending in mid-air. Everything the scene's doctrine
// forbids in one 44-point box: an additive layer outside the sprite's
// silhouette, with an edge, that no light in the room could have made.
//
// The affordance was worth keeping and the shape was not, so it is light on the
// grip instead — `SwordSceneView.gripHint`, drawn from the sprite and masked by
// it, which is the same trick `sheenPass` uses and cannot bleed by
// construction.
