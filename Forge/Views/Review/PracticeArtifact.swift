import SwiftUI

/// One image, worth showing somebody.
///
/// # Why this exists
///
/// Forge had nothing a person could ever show another human being. Every other
/// app in this category has a share sheet on everything, which is why they all
/// feel like they are using you — but the answer to that is not *nothing*, it is
/// **one artifact, at two moments that actually mean something, that the user
/// has to go and get.**
///
/// The two moments are a blade earned and a chapter closed. Both are rare, both
/// are real, and both are the only times somebody would want to say anything out
/// loud about a private practice.
///
/// # The rules
///
/// - **Never automatic.** Nothing is posted, nothing is offered unprompted, and
///   there is no "share your progress!" anywhere. The image is made when the
///   share button is pressed and not before.
/// - **No app furniture.** No logo lockup, no download badge, no watermark, no
///   "sent from". If somebody shares this it is because it is a good picture of
///   their own practice, and an advert stapled to it would make it a worse one
///   *and* stop them sharing it.
/// - **Nothing on it that is not theirs.** The blade, the count, the identity in
///   their own words, and the date. No streak — a streak on a shared image is a
///   number somebody has to defend next month.
/// - **Spelled, not scored.** `ForgeCount.spelled` for the same reason the rest
///   of the app uses it: "Two hundred days" is a fact about a person, "200" is a
///   scoreboard.
struct PracticeArtifact: View {

    /// What this image is about.
    enum Occasion: Equatable {
        /// A blade came out of the stone.
        case blade(name: String, asset: String, state: BladeState)
        /// Six weeks closed.
        case chapter(name: String)
    }

    let occasion: Occasion
    let daysKept: Int
    /// The user's own sentence, if they have written one. Nil is ordinary.
    let identity: String?
    let date: Date

    /// A square, because it is the one shape every surface accepts without
    /// re-cropping — a portrait card is cut in half by half the places somebody
    /// would put it.
    static let size = CGSize(width: 1080, height: 1080)

    var body: some View {
        ZStack {
            // The room, not a gradient off a brand palette. This is the same
            // near-black the app is drawn in, lit from the upper left like
            // every sprite in it.
            Rectangle()
                .fill(ForgeTheme.bg)

            RadialGradient(
                colors: [Color.white.opacity(0.14), .clear],
                center: UnitPoint(x: 0.2, y: 0.08),
                startRadius: 0,
                endRadius: 900
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                subject

                Spacer(minLength: 0)

                VStack(spacing: 22) {
                    Text(count)
                        .font(.system(size: 84, weight: .semibold))
                        .foregroundStyle(ForgeTheme.cream)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)

                    if let identity {
                        Text(identity)
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    Text(Self.dateFormat.string(from: date).uppercased())
                        .font(.system(size: 22, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.34))
                }
                .padding(.horizontal, 90)
                .padding(.bottom, 96)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var subject: some View {
        switch occasion {
        case let .blade(name, asset, state):
            VStack(spacing: 28) {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 470)
                    // The blade at the age the practice has made it, so a shared
                    // image of a four-hundred-day blade is not the same picture
                    // as a shared image of a sixty-day one. See `BladeState`.
                    .bladeState(state)

                Text(name.uppercased())
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 96)

        case let .chapter(name):
            VStack(spacing: 24) {
                Text("CHAPTER CLOSED")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.4))

                Text(name)
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(ForgeTheme.cream)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 150)
            .padding(.horizontal, 90)
        }
    }

    private var count: String {
        daysKept == 1 ? "One day kept" : "\(ForgeCount.spelled(daysKept)) days kept"
    }

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()
}

// MARK: - Making the file

extension PracticeArtifact {

    /// Render it, and hand back something `ShareLink` can carry.
    ///
    /// `ImageRenderer` on the main actor, at a fixed scale rather than the
    /// screen's: a share image should be the same picture from an iPhone SE and
    /// an iPad Pro, and letting the device decide would make one of them post a
    /// blurry one.
    ///
    /// Rendered when the screen that offers it appears, which is a blade
    /// celebration or a chapter close and therefore a handful of times a year —
    /// not on every launch, and never anywhere in the daily loop.
    @MainActor
    func rendered() -> Image? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}

/// A share button that renders on demand and quietly does nothing if it cannot.
///
/// Nothing about failing to render is worth telling somebody about — the image
/// is a nicety, and an error alert over a private practice would be the app
/// making its own problem into the user's.
struct ArtifactShareButton: View {
    let artifact: PracticeArtifact
    var title: String = "Save or share"

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    preview: SharePreview("Forge", image: image)
                ) {
                    label
                }
            } else {
                // Nothing at all rather than a disabled button. The render takes
                // a frame or two and a control that arrives greyed out and then
                // wakes up is worse than one that simply appears.
                Color.clear.frame(height: 44)
            }
        }
        .buttonStyle(.plain)
        // On appear, not on tap: the first press should open the share sheet
        // rather than start the work. This screen is seen a handful of times a
        // year, so the cost is nothing and it is never paid in the daily loop.
        .task { image = artifact.rendered() }
        .accessibilityLabel(title)
        .accessibilityHint("Makes an image of this you can save or send")
    }

    private var label: some View {
        Label(title, systemImage: "square.and.arrow.up")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}
