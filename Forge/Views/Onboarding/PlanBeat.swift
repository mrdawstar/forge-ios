import SwiftUI

// MARK: - Why it works

/// Three findings, each ending on the part of Forge it explains, each with its
/// citation in small type under it.
///
/// Text only: no logos, no journal badges, no percentages the papers do not
/// contain. The claim is small on purpose — "in one study", "across
/// ninety-four studies" — because a first run that overstates the science is
/// the one screen somebody who knows it will remember. The words are in
/// `FirstRunCopy.findings`, where a test holds that only the papers
/// DIRECTION_1_1 lists are cited.
struct ScienceBeat: View {
    let onContinue: () -> Void

    @State private var scrollHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)

                    Text(FirstRunCopy.scienceTitle)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 4)

                    ForEach(Array(FirstRunCopy.findings.enumerated()), id: \.offset) { _, finding in
                        FindingCard(finding: finding)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: scrollHeight)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

            ForgeButton(title: "Continue") {
                ForgeHaptics.shared.tap()
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .padding(.bottom, 20)
    }
}

private struct FindingCard: View {
    let finding: FirstRunCopy.Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(finding.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(finding.mechanic)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgeTheme.cream)
                .fixedSize(horizontal: false, vertical: true)

            Text(finding.citation)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeCard(radius: ForgeTheme.Radius.card)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Your plan

/// The day being proposed: one activity for each part somebody is building,
/// each with a time, every day.
///
/// **Every row is one tap from changing.** A tap opens the row's own editor —
/// the time, and the other starters in the same dimension to swap it for — so
/// nothing about the plan has to be accepted as given, and nothing on it is
/// written until Continue. Continue writes the real day
/// (`ForgeViewModel.adoptPlan`): the activities, their hours, every day.
///
/// The line under the title says "every day" because that is what Continue
/// writes, and the screen before this one projected exactly that plan kept
/// five days a week.
struct PlanBeat: View {
    @Binding var entries: [PlanEntry]
    let onContinue: () -> Void

    @State private var editing: PlanEntry?
    @State private var scrollHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // The heading and the rows scroll together and sit centred when
            // there are only three: a short plan pinned to the top of the
            // screen read as a list waiting to be filled.
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Text(FirstRunCopy.planTitle)
                            .font(.title.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(FirstRunCopy.planSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)

                    // ARC-PICKER (session S3): the Arc choice (Lock In 7 first)
                    // goes here, above the list it appends to — DIRECTION_1_1
                    // §5. An Arc shows what it adds before it adds it (§5 #7
                    // and #9).

                    VStack(spacing: 8) {
                        ForEach(entries) { entry in
                            if let ritual = entry.ritual {
                                PlanRow(ritual: ritual, entry: entry) {
                                    ForgeHaptics.shared.tap()
                                    editing = entry
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: scrollHeight)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

            ForgeButton(title: "Continue") {
                ForgeHaptics.shared.tap()
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .padding(.bottom, 20)
        .sheet(item: $editing) { entry in
            PlanEntryEditor(
                entry: entry,
                taken: Set(entries.filter { $0.dimension != entry.dimension }.map(\.ritualID))
            ) { changed in
                apply(changed)
            }
        }
    }

    /// A row changed in its editor. Re-sorted by time, so the plan always
    /// reads as a day, earliest first.
    private func apply(_ changed: PlanEntry) {
        guard let index = entries.firstIndex(where: { $0.dimension == changed.dimension }) else { return }
        withAnimation(.forgeRow) {
            entries[index] = changed
            entries.sort { $0.minute < $1.minute }
        }
    }
}

/// One activity on the plan: what it is, its standard, its time, and which
/// part of somebody it builds, in that part's colour.
private struct PlanRow: View {
    let ritual: Ritual
    let entry: PlanEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RitualGlyph(ritual: ritual, size: 20)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ritual.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !ritual.sub.isEmpty {
                        Text(ritual.sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ClockMinute.label(entry.minute))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: entry.dimension.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(entry.dimension.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: ForgeTheme.Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(ritual.label), \(ClockMinute.label(entry.minute)). Builds \(entry.dimension.label.lowercased())."
        ))
        .accessibilityHint(Text("Double tap to change the time or swap it"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One row's editor: its time, and what else in the same dimension it could
/// be. Applies on Done; Cancel leaves the row as it was.
private struct PlanEntryEditor: View {
    let entry: PlanEntry
    /// Activities already on other rows, which a swap may not duplicate.
    let taken: Set<String>
    let onDone: (PlanEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanEntry
    @State private var time: Date

    init(entry: PlanEntry, taken: Set<String>, onDone: @escaping (PlanEntry) -> Void) {
        self.entry = entry
        self.taken = taken
        self.onDone = onDone
        _draft = State(initialValue: entry)
        _time = State(initialValue: Self.date(for: entry.minute))
    }

    private var alternatives: [Ritual] {
        OnboardingPlan.alternatives(for: entry.dimension).filter { !taken.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("Time")
                }

                Section {
                    ForEach(alternatives) { ritual in
                        Button {
                            ForgeHaptics.shared.detent()
                            draft.ritualID = ritual.id
                        } label: {
                            HStack(spacing: 12) {
                                RitualGlyph(ritual: ritual, size: 16, color: .secondary)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ritual.label)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if !ritual.sub.isEmpty {
                                        Text(ritual.sub)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if draft.ritualID == ritual.id {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(ForgeTheme.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.ritualID == ritual.id ? [.isButton, .isSelected] : .isButton)
                    }
                } header: {
                    Text("Swap for")
                } footer: {
                    Text("Everything here builds \(entry.dimension.label.lowercased()).")
                }
            }
            .navigationTitle(entry.dimension.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var changed = draft
                        changed.minute = Self.minute(of: time)
                        onDone(changed)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
    }

    private static func date(for minute: Int) -> Date {
        var parts = DateComponents()
        parts.hour = minute / 60
        parts.minute = minute % 60
        return Calendar.current.date(from: parts) ?? .now
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
