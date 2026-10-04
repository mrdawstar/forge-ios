import SwiftUI

/// What Forge would read from Apple Health, before iOS asks whether it may.
///
/// Raised in context and only then (FORGE_CONTEXT §8, DIRECTION_1_1 §8): the
/// first time an activity Health can check enters the day after the first run,
/// or the first tap on one. Never at launch and never during the first run.
///
/// **It lists exactly what is read and why**: the four types `HealthBridge`
/// asks for, each with what is taken from it and the activities it checks,
/// read from the library through the person's own edits. No row for anything
/// Forge does not read, and nothing about writing, because Forge writes nothing.
///
/// Answered once. It cannot be swiped away: "Keep it Your Word" is a real
/// answer and it is final; Settings is the only door back, and it is the
/// person's to open.
struct HealthPrimerView: View {
    /// The activities each metric checks, by name, as the person sees them.
    var activities: (ActivityMetric) -> [String]
    /// Continue (true) or Keep it Your Word (false). The sheet closes after.
    var onAnswer: (Bool) async -> Void

    @State private var isAsking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 34, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.top, 34)

                Text("Apple Health can tick these off.")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    // The screen's heading, found by VoiceOver's rotor like
                    // every other screen's (§17.7).
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)
                    .padding(.horizontal, 24)

                Text("Forge reads four things, on this iPhone. It never writes to Health, and nothing it reads leaves the phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    ForEach(ActivityMetric.allCases, id: \.self) { metric in
                        ReadRow(metric: metric, activities: activities(metric))
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)

                Text("When a number reaches its target, the activity ticks itself off. You can undo it, and you can always say you did it yourself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                    .padding(.horizontal, 32)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { buttons }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ForgeTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .interactiveDismissDisabled()
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            Button {
                answer(true)
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.cream)
            .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
            .disabled(isAsking)
            .padding(.horizontal, 24)

            // A no is a real answer and is taken as one. Nothing asks again.
            Button("Keep it Your Word") { answer(false) }
                .font(.footnote.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isAsking)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(ForgeTheme.bg)
    }

    private func answer(_ allow: Bool) {
        guard !isAsking else { return }
        isAsking = true
        ForgeHaptics.shared.tap()
        Task { @MainActor in
            await onAnswer(allow)
            dismiss()
        }
    }
}

/// One type Forge reads: its name, what is taken from it, and what it checks.
private struct ReadRow: View {
    let metric: ActivityMetric
    let activities: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: metric.healthSymbol)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.healthName)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard !activities.isEmpty else { return metric.healthUse }
        return "\(metric.healthUse) For \(Self.joined(activities))."
    }

    /// "A", "A and B", "A, B and C". The interface is English whatever the
    /// phone's region, so this is not left to the locale's list format.
    static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
}
