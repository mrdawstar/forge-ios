import SwiftUI

/// The Forge scene: a heavy sword in real stone, in a dark room lit from the
/// upper left (spec §4, §5).
///
/// Doctrine that must not be violated:
/// 1. One key light, upper-left. Every shadow falls **down and to the right**;
///    every specular sits on the **left** bevel.
/// 2. Lighting is baked into the sprite, never added as blend layers. No glow,
///    no halo, no bloom — an additive layer extends past the sprite's bounds
///    and instantly reads as a cut-out pasted onto a photo.
/// 3. A single `progress` scalar drives every lighting cue, so the scene reads
///    as photographed rather than composited.
struct SwordSceneView: View {

    @Bindable var vm: ForgeViewModel
    var engine: SwordEngine
    var swords: SwordStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chips: [StoneChip] = []
    @State private var sheens: [SheenRun] = []
    @State private var didArmLooseState = false

    /// The blade being faded out after an equip, and how far the swap has run.
    @State private var outgoingAsset: String?
    @State private var swapMix: Double = 1
    @State private var swapToken = 0

    private var g: SceneGeometry.Type { SceneGeometry.self }

    /// Live pull, straight off the physics engine — no animation anywhere on
    /// this path, which is what gives the drag zero lag.
    private var pull: Double { engine.pos }

    /// The scene has to agree with the sheet. The first pull is granted with the
    /// list unfinished, and a blade the panel is calling loose should not still
    /// be sitting a third of the way out of the stone.
    private var doneFraction: Double {
        if vm.allDone { return 1 }
        return vm.totalActive > 0 ? Double(vm.totalDone) / Double(vm.totalActive) : 0
    }

    /// `progress = (done/total)·0.85 + pull·0.15` — one scalar for the room
    /// brightness, floor bounce, haze, motes, sword brightness and cracks.
    ///
    /// Pinned once the blade is out, for the same reason `outRest` is: both
    /// inputs are unstable afterwards, so a relaunched earned day was lit
    /// differently from the one the user had just watched being earned.
    private var progress: Double {
        if vm.isOut { return 1 }
        return doneFraction * 0.85 + pull * 0.15
    }

    /// The blade is loose but still seated: rituals are done, nothing pulled.
    private var isLoose: Bool { vm.allDone && !vm.isOut }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let scale = w / SceneGeometry.canvasWidth

            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate

                ZStack(alignment: .topLeading) {
                    sceneBody(w: w, h: h, scale: scale, phase: phase)

                    // Chrome is HUD, so it sits above the scene.
                    chrome(scale: scale)
                }
                .frame(width: w, height: h, alignment: .topLeading)
                // The room is shot from a locked-off camera (§5.7). There is no
                // dolly, no zoom and no offset on the scene stack, so the plate
                // is pinned for the whole sequence and can never slide down to
                // expose a black bar at the top. Everything that used to be
                // sold by moving the camera is sold by the sword instead: it
                // lifts, it comes toward the lens, the stone settles.
                .clipped()
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    pullZone(scale: scale)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { armEngine() }
        .onChange(of: vm.totalDone) { _, newValue in
            ritualCommitted(isLast: newValue >= vm.totalActive && vm.totalActive > 0)
        }
        .onChange(of: vm.isOut) { wasOut, isOut in
            // The sword returns to the stone (§5.10). The pull has to be wound
            // back down, or `pull` stays pinned at 1 and every value that reads
            // it — chrome opacity, the extra 46pt of lift, the stone's sag, the
            // stress cracks — stays stuck with it.
            guard wasOut, !isOut else { return }
            engine.release()
            ForgeAudio.shared.stopGrind()
            ForgeAudio.shared.undo()
            ForgeHaptics.shared.swordReseated()
        }
        .onChange(of: swordAsset) { previous, _ in
            crossfadeBlade(from: previous)
        }
    }

    /// Hands the outgoing sprite to the layer above and fades between them.
    private func crossfadeBlade(from previous: String) {
        guard !reduceMotion else { return }
        swapToken += 1
        let token = swapToken

        outgoingAsset = previous
        swapMix = 0
        withAnimation(.easeInOut(duration: 0.55)) { swapMix = 1 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            // A second equip mid-fade owns the transition now; dropping the
            // outgoing sprite here would cut its fade short.
            if swapToken == token { outgoingAsset = nil }
        }
    }

    // MARK: - Changing world

    private static let weatherFade: Double = 1.5

    // MARK: - Scene stack

    @ViewBuilder
    private func sceneBody(w: CGFloat, h: CGFloat, scale: CGFloat, phase: Double) -> some View {
        ZStack(alignment: .topLeading) {
            backgroundPlate(w: w, h: h)
            fullBleed(w: w, h: h) { grade() }


            if !reduceMotion {
                DustMotes(progress: progress, scale: scale, phase: phase)
            }

            // Everything with mass in the room. It settles as one body when the
            // blade comes free, so the stone can never slide out from under its
            // own contact shadow — the giveaway that a scene was assembled from
            // layers rather than photographed.
            ZStack(alignment: .topLeading) {
                floorBounce(scale: scale)
                groundShadow(scale: scale)

                // z2 — the blade, behind the stone.
                swordLayer(scale: scale, phase: phase)

                // z4…z7 — everything attached to the stone shares one transform,
                // so the slot can never drift off the sword's axis.
                stoneGroup(scale: scale)

                chipsLayer(scale: scale)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .offset(y: subjectSettle * scale)
            .animation(.settle(2.4), value: vm.isOut)

            fullBleed(w: w, h: h) { atmosphere(scale: scale) }


            // **Not** full-bleed, and it carries its own frame. Both halves
            // matter and the second one is the fix that had been missed twice.
            //
            // Every other layer here is a texture that would show a rounding
            // seam at the frame's edge, so it is over-sized and re-centred. This
            // one is bottom-*anchored* and has to end exactly where the screen
            // does, which is why it was taken out of `fullBleed`.
            //
            // Taking it out was not enough. A `ZStack` sizes itself to its
            // largest child, and two of the children above are `fullBleed` —
            // `h * 1.14`. So the stack's own height was 996 on a 874pt phone,
            // that is what got proposed to this `VStack`, and the band's bottom
            // landed 122pt below the screen with only ~62% of the smoothstep on
            // it. `.frame(alignment: .topLeading)` then cropped the overhang
            // away rather than pulling it back up. The darkening therefore
            // peaked at 45% of full at the bottom of the screen while the
            // photograph's own floor was getting brighter — so the room lifted
            // toward the panel instead of falling away under it, and the
            // mismatch between a half-dark room and the panel's ground read as
            // a horizontal band that looked like a rendering failure.
            //
            // The explicit frame is what pins the band to the screen rather
            // than to whatever the tallest sibling happens to be. Measured
            // after the fact: the band now runs 554→874, and the smoothstep
            // finishes on screen.
            bottomVignette(w: w, h: h, scale: scale)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    /// The freed composition eases down to clear the top safe area: on a
    /// Dynamic Island phone the pommel would otherwise hang at y≈49, right
    /// under the cutout. Only the subjects move — the plate, the grade and the
    /// vignette stay exactly where they are.
    private var subjectSettle: CGFloat {
        vm.isOut ? g.outSettle : 0
    }

    // MARK: - Room (§4.1)

    /// Every full-bleed layer is over-sized by this much. The plate no longer
    /// moves, so this is pure insurance: the background photo is cropped to
    /// fill rather than fitted, and a rounding error at the frame's edge can
    /// never surface as a seam.
    private static let bleed: CGFloat = 1.14

    private func fullBleed<Content: View>(
        w: CGFloat, h: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        let inset = (Self.bleed - 1) / 2
        return content()
            .frame(width: w * Self.bleed, height: h * Self.bleed)
            .offset(x: -w * inset, y: -h * inset)
    }

    /// One drawable plate: a filename, and the composition it was cropped for.
    ///
    /// Forge's own room is `hero: nil`, which is also what every world that has
    /// not been drawn yet resolves to.
    /// The room, which is now only ever Forge's own.
    ///
    /// Kept as a type rather than collapsed into the string it holds because
    /// the crossfade machinery below still takes one, and because a second
    /// plate is a plausible thing to want again — a seasonal room, a night
    /// room — without a world system to hang it on.
    private struct Plate: Equatable {
        var asset: String { "scene-background" }
    }

    /// The plate the room is standing in. Forge's own until a world names one.
    private var plate: Plate { Plate() }

    private func backgroundPlate(w: CGFloat, h: CGFloat) -> some View {
        fullBleed(w: w, h: h) {
            ZStack {
                plateImage(plate, w: w, h: h)
            }
        }
        .brightness(progress * 0.10)
        .animation(.easeInOut(duration: 1.6), value: doneFraction)
    }

    private func plateImage(_ plate: Plate, w: CGFloat, h: CGFloat) -> some View {
        let fw = w * Self.bleed
        let fh = h * Self.bleed

        return Image(plate.asset)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: fw, height: fh)
            .frame(width: fw, height: fh)
            .clipped()
    }

    /// How far to slide a plate inside the width the crop is throwing away.
    ///
    /// Computed from the plate's own proportions against the frame it is being
    /// cropped into, rather than baked in as points, because the spare width is
    /// not the same on every phone. Expressing the bias as a fraction of
    /// whatever is actually spare is what makes it impossible to slide a black
    /// edge into view on a screen this was not measured on — at worst the plate
    /// ends up hard against one side.

    /// Where the room's light is coming from.
    ///
    /// Forge's is just off the top-left corner, which is where it has always
    /// been and where every sprite in the catalog is lit from. A world can move
    /// it onto whatever its plate actually shows as the source — and that is
    /// the whole idea behind the Vigil: Forge has been lit from the upper left
    /// since the first build, and in this world you can finally see what by.
    private var keyLight: UnitPoint {
        UnitPoint(x: 0.04, y: -0.06)
    }

    /// A bloom bedded into the key light plus a long top ramp. There must be no
    /// hard horizontal edge anywhere in the beam.
    private func grade() -> some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 238 / 255, green: 244 / 255, blue: 1).opacity(0.11), .clear],
                center: keyLight,
                startRadius: 0,
                endRadius: 420
            )
            LinearGradient(
                stops: [
                    .init(color: Color(red: 4 / 255, green: 5 / 255, blue: 6 / 255).opacity(0.20), location: 0),
                    .init(color: Color(red: 4 / 255, green: 5 / 255, blue: 6 / 255).opacity(0.08), location: 0.12),
                    .init(color: .clear, location: 0.26),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    /// A soft pool of bounced light landing just left of the stone. No hotspot,
    /// no visible ellipse edge — and until now it had one.
    ///
    /// It was a 760×360 ellipse filled with a circular gradient of radius 180
    /// focused at `UnitPoint(0.40, 0.30)`. The focus sits 104pt above the
    /// ellipse's top boundary at that column, so the ellipse cut the gradient
    /// off **while it was still at 42% of peak** — drawing its own top arc, in
    /// bounced light, across the middle-left of the room. See `SoftPool`, which
    /// makes that shape of mistake unavailable.
    private func floorBounce(scale: CGFloat) -> some View {
        SoftPool(
            colors: [
                Color(red: 210 / 255, green: 224 / 255, blue: 246 / 255)
                    .opacity(0.03 + progress * 0.035 + (vm.isOut ? 0.02 : 0)),
                .clear,
            ],
            width: 760 * scale, height: 360 * scale
        )
        // Where the old focus actually landed, now that the focus *is* the
        // position: 94pt from the left of the room, 72pt above the mouth.
        .position(x: 94 * scale, y: (g.mouth - 146) * scale)
        .animation(.easeInOut(duration: 1.6), value: doneFraction)
    }

    /// The ground under the stone. Same fix as the bounce: the old ellipse
    /// clipped a 130pt gradient 28pt from its focus, so 47% of a black fall-off
    /// stopped dead along an arc — with only 15pt of blur over it.
    ///
    /// **It sits 14pt higher than it did**, at `mouth + 34`. The pool is drawn
    /// where the stone's mass meets the floor, and the stone had drifted up the
    /// frame relative to it over the compositing passes — so the dark was
    /// pooling a little below the rock rather than under it, which reads as the
    /// stone hovering. Moving the shadow rather than the stone is deliberate:
    /// the stone is on the sword's axis by measurement (`rockLeft`), and the
    /// pool is the only thing here with no landmark of its own to be wrong
    /// about. It moves with the rest of the mass on `outSettle`, so nothing can
    /// slide out from under it when the blade comes free.
    private func groundShadow(scale: CGFloat) -> some View {
        SoftPool(
            colors: [.black.opacity(0.6), .black.opacity(0.3), .clear],
            width: 300 * scale, height: 96 * scale
        )
        .position(x: (g.axis - 24) * scale, y: (g.mouth + 34) * scale)
        .blur(radius: 15 * scale)
    }

    private func atmosphere(scale: CGFloat) -> some View {
        LinearGradient(
            colors: [
                Color(red: 226 / 255, green: 234 / 255, blue: 248 / 255).opacity(0.045 + progress * 0.02),
                Color(red: 226 / 255, green: 234 / 255, blue: 248 / 255).opacity(0.02),
                .clear,
            ],
            startPoint: UnitPoint(x: 0.0, y: 0.2),
            endPoint: UnitPoint(x: 0.7, y: 0.6)
        )
        .allowsHitTesting(false)
    }

    /// The room falling away under the panel.
    ///
    /// It used to be four evenly-spaced colour stops over 230pt, and a linear
    /// ramp from nothing to 30% inside the first 77 of those is a **visible
    /// line**: the eye finds the place where a gradient starts, not the place
    /// where it is darkest, and the giveaway is the second derivative rather
    /// than the slope. It read as a sheet of dark glass laid across the
    /// photograph — worst of all on an earned day, which is exactly where it
    /// showed. Three things happen at once when the blade comes free: the plate
    /// brightens (`progress` hits 1), the whole physical composition sinks
    /// 116pt on `outSettle`, and the stone's crown therefore slides down
    /// *across* this band. A hard onset drawn over a moving subject is a hard
    /// onset somebody can watch travelling.
    ///
    /// So: no stop with a corner in it. `vignetteStops` is a smoothstep, which
    /// leaves the top of the band with zero slope *and* zero curvature — there
    /// is no first frame of it to see. It is also 320pt rather than 230, which
    /// buys the curve the room to be that gentle.
    ///
    /// And a whisper of frost under it. A fade alone still darkens detail into
    /// mush at the bottom; a little defocus is what a real lens does with the
    /// near floor, so the room dissolves rather than dims. It is masked by the
    /// same curve, at a fraction of the strength, and it sits *under* the
    /// gradient so the two read as one fall-off rather than two overlays.
    private func bottomVignette(w: CGFloat, h: CGFloat, scale: CGFloat) -> some View {
        VStack {
            Spacer()
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            stops: Self.vignetteStops(.white, peak: 0.55),
                            startPoint: .top, endPoint: .bottom
                        )
                    }

                LinearGradient(
                    stops: Self.vignetteStops(
                        Color(red: 0.010, green: 0.014, blue: 0.019), peak: 1
                    ),
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(height: 320 * scale)
        }
        // The screen, explicitly. See the call site — without this the band is
        // proposed the ZStack's over-sized height and its darkest end falls off
        // the bottom of the phone.
        .frame(width: w, height: h, alignment: .bottom)
        .allowsHitTesting(false)
    }

    /// A smoothstep laid out as gradient stops.
    ///
    /// `LinearGradient` interpolates linearly between whatever it is given, so
    /// a curve has to be sampled into it. Sixteen is comfortably past the point
    /// where the straight segments between samples are visible, and the cubic
    /// is squared on top so the first third of the band is nearly nothing —
    /// which is the whole trick: the darkening has to have begun before there
    /// is anything to notice beginning.
    private static func vignetteStops(_ color: Color, peak: Double) -> [Gradient.Stop] {
        (0...16).map { step in
            let t = Double(step) / 16
            let eased = smoothstep(t)
            return Gradient.Stop(
                color: color.opacity(eased * eased * peak),
                location: t
            )
        }
    }

    // MARK: - Sword (§5.1–5.4)

    /// Straight off the shared store, so the blade in the stone is always the
    /// blade the collection says is equipped — unless a world has lent one.
    ///
    /// A skin dresses this scene and reaches no further. The collection goes on
    /// showing the seven real blades and which of them is equipped, because
    /// those are earned and the record of them is not a Path's to edit: walking
    /// a world borrows its blade, and coming back to Forge hands yours straight
    /// back. Nothing here touches what unlocks, what is carried, or what the
    /// stone does when it is pulled.
    private var swordAsset: String { swords.equippedSceneAsset }

    private func bladeSprite(_ name: String, scale: CGFloat) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: g.swordWidth * scale, height: g.swordHeight * scale)
    }

    @ViewBuilder
    private func swordLayer(scale: CGFloat, phase: Double) -> some View {
        let idle = idleOffset(phase: phase)

        ZStack(alignment: .topLeading) {
            // Equipping a different blade cross-fades rather than swapping on
            // one frame. It matters in exactly one place — accepting a newly
            // unlocked sword while the old one is hanging in plain sight — and
            // costs a second sprite only while a swap is actually running.
            ZStack {
                if let outgoing = outgoingAsset, swapMix < 1 {
                    bladeSprite(outgoing, scale: scale)
                        .opacity(1 - swapMix)
                }
                bladeSprite(swordAsset, scale: scale)
                    .opacity(swapMix)
            }
                .frame(width: g.swordWidth * scale, height: g.swordHeight * scale)
                // Slight transparency and desaturation put the blade *in* the
                // room's air instead of on top of it.
                .opacity(0.955)
                // Kept close to the sprite's own exposure. Lifting brightness
                // for the freed state blew the steel out to near-white and lost
                // the baked bevel; the blade reads as *awake* through the slow
                // glint below instead.
                .brightness(-0.06 + progress * 0.07)
                .contrast(0.96 + progress * 0.04)
                .saturation(0.94)
                // Soft, down-right — never a hard contact shadow.
                .shadow(color: .black.opacity(0.42), radius: 7 * scale, x: 2.4 * scale, y: 3.4 * scale)
                .overlay { sheenOverlay(scale: scale, phase: phase) }
                .overlay { idleGlint(scale: scale, phase: phase) }
                .overlay { gripHint(scale: scale, phase: phase) }


        }
        .frame(width: g.swordWidth * scale, height: g.swordHeight * scale, alignment: .topLeading)
        // Idle breathing / levitation rides on the sprite …
        .offset(y: idle.offset * scale)
        .rotationEffect(.degrees(idle.rotation), anchor: .bottom)
        // … while the pull and the step lift ride on the container.
        .scaleEffect(vm.isOut ? g.outSwordScale : 1, anchor: .bottom)
        .animation(.settle(2.4), value: vm.isOut)
        .offset(y: -(stepLift + pullLiftAmount) * scale)
        .animation(.settle(vm.isOut ? 2.4 : 2.1), value: stepLift)
        .position(
            x: (g.swordLeft + g.swordWidth / 2) * scale,
            y: (g.seatTop + g.swordHeight / 2) * scale
        )
        .allowsHitTesting(false)
    }

    /// Step lift is discrete and settles; pull lift is continuous and does not.
    ///
    /// Once the blade is out, neither is read at all: the resting height is the
    /// single constant in `SceneGeometry.outRest`, so an earned day hangs in
    /// exactly one place whether it was just pulled, come back to from another
    /// tab, or found there on the next launch.
    private var stepLift: CGFloat {
        guard !vm.isOut else { return g.outRest }
        return CGFloat(doneFraction) * g.travel
    }

    /// The drag is over the moment the blade is free. Leaving it in the sum is
    /// what made the blade sit 46pt higher immediately after the break than it
    /// did anywhere else.
    private var pullLiftAmount: CGFloat {
        vm.isOut ? 0 : CGFloat(pull) * g.pullLift
    }

    /// Three distinct idles (§5.2). The sword is never perfectly still — except
    /// when it is stuck, and that stillness is what makes the later motion feel
    /// earned.
    private func idleOffset(phase: Double) -> (offset: CGFloat, rotation: Double) {
        guard !reduceMotion else { return (0, 0) }

        if vm.isOut {
            // hoverIdle — levitation, 5.6s, with a whisper of roll.
            let t = (phase / 5.6).truncatingRemainder(dividingBy: 1)
            let wave = (1 - cos(t * .pi * 2)) / 2
            return (-4 * CGFloat(wave), 0.5 * wave)
        }
        if isLoose && pull < 0.02 {
            // breathe — barely perceptible. The sword is alive and wants out.
            let t = (phase / 4.6).truncatingRemainder(dividingBy: 1)
            let wave = (1 - cos(t * .pi * 2)) / 2
            return (-2.4 * CGFloat(wave), 0)
        }
        // Seated and stuck: dead still.
        return (0, 0)
    }

    /// A slow catch of light travelling the freed blade — the levitating sword
    /// is "a little bit shining" rather than brightened overall. One pass per
    /// hover cycle, occupying only the first half of it, so most of the time the
    /// blade simply hangs there.
    @ViewBuilder
    private func idleGlint(scale: CGFloat, phase: Double) -> some View {
        if vm.isOut && !reduceMotion {
            let cycle = (phase / 5.6).truncatingRemainder(dividingBy: 1)
            let sweep = cycle / 0.5
            if sweep < 1 {
                sheenPass(
                    progress: sweep,
                    scale: scale,
                    brightness: 0.16,
                    opacity: SheenMask.opacity(for: sweep) * 0.26
                )
            }
        }
    }

    /// Every travelling highlight currently in flight. Runs are clocked off the
    /// timeline rather than driven by `withAnimation`, so two that overlap
    /// simply cross-fade past each other — the newer one can never snap the
    /// older one back to the tip mid-sweep.
    private func sheenOverlay(scale: CGFloat, phase: Double) -> some View {
        ZStack {
            ForEach(sheens) { run in
                let p = run.progress(at: phase)
                if p > 0 && p < 1 {
                    sheenPass(
                        progress: p,
                        scale: scale,
                        brightness: 0.34,
                        opacity: SheenMask.opacity(for: p) * run.peak
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Where the thumb goes, once the blade is loose.
    ///
    /// # Why this is light on the steel and not a ring around it
    ///
    /// It used to be `GripRing`: a stroked, pulsing rounded rectangle laid over
    /// the grip. On a photograph of a dark room that is a drawn box, and it
    /// measured like one — its left edge stood eighteen levels brighter than the
    /// plate beside it, a hard vertical line with a semicircular cap ending in
    /// mid-air to the left of the blade. It is the exact failure the scene's
    /// second rule exists to prevent: *an additive layer that extends past the
    /// sprite's bounds instantly reads as a cut-out pasted onto a photo.*
    ///
    /// So the hint is made the way every other highlight in this scene is made
    /// — a brightened copy of the sprite, masked. It cannot leave the steel,
    /// because it **is** the steel; the grip simply comes up out of the dark and
    /// goes back down, on the same 2.6s breath the ring pulsed on. A pointing
    /// finger with no outline, which is what the affordance was always for.
    ///
    /// The band is expressed as a fraction of the sprite's height so it stays
    /// on the grip whichever blade is equipped: the pommel and the wrap occupy
    /// the top fifth of every sprite in the catalogue.
    @ViewBuilder
    private func gripHint(scale: CGFloat, phase: Double) -> some View {
        if isLoose && !engine.isDragging && pull < 0.04 && !reduceMotion {
            let cycle = (phase / 2.6).truncatingRemainder(dividingBy: 1)
            let wave = (1 - cos(cycle * .pi * 2)) / 2

            Image(swordAsset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: g.swordWidth * scale, height: g.swordHeight * scale)
                .brightness(0.34)
                .saturation(0.5)
                .mask {
                    // Feathered at both ends, so the light has no start and no
                    // finish anybody can point at.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white, location: 0.055),
                            .init(color: .white, location: 0.135),
                            .init(color: .clear, location: 0.205),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .opacity(0.10 + wave * 0.16)
                .allowsHitTesting(false)
        }
    }

    /// One pass of light: a brightened copy of the sprite behind a soft,
    /// diagonal mask. Because it *is* the sprite, it can never bleed outside the
    /// blade's silhouette — all of the feathering lives inside the mask, never
    /// as a blur on the lit copy, which would halo past the steel.
    private func sheenPass(
        progress: Double, scale: CGFloat, brightness: Double, opacity: Double
    ) -> some View {
        Image(swordAsset)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: g.swordWidth * scale, height: g.swordHeight * scale)
            .brightness(brightness)
            .saturation(0.45)
            .mask(
                SheenMask(
                    progress: progress,
                    width: g.swordWidth * scale,
                    height: g.swordHeight * scale
                )
            )
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    // MARK: - Stone (§4.3, §4.4, §4.5)

    private func stoneGroup(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // **Opaque.** It was 0.9, which is a tenth of everything drawn
            // behind it coming through the rock — and what is drawn behind it
            // is the blade, plus the blade's own 0.42 drop shadow. Both have
            // hard vertical edges, so the stone carried a faint ghost of the
            // sword down its face with two straight seams on it: the one thing
            // a photographed scene can never have. Whatever bedding-in the 0.9
            // was for, `atmosphere` does over the top of the subjects anyway.
            Image("rock-lit")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: g.rockWidth * scale, height: g.rockHeight * scale)
                .clipped()
                .brightness(progress * 0.07)
                .position(
                    x: (g.rockLeft + g.rockWidth / 2) * scale,
                    y: (g.rockTop + g.rockHeight / 2) * scale
                )

            // Both crack layers carry the same drift, so the fissures sit on
            // the rock's own centre line rather than on the sword's axis.
            CrackOverlay(doneCount: vm.totalDone, isOut: vm.isOut, scale: scale)
                .offset(x: g.crackDrift * scale, y: StoneCracks.originY * scale)

            // Reads `pull` directly, so the fissures open and close with the
            // finger rather than chasing it through an animation — and closes
            // them once there is no finger. Stress held in stone by a hand that
            // let go a day ago was the same drift the blade had: fully drawn the
            // instant it broke, gone after a relaunch.
            StressCrackOverlay(pull: vm.isOut ? 0 : pull, scale: scale)
                .offset(x: g.crackDrift * scale, y: StressCracks.originY * scale)

            SocketLayers(progress: progress, isOut: vm.isOut, scale: scale)
        }
        // One shared transform, scaled about the mouth.
        .scaleEffect(g.rockScale, anchor: mouthUnitPoint(scale: scale))
        // Nothing here tracks the pull: the stone holds still for the whole
        // haul and settles only once the blade is out, on the Settle curve.
        .offset(y: (g.rockDrop + (vm.isOut ? g.outRockDrop : 0)) * scale)
        .animation(.settle(2.4), value: vm.isOut)
        .allowsHitTesting(false)
    }

    // MARK: - Camera (§5.7)

    private func mouthUnitPoint(scale: CGFloat) -> UnitPoint {
        // The stone group is laid out on the full canvas, so the mouth's unit
        // position is simply its canvas fraction.
        UnitPoint(
            x: g.axis / SceneGeometry.canvasWidth,
            y: g.mouth / (SceneGeometry.canvasWidth * 874 / 402)
        )
    }

    // MARK: - Chips

    private func chipsLayer(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(chips) { chip in
                StoneChipView(chip: chip, scale: scale)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Chrome (§4.6)

    private func chrome(scale: CGFloat) -> some View {
        HStack {
            Text("FORGE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(3.96)
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            // Days kept, not the streak. The streak was here to be
            // protected — a number that only ever falls to zero, sitting on the
            // home screen where it could be lost. This one counts up and stays
            // up, which makes it a description of somebody rather than something
            // they are holding on to.
            //
            // Before the first day is kept it says DAY ONE rather than a zero
            // — see `HomeCopy.daysBadge`.
            let badge = HomeCopy.daysBadge(daysKept: vm.daysKept)
            HStack(spacing: 7) {
                if let count = badge.count {
                    Text(count)
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Text(badge.word)
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(1.33)
                    .foregroundStyle(.white.opacity(badge.count == nil ? 0.85 : 0.6))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(badge.accessibility))
        }
        .padding(.horizontal, 24)
        .padding(.top, 58)
        // The floor-bounce ellipse is ~1.9x the screen width and stretches the
        // ZStack; without this the streak badge lands off-screen.
        .frame(width: SceneGeometry.canvasWidth * scale, alignment: .leading)
        // The UI gets out of the way as the hand takes over, but comes back
        // fully once the blade is free.
        .opacity(vm.isOut ? 1 : 1 - pull * 0.85)
        .animation(vm.isOut ? .easeInOut(duration: 1.1).delay(0.5) : nil, value: vm.isOut)
        .allowsHitTesting(false)
    }

    // MARK: - Gesture (§5.6)

    /// A full-width invisible zone, present only while the blade is loose.
    @ViewBuilder
    private func pullZone(scale: CGFloat) -> some View {
        if isLoose {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: SceneGeometry.canvasWidth * scale, height: 480 * scale)
                .offset(y: 110 * scale)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !engine.isDragging {
                                engine.dragBegan(atY: value.startLocation.y / scale)
                            }
                            engine.dragChanged(toY: value.location.y / scale)
                        }
                        .onEnded { _ in
                            engine.dragEnded()
                        }
                )
                .accessibilityLabel("Pull the sword free")
                .accessibilityHint("Drag upward against the resistance")
        }
    }

    // MARK: - Engine wiring

    private func armEngine() {
        guard !didArmLooseState else { return }
        didArmLooseState = true

        ForgeHaptics.shared.prepare()

        engine.onDragBegan = {
            ForgeAudio.shared.startGrind()
            ForgeHaptics.shared.startDragScrape()
        }

        engine.onDragEnded = {
            ForgeAudio.shared.stopGrind()
            ForgeHaptics.shared.stopDragScrape()
        }

        engine.onFrame = { pos, vel in
            vm.pull = pos
            ForgeAudio.shared.updateGrind(pos: pos, vel: vel)
            ForgeHaptics.shared.updateDragScrape(pull: pos)
        }

        // A catch: a dry crack, a sharp haptic, and five chips.
        engine.onCatch = {
            ForgeAudio.shared.catchCrack()
            ForgeHaptics.shared.catchTick()
            spawn(StoneChip.burst(count: 5, spread: 26, big: false))
        }

        engine.onFrictionTick = {
            ForgeHaptics.shared.frictionTick()
        }

        engine.onBottomOut = {
            ForgeAudio.shared.bottomOut()
            ForgeHaptics.shared.bottomOut()
        }

        engine.onSlipBack = {
            // No error state, no message — it just didn't come.
            ForgeAudio.shared.slipBack()
        }

        engine.onBreakFree = {
            breakFreeSequence()
        }
    }

    // MARK: - Beats

    /// One coordinated beat when a ritual is committed (§21.2).
    private func ritualCommitted(isLast: Bool) {
        guard vm.totalDone > 0 else { return }
        ForgeAudio.shared.ritualCommitted()
        if isLast {
            ForgeHaptics.shared.lastRitualVerified()
        } else {
            ForgeHaptics.shared.ritualVerified()
        }
        spawn(StoneChip.burst(count: isLast ? 18 : 11, spread: isLast ? 44 : 30, big: false))
        playSheen(duration: 1.05, peak: 0.62)
    }

    /// The last third rips (§5.6). Stone tears, a heavy thud, then the blade
    /// sings — and 520ms later the freed state takes over.
    private func breakFreeSequence() {
        spawn(StoneChip.burst(count: 30, spread: 84, big: true))
        ForgeAudio.shared.breakFree()
        ForgeHaptics.shared.breakFree()
        // A short, bright catch on the rip. It is timed to land just inside the
        // 520ms handoff so the long sweep below starts on a clean blade.
        playSheen(duration: 0.46, peak: 0.75)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            vm.breakFree()
            // The freed blade's one showpiece: a slow, wide diagonal travelling
            // top-left to bottom-right, arriving after the lift has begun.
            playSheen(duration: 1.7, peak: 0.9)
        }
    }

    private func playSheen(duration: Double, peak: Double) {
        guard !reduceMotion else { return }
        let run = SheenRun(
            start: Date.timeIntervalSinceReferenceDate,
            duration: duration,
            peak: peak
        )
        sheens.append(run)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            sheens.removeAll { $0.id == run.id }
        }
    }

    private func spawn(_ newChips: [StoneChip]) {
        guard !reduceMotion else { return }
        chips.append(contentsOf: newChips)
        let ids = Set(newChips.map(\.id))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            chips.removeAll { ids.contains($0.id) }
        }
    }
}
