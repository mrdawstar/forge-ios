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
/// # Exactly three doors
///
/// **A blade earned** (`SwordUnlockOverlay`, once its celebration has staged
/// its actions), **a chapter closed** (`ChapterCloseView`, once "Close this
/// chapter" has been pressed) and, since 1.1, **the running Arc's card** on
/// the Arcs tab (DIRECTION_1_1 §5). Each carries one quiet action, *Save the
/// proof*, and nothing else in the app offers to share anything: no prompt at
/// launch, no reminder, no notification, nothing in the daily loop, and the
/// share sheet only ever opens because somebody pressed the button.
/// `FirstWeekTests.proofCardDoors` reads the source and fails if a fourth door
/// appears.
///
/// # What is on it
///
/// The sword in the stone, the days kept **in words**, the date, and
/// `forgebetter.app` — small, at the foot, the one line of address a stranger
/// would need to find what they are looking at. No congratulation, no streak (a
/// streak on a shared image is a number somebody has to defend next month), no
/// achievement, no handle, no marketing line. Nothing the person wrote.
///
/// # The Arc's card
///
/// The one card with numbers on it: "Winter Arc · Day 30 of 90", the blade,
/// the hexagon with its six numbers and OVR, the date and the address. It is
/// the only one where a number is the point — an Arc is a count of days, and
/// the six are what the days did — so they are digits, as everywhere they are
/// a score (DIRECTION_1_1 §3). Still nothing written by the person, no streak
/// and no congratulation.
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

        var line: String {
            switch self {
            case .blade(let name): name.uppercased()
            case .chapter: "CHAPTER CLOSED"
            case .arc(let proof): proof.title.uppercased()
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
        if case .arc(let proof) = occasion {
            ArcProofCard(proof: proof, date: date, format: format)
        } else {
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
                    six(side: hexagon)
                        .padding(.top, 10)
                } else {
                    HStack(spacing: 30) {
                        sword(width: bladeWidth, height: bladeHeight, spriteHeight: spriteHeight)
                        six(side: hexagon)
                    }
                    .padding(.top, 40)
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
        Image(proof.blade)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: spriteHeight)
            .winterEngraving(proof.winters, width: width, spriteHeight: spriteHeight)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(
                    stops: SwordArt.fadeStops(solid: 0.62),
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    /// The hexagon in the six colours, OVR in its middle, and each side's
    /// number beside its vertex.
    private func six(side: CGFloat) -> some View {
        let values = proof.scores.map { Double($0 ?? 0) / 100 }
        return ZStack {
            StatHexagon(values: values, showsGlyphs: false, animation: nil) {
                VStack(spacing: 2) {
                    Text("\(proof.overall)")
                        .font(.system(size: side * 0.15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("OVR")
                        .font(.system(size: side * 0.035, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(ForgeTheme.cream.opacity(0.75))
                }
            }
            .frame(width: side * 0.66, height: side * 0.66)

            ForEach(Array(RitualCategory.dimensions.enumerated()), id: \.element) { index, dimension in
                let score = proof.scores.indices.contains(index) ? proof.scores[index] : nil
                VStack(spacing: 2) {
                    Text(score.map(String.init) ?? "\u{2014}")
                        .font(.system(size: side * 0.06, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(dimension.color)
                    Text(dimension.label.uppercased())
                        .font(.system(size: side * 0.026, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .position(
                    HexagonGeometry.point(
                        index, radius: side * 0.43,
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

    static let title = "Save the proof"

    /// What the share sheet calls the file: the Arc's title on the Arc's
    /// card, the days kept on the other two.
    private var previewTitle: String {
        if case .arc(let proof) = occasion { return proof.title }
        return PracticeArtifact.dayWords(daysKept)
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
            Label(Self.title, systemImage: "square.and.arrow.down")
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
