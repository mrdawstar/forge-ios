import SwiftUI
import UniformTypeIdentifiers

/// The Proof Card: one image, worth showing somebody.
///
/// # Why this exists
///
/// Forge had nothing a person could ever show another human being. Every other
/// app in this category has a share sheet on everything, which is why they all
/// feel like they are using you — but the answer to that is not *nothing*, it is
/// **one artifact, at two moments that actually mean something, that the user
/// has to go and get.**
///
/// # Exactly four doors
///
/// **A blade earned** (`SwordUnlockOverlay`, once its celebration has staged
/// its actions), **a chapter closed** (`ChapterCloseView`, once "Close this
/// chapter" has been pressed) and, since 1.1, **the running Arc's card** on
/// the Arcs tab (DIRECTION_1_1 §5) and **Share your stats** on the Becoming
/// tab. Each carries one quiet action, and nothing else in the app offers to
/// share anything: no prompt at launch, no reminder, no notification, nothing
/// in the daily loop, and the share sheet only ever opens because somebody
/// pressed the button. `FirstWeekTests.proofCardDoors` reads the source and
/// fails if a fifth door appears.
///
/// # What is on it
///
/// The sword in the stone, the days kept **in words**, the date, and
/// `forgebetter.app` — small, at the foot, the one line of address a stranger
/// would need to find what they are looking at. No congratulation, no streak (a
/// streak on a shared image is a number somebody has to defend next month), no
/// achievement, no handle, no marketing line. Nothing the person wrote.
///
/// # The Arc's card, and the stats card
///
/// The two cards with numbers on them. The Arc's: "Winter Arc · Day 30 of
/// 90", the blade, the hexagon with its six numbers and OVR, the date and the
/// address. The stats card (Becoming's *Share your stats*): the blade and the
/// days kept, the Arc's day when one is running, the same hexagon. They are
/// the only ones where a number is the point — an Arc is a count of days, and
/// the six are what the days did — so they are digits, as everywhere they are
/// a score (DIRECTION_1_1 §3). Still nothing written by the person, no streak
/// and no congratulation.
///
/// # Temper marks
///
/// Past Enduring, every card carries the blade's temper marks
/// (`Ladder.temperMarks`): under the days on the blade card, under the blade
/// on the other two. Drawn only when there are any, so nothing about a card
/// changes for anybody short of two hundred and seventy days.
///
/// # Two formats
///
/// 1080 × 1920 for a story, 1080 × 1080 for everywhere else. Rendered when the
/// share sheet asks for the file, not before — see `ProofCardFile`.
struct PracticeArtifact: View {

    /// What this image marks. A quiet line under the count, never a headline.
    enum Occasion: Equatable, Sendable {
        /// A blade came out of the stone.
        case blade(name: String)
        /// A chapter closed.
        case chapter
        /// Where somebody is in an Arc.
        case arc(ArcProof)
        /// The six, as Becoming shows them.
        case stats(StatsProof)

        var line: String {
            switch self {
            case .blade(let name): name.uppercased()
            case .chapter: "CHAPTER CLOSED"
            case .arc(let proof): proof.title.uppercased()
            case .stats(let proof): proof.title.uppercased()
            }
        }
    }

    /// The two shapes the card is made in.
    enum Format: String, CaseIterable, Identifiable, Sendable {
        /// 1080 × 1920 — a story, a phone's own screen.
        case portrait
        /// 1080 × 1080 — every other surface, without re-cropping.
        case square

        var id: String { rawValue }

        var size: CGSize {
            switch self {
            case .portrait: CGSize(width: 1080, height: 1920)
            case .square: CGSize(width: 1080, height: 1080)
            }
        }

        var label: String {
            switch self {
            case .portrait: "Portrait · 1080 × 1920"
            case .square: "Square · 1080 × 1080"
            }
        }
    }

    let occasion: Occasion
    let daysKept: Int
    let date: Date
    var format: Format = .square

    /// The one address on the card.
    static let site = "forgebetter.app"

    var body: some View {
        switch occasion {
        case .arc(let proof):
            ArcProofCard(proof: proof, date: date, format: format)
        case .stats(let proof):
            StatsProofCard(proof: proof, date: date, format: format)
        case .blade, .chapter:
            bladeCard
        }
    }

    private var bladeCard: some View {
        let size = format.size
        return ZStack {
            // The room, not a gradient off a brand palette: the near-black the
            // app is drawn in.
            Rectangle().fill(ForgeTheme.bg)

            VStack(spacing: 0) {
                // The sword in the stone, faded into the black at its foot.
                // (The paywall draws `hero-plate` since 1.1, which is the same
                // art with its empty space made true black.)
                Image("hero")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height * (format == .portrait ? 0.62 : 0.56))
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.7),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                Spacer(minLength: 0)

                VStack(spacing: 22) {
                    Text(Self.dayWords(daysKept))
                        .font(.system(size: 84, weight: .semibold))
                        .foregroundStyle(ForgeTheme.cream)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)

                    TemperMarks(count: Ladder.temperMarks(daysKept: daysKept), tick: 26)

                    Text(occasion.line)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.45))

                    Text(Self.dateFormat.string(from: date).uppercased())
                        .font(.system(size: 22, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.34))
                }
                .padding(.horizontal, 90)

                Spacer(minLength: 0)

                Text(Self.site)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.bottom, format == .portrait ? 120 : 60)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
    }

    /// "No days kept", "One day kept", "Forty-two days kept". Spelled, like
    /// every count Forge says out loud, and never "one days".
    static func dayWords(_ count: Int) -> String {
        switch count {
        case ..<1: "No days kept"
        case 1: "One day kept"
        default: "\(ForgeCount.spelled(count)) days kept"
        }
    }

    static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()
}

// MARK: - The Arc's card

/// What the Arc's card is made of, taken once when the button is drawn.
///
/// Values, not stores: the card is rendered off the main loop's state at the
/// moment the share sheet asks, and it must be the numbers that were on
/// screen when the button was pressed.
struct ArcProof: Equatable, Sendable {
    /// "Winter Arc · Day 30 of 90".
    let title: String
    /// The six, in `RitualCategory.dimensions` order; nil draws a dash.
    let scores: [Int?]
    let overall: Int
    /// The equipped blade's sprite.
    let blade: String
    /// Winters finished, engraved on the blade.
    let winters: Int
    /// Temper marks on the blade (`Ladder.temperMarks`).
    var temperMarks: Int = 0
}

/// What the stats card is made of: Becoming's *Share your stats*, taken once
/// when the button is drawn, for the reason `ArcProof` is.
struct StatsProof: Equatable, Sendable {
    /// "Quenched · 23 days" — the blade carried and the days kept.
    let title: String
    /// "Winter Arc · Day 43 of 90", while an Arc runs.
    let arcLine: String?
    /// The six, in `RitualCategory.dimensions` order; nil draws a dash.
    let scores: [Int?]
    let overall: Int
    /// The word under OVR: Rising, Steady, Slipping, Early.
    let state: String
    /// The equipped blade's sprite.
    let blade: String
    let winters: Int
    let temperMarks: Int
}

/// "Winter Arc · Day 30 of 90", the blade, the six and OVR, the date, the
/// address. Drawn on the room, like every other card.
struct ArcProofCard: View {
    let proof: ArcProof
    let date: Date
    let format: PracticeArtifact.Format

    private var isPortrait: Bool { format == .portrait }

    var body: some View {
        let size = format.size
        let bladeWidth: CGFloat = isPortrait ? 150 : 104
        let spriteHeight = bladeWidth * 1771.0 / 483.0
        let bladeHeight: CGFloat = isPortrait ? 560 : 400
        let hexagon: CGFloat = isPortrait ? 600 : 470

        return ZStack {
            Rectangle().fill(ForgeTheme.bg)
            RadialGradient(
                colors: [ForgeTheme.cream.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: size.height * 0.6
            )

            VStack(spacing: 0) {
                Text(proof.title.uppercased())
                    .font(.system(size: isPortrait ? 40 : 34, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(ForgeTheme.cream)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, isPortrait ? 150 : 70)
                    .padding(.horizontal, 60)

                if isPortrait {
                    sword(width: bladeWidth, height: bladeHeight, spriteHeight: spriteHeight)
                        .padding(.top, 60)
                    TemperMarks(count: proof.temperMarks, tick: 22)
                        .padding(.top, 14)
                    six(side: hexagon)
                        .padding(.top, 10)
                } else {
                    // Centred between the title and the date: pinned under
                    // the title it left a third of the square empty.
                    Spacer(minLength: 0)
                    HStack(spacing: 30) {
                        VStack(spacing: 12) {
                            sword(width: bladeWidth, height: bladeHeight, spriteHeight: spriteHeight)
                            TemperMarks(count: proof.temperMarks, tick: 18)
                        }
                        six(side: hexagon)
                    }
                }

                Spacer(minLength: 0)

                Text(PracticeArtifact.dateFormat.string(from: date).uppercased())
                    .font(.system(size: 22, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.bottom, 16)

                Text(PracticeArtifact.site)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.bottom, isPortrait ? 120 : 56)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
    }

    private func sword(width: CGFloat, height: CGFloat, spriteHeight: CGFloat) -> some View {
        ProofBlade(asset: proof.blade, winters: proof.winters,
                   width: width, height: height, spriteHeight: spriteHeight)
    }

    private func six(side: CGFloat) -> some View {
        ProofHexagon(scores: proof.scores, overall: proof.overall, side: side)
    }
}

// MARK: - The stats card

/// "Quenched · 23 days", the Arc's day while one runs, the blade with its
/// marks, the hexagon with the six numbers and OVR, the date, the address. The
/// Arc's card with the person's own line on top instead of the Arc's.
struct StatsProofCard: View {
    let proof: StatsProof
    let date: Date
    let format: PracticeArtifact.Format

    private var isPortrait: Bool { format == .portrait }

    var body: some View {
        let size = format.size
        let bladeWidth: CGFloat = isPortrait ? 150 : 104
        let spriteHeight = bladeWidth * 1771.0 / 483.0
        let bladeHeight: CGFloat = isPortrait ? 540 : 380
        let hexagon: CGFloat = isPortrait ? 600 : 470

        return ZStack {
            Rectangle().fill(ForgeTheme.bg)
            RadialGradient(
                colors: [ForgeTheme.cream.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: size.height * 0.6
            )

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Text(proof.title.uppercased())
                        .font(.system(size: isPortrait ? 40 : 34, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(ForgeTheme.cream)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let arcLine = proof.arcLine {
                        Text(arcLine.uppercased())
                            .font(.system(size: isPortrait ? 24 : 21, weight: .semibold))
                            .tracking(4)
                            .foregroundStyle(.white.opacity(0.5))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                .padding(.top, isPortrait ? 150 : 64)
                .padding(.horizontal, 60)

                if isPortrait {
                    ProofBlade(asset: proof.blade, winters: proof.winters,
                               width: bladeWidth, height: bladeHeight, spriteHeight: spriteHeight)
                        .padding(.top, 50)
                    // Air under the marks, when there are any: the hexagon's
                    // top label sits on its frame's edge, and 10 points under
                    // three notches it read as part of them.
                    TemperMarks(count: proof.temperMarks, tick: 22)
                        .padding(.top, 14)
                        .padding(.bottom, proof.temperMarks > 0 ? 30 : 0)
                    ProofHexagon(scores: proof.scores, overall: proof.overall, state: proof.state, side: hexagon)
                        .padding(.top, 10)
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: 30) {
                        VStack(spacing: 12) {
                            ProofBlade(asset: proof.blade, winters: proof.winters,
                                       width: bladeWidth, height: bladeHeight, spriteHeight: spriteHeight)
                            TemperMarks(count: proof.temperMarks, tick: 18)
                        }
                        ProofHexagon(scores: proof.scores, overall: proof.overall, state: proof.state, side: hexagon)
                    }
                }

                Spacer(minLength: 0)

                Text(PracticeArtifact.dateFormat.string(from: date).uppercased())
                    .font(.system(size: 22, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.bottom, 16)

                Text(PracticeArtifact.site)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.bottom, isPortrait ? 120 : 56)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared by the two cards with numbers on them

/// The blade, top-anchored and faded into the room, with its winters cut in.
private struct ProofBlade: View {
    let asset: String
    let winters: Int
    let width: CGFloat
    let height: CGFloat
    let spriteHeight: CGFloat

    var body: some View {
        Image(asset)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: spriteHeight)
            .winterEngraving(winters, width: width, spriteHeight: spriteHeight)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(
                    stops: SwordArt.fadeStops(solid: 0.62),
                    startPoint: .top, endPoint: .bottom
                )
            )
    }
}

/// The hexagon in the six colours, OVR in its middle, and each side's number
/// beside its vertex.
private struct ProofHexagon: View {
    let scores: [Int?]
    let overall: Int
    /// The word under OVR, or nil for the bare label.
    var state: String? = nil
    let side: CGFloat

    var body: some View {
        let values = scores.map { Double($0 ?? 0) / 100 }
        return ZStack {
            StatHexagon(values: values, showsGlyphs: false, animation: nil) {
                VStack(spacing: 2) {
                    Text("\(overall)")
                        .font(.system(size: side * 0.12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(state.map { "OVR \u{00B7} \($0.uppercased())" } ?? "OVR")
                        .font(.system(size: side * 0.032, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(ForgeTheme.cream.opacity(0.75))
                }
                // The same pool of dark `OverallCore` sits on in the app: the
                // polygon runs through the middle, and without it its edges
                // crossed the number on the saved card.
                .background {
                    Circle()
                        .fill(ForgeTheme.bg.opacity(0.72))
                        .frame(width: side * 0.29, height: side * 0.29)
                        .blur(radius: side * 0.036)
                }
            }
            .frame(width: side * 0.6, height: side * 0.6)

            ForEach(Array(RitualCategory.dimensions.enumerated()), id: \.element) { index, dimension in
                let score = scores.indices.contains(index) ? scores[index] : nil
                VStack(spacing: 2) {
                    Text(score.map(String.init) ?? "\u{2014}")
                        .font(.system(size: side * 0.06, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(dimension.color)
                    // The six colours wherever the six are (DIRECTION_1_1
                    // §4): the name in its colour, a step under its number.
                    Text(dimension.label.uppercased())
                        .font(.system(size: side * 0.026, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(dimension.color.opacity(0.7))
                }
                .position(
                    HexagonGeometry.point(
                        // Outside the outline, so the widest label —
                        // RELATIONSHIP — clears the vertex beside it.
                        index, radius: side * 0.45,
                        centre: CGPoint(x: side / 2, y: side / 2)
                    )
                )
            }
        }
        .frame(width: side, height: side)
    }
}

// MARK: - The file

/// The card as something `ShareLink` can carry, rendered only when the share
/// sheet asks for it — so pressing *Save the proof* costs nothing until the
/// person picks where it goes, and nothing is ever rendered in the daily loop.
///
/// `ImageRenderer` on the main actor, at a fixed scale of one: a share image
/// should be the same 1080-wide picture from every phone.
struct ProofCardFile: Transferable, Sendable {
    let occasion: PracticeArtifact.Occasion
    let daysKept: Int
    let date: Date
    let format: PracticeArtifact.Format

    enum RenderError: Error { case failed }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            try await file.png()
        }
        .suggestedFileName("Forge proof.png")
    }

    @MainActor
    func png() throws -> Data {
        let renderer = ImageRenderer(
            content: PracticeArtifact(occasion: occasion, daysKept: daysKept, date: date, format: format)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { throw RenderError.failed }
        return data
    }
}

// MARK: - The button

/// *Save the proof*: a quiet third action, offering the two formats.
///
/// Used in exactly three places — see `PracticeArtifact`. It never opens
/// itself; the share sheet appears only after somebody picks a format.
struct ProofCardButton: View {
    let occasion: PracticeArtifact.Occasion
    let daysKept: Int
    var date: Date = .now
    /// "Save the proof" at three doors; Becoming's says what it is, "Share
    /// your stats".
    var title: String = Self.title

    static let title = "Save the proof"

    /// What the share sheet calls the file: the Arc's or the stats card's own
    /// title, the days kept on the other two.
    private var previewTitle: String {
        switch occasion {
        case .arc(let proof): proof.title
        case .stats(let proof): proof.title
        case .blade, .chapter: PracticeArtifact.dayWords(daysKept)
        }
    }

    var body: some View {
        Menu {
            ForEach(PracticeArtifact.Format.allCases) { format in
                ShareLink(
                    item: ProofCardFile(occasion: occasion, daysKept: daysKept, date: date, format: format),
                    preview: SharePreview(previewTitle, image: Image("hero"))
                ) {
                    Text(format.label)
                }
            }
        } label: {
            Label(title, systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Makes an image of this you can save or send")
    }
}
