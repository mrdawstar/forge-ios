import SwiftUI

// MARK: - Why it works

/// Three findings and what Forge built on each, read in the time it takes to
/// look at them.
///
/// # What it replaced, and why
///
/// It was three cards of research prose — a title, a paragraph, the mechanic
/// and the full reference, a hundred-odd words before Continue — and it read as
/// homework. Every word was accurate and most of them went unread, which meant
/// the one thing the screen has to land didn't: *this is built on evidence*.
///
/// # How it is read now
///
/// In the order the eye goes, and each step is enough on its own:
///
/// 1. **A column of figures** — 66, 94, 138 — with what each counts under it.
///    Before a word is read, the screen is visibly about measured things.
/// 2. **The principle**, one plain line each: repetition makes a new habit
///    automatic; deciding when and where raises follow-through; recording
///    progress helps you reach goals.
/// 3. **What Forge does with it**, in cream after a turn arrow — Arcs, a day
///    and a time for every activity, the sword — so the claim ends in the
///    product rather than in a journal.
/// 4. **Who found it**, author and year, in the smallest type on the screen.
///
/// The fuller finding and the full reference are one tap further, under
/// **Sources**: supporting evidence for anybody who wants it, not the content
/// of the screen. No logos, no badges, no percentage the papers do not
/// contain; the claims are the papers' and the figures are the papers'
/// (`FirstRunCopy.findings`, held by `FirstRunTests`).
struct ScienceBeat: View {
    let onContinue: () -> Void

    @State private var scrollHeight: CGFloat = 0
    @State private var showsSources = false

    private static let sourcesID = "sources"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 6) {
                            Text(FirstRunCopy.scienceOverline.uppercased())
                                .font(ForgeTheme.overline)
                                .kerning(ForgeTheme.overlineKerning)
                                .foregroundStyle(ForgeTheme.cream.opacity(0.75))
                                .accessibilityHidden(true)
                            Text(FirstRunCopy.scienceTitle)
                                .font(.title.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)

                        VStack(spacing: 0) {
                            ForEach(Array(FirstRunCopy.findings.enumerated()), id: \.offset) { index, finding in
                                if index > 0 {
                                    Rectangle()
                                        .fill(ForgeTheme.cream.opacity(0.08))
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                                FindingRow(finding: finding)
                            }
                        }
                        .forgeCard(radius: ForgeTheme.Radius.card)

                        sourcesButton(reader)
                            .padding(.top, 12)

                        if showsSources {
                            sources
                                .id(Self.sourcesID)
                                .transition(.opacity)
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
            }

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

    /// Opening it brings it into view: it opens under the fold, and a
    /// disclosure that opens off-screen reads as one that did nothing. The
    /// scroll waits for the opening to finish — the content's height grows
    /// with the animation, and scrolled any earlier it stopped at the first
    /// lines.
    private func sourcesButton(_ reader: ScrollViewProxy) -> some View {
        Button {
            ForgeHaptics.shared.tap()
            withAnimation(.forgeRow) {
                showsSources.toggle()
            } completion: {
                guard showsSources else { return }
                withAnimation(.forgeRow) { reader.scrollTo(Self.sourcesID, anchor: .bottom) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(FirstRunCopy.sources)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showsSources ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(showsSources ? "Shown" : "Hidden"))
        .accessibilityHint(Text(showsSources ? "Hides the full references" : "Shows each finding in full, with its reference"))
    }

    /// Each finding in full, with the reference it can be looked up by.
    private var sources: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(FirstRunCopy.findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(finding.citation)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One finding: the figure on the left, and the principle, what Forge does
/// with it and who found it on the right. Stacked at the accessibility sizes,
/// where a column of figures would leave the words a sliver of the screen.
private struct FindingRow: View {
    let finding: FirstRunCopy.Finding

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))

        layout {
            VStack(alignment: .leading, spacing: 2) {
                // Proportional digits: nothing here counts, and tabular ones
                // set the 1 of 138 in from the column's edge.
                Text(finding.figure)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(finding.unit.uppercased())
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .foregroundStyle(ForgeTheme.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The figure is the anchor, not the reading: past the first
            // accessibility size it would crowd out the sentence it anchors.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(width: typeSize.isAccessibilitySize ? nil : 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(finding.principle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ForgeTheme.cream.opacity(0.6))
                    Text(finding.mechanic)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForgeTheme.cream)
                }

                Text(finding.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(finding.figure) \(finding.unit.lowercased()). \(finding.principle) \(finding.mechanic) \(finding.source)."
        ))
    }
}

// MARK: - Your plan

/// The week being proposed: one activity for each part somebody is building,
/// each on its own days and at its own time — "Mon · Wed · Fri · 18:00",
/// "Daily · 21:30" — so the cadence reads at a glance.
///
/// **Every row is one tap from changing.** A tap opens the row's own editor —
/// its days (the app's own repeat picker), its time, and the other starters in
/// the same dimension to swap it for — so nothing about the plan has to be
/// accepted as given, and nothing on it is written until Continue. Continue
/// writes the real day (`ForgeViewModel.adoptPlan`): the activities, their
/// days, their hours.
///
/// **Something has to be on today.** The two beats after this one — do one
/// now, and the first pull — are today's, and a day with nothing on it can be
/// neither. Every proposal has something every day (`OnboardingPlan.cadences`),
/// so this only ever matters after an edit, and then Continue waits for one
/// row to include today rather than letting the first pull land on an empty
/// day.
struct PlanBeat: View {
    @Binding var entries: [PlanEntry]
    /// The Arc the plan starts with (DIRECTION_1_1 §5). Lock In 7 — the
    /// default — is the plan as it is; any other brings its own rows.
    @Binding var arc: ArcID
    /// The rows an Arc other than Lock In 7 brings. Read-only here: they are
    /// the Arc's, and they are the week's to change once it has begun.
    let arcRows: [ArcJoin.Addition]
    /// Today's weekday, `Calendar` numbering, from the civil day.
    let today: Int
    /// The civil day, for whether it is the winter.
    let day: ForgeDay
    let onContinue: () -> Void

    @State private var editing: PlanEntry?
    @State private var scrollHeight: CGFloat = 0

    private var isPlanAsItIs: Bool { arc == .lockIn }

    private var hasToday: Bool {
        isPlanAsItIs
            ? entries.contains { $0.happens(on: today) }
            : arcRows.contains { RitualRepeat(weekdays: $0.weekdays).includes(today) }
    }

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
                        Text(isPlanAsItIs ? FirstRunCopy.planSubtitle : FirstRunCopy.arcPlanSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)

                    // The Arc, above the list it decides. Lock In 7 first and
                    // chosen; Winter Arc lit through the winter. An Arc shows
                    // what it adds before it adds it (§5 #7 and #9): the rows
                    // below are exactly what Continue writes.
                    ArcPicker(selection: $arc, day: day)
                        .padding(.bottom, 16)

                    VStack(spacing: 8) {
                        if isPlanAsItIs {
                            ForEach(entries) { entry in
                                if let ritual = entry.ritual {
                                    PlanRow(ritual: ritual, entry: entry) {
                                        ForgeHaptics.shared.tap()
                                        editing = entry
                                    }
                                }
                            }
                        } else {
                            ForEach(arcRows) { ArcPlanRow(addition: $0) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .animation(.forgeRow, value: arc)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: scrollHeight)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

            if !hasToday {
                Text(FirstRunCopy.planNothingToday)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            ForgeButton(title: "Continue") {
                ForgeHaptics.shared.tap()
                onContinue()
            }
            .disabled(!hasToday)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .padding(.bottom, 20)
        .animation(.forgeFade, value: hasToday)
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

// MARK: - Start with an Arc

/// The four Arcs as a row of small covers, one chosen. Lock In 7 comes first
/// and is chosen when the beat opens — it is the plan as it is, for seven days,
/// with the daily challenge — and Winter Arc is lit, and said to start today,
/// from the first of October to the end of January.
private struct ArcPicker: View {
    @Binding var selection: ArcID
    let day: ForgeDay

    private var programs: [ArcProgram] {
        // The starter first, then the winter while it is the winter.
        let order: [ArcID] = ArcCatalog.isWinterSeason(day)
            ? [.lockIn, .winter, .monk, .discipline]
            : [.lockIn, .monk, .discipline, .winter]
        return order.map(ArcCatalog.program)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FirstRunCopy.arcPickerTitle)
                .font(.headline)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(programs) { program in
                        chip(program)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            Text(ArcCatalog.program(selection).summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .contentTransition(.opacity)
                .animation(.forgeFade, value: selection)
        }
    }

    private func chip(_ program: ArcProgram) -> some View {
        let chosen = selection == program.id
        let inSeason = program.isSeasonal && ArcCatalog.isWinterSeason(day)
        return Button {
            ForgeHaptics.shared.tap()
            withAnimation(.forgeSelection) { selection = program.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArcCover(program: program, showsName: false, height: 72)
                    .frame(width: 112)
                Text(program.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(inSeason ? "STARTS TODAY" : program.lengthLabel.uppercased())
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .foregroundStyle(inSeason ? AnyShapeStyle(ForgeTheme.accent) : AnyShapeStyle(.secondary))
            }
            .padding(8)
            .frame(width: 128, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .fill(chosen ? ForgeTheme.accent.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        chosen ? ForgeTheme.accent : (inSeason ? ForgeTheme.accent.opacity(0.4) : Color.white.opacity(0.08)),
                        lineWidth: chosen ? 1.5 : 1
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(program.name), \(program.lengthLabel)\(inSeason ? ", starts today" : "")"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// One of an Arc's activities on the first run's plan: what it is and when.
/// Read-only — the Arc's own, until the week makes it somebody's.
private struct ArcPlanRow: View {
    let addition: ArcJoin.Addition

    private var dimension: RitualCategory {
        Ritual.find(addition.id)?.category ?? .discipline
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: addition.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ForgeTheme.cream.opacity(0.9))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(addition.name)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(addition.schedule)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ForgeTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: dimension.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dimension.color)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .glassEffect(.regular, in: .rect(cornerRadius: ForgeTheme.Radius.control))
        .accessibilityElement(children: .combine)
    }
}

/// One activity on the plan: what it is, when — its days and its time, on one
/// line — its standard, and which part of somebody it builds, in that part's
/// colour.
private struct PlanRow: View {
    let ritual: Ritual
    let entry: PlanEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RitualGlyph(ritual: ritual, size: 20)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ritual.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    // The line the row is for: when. In cream, the colour the
                    // first run gives what Forge does rather than what it says.
                    Text(entry.schedule)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ForgeTheme.cream)
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

                Image(systemName: entry.dimension.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.dimension.color)
                    .accessibilityHidden(true)
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
            "\(ritual.label). \(entry.repeats.spokenLabel), \(ClockMinute.label(entry.minute)). Builds \(entry.dimension.label.lowercased())."
        ))
        .accessibilityHint(Text("Double tap to change its days or time, or swap it"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One row's editor: its days, its time, and what else in the same dimension
/// it could be. Applies on Done; Cancel leaves the row as it was.
///
/// The days are the app's own `RepeatPicker` — the screen every activity's
/// repeat is set on afterwards — so the plan's days are chosen with the same
/// control that will change them later, and written as the same
/// `RitualRepeat`.
private struct PlanEntryEditor: View {
    let entry: PlanEntry
    /// Activities already on other rows, which a swap may not duplicate.
    let taken: Set<String>
    let onDone: (PlanEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanEntry
    @State private var time: Date
    /// Whether the days were changed in this editor. Until they are, a swap
    /// brings the new activity's own days with it — "Work out" arrives on
    /// Monday, Wednesday and Friday, not on the days "Walk outside" had.
    @State private var daysChanged = false

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

    private var days: Binding<RitualRepeat> {
        Binding(
            get: { draft.repeats },
            set: { repeats in
                draft.repeats = repeats
                daysChanged = true
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RepeatPicker(selection: days)
                    } label: {
                        LabeledContent("Repeat") {
                            Text(draft.repeats.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Repeat")
                    .accessibilityValue(draft.repeats.spokenLabel)
                } header: {
                    Text("Days")
                }

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
                            if !daysChanged { draft.repeats = OnboardingPlan.cadence(for: ritual.id) }
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
