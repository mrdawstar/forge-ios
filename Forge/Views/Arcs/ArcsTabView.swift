import SwiftUI

/// The Arcs: the one being lived in, the ones that can be started, and the
/// ones finished.
///
/// In that order, which is the order of what somebody opens this tab to do —
/// see where they are, pick the next, look back. The running Arc's card is
/// the only thing here that changes anything, and it changes the week only on
/// an explicit tap: a phase's changes are listed first and applied by one
/// button (§5 #9).
///
/// **Arcs are the practice, and the practice is Forge Pro** (DIRECTION_1_1
/// §1): somebody without it meets the one locked state where the running Arc
/// and the start buttons would be. What they have finished is the record, and
/// the record is never locked (§5 #1).
struct ArcsTabView: View {
    var arcs: ArcStore
    var forge: ForgeViewModel
    var swords: SwordStore

    @Environment(ForgeStore.self) private var store: ForgeStore?
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?
    @State private var isLeaving = false
    @State private var path: [ArcID] = []

    private var today: ForgeDay { forge.progress.currentDay }

    private var isLocked: Bool {
        guard let store else { return false }
        return forge.hasCompletedFirstRun && PremiumGate.isLocked(.arcs, for: store.access)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLocked {
                        ProLockedState { paywallDoor = .locked }
                            .forgeCard()
                            .padding(.bottom, ForgeTheme.Space.section)
                    } else if let current = arcs.current {
                        ArcRunningCard(
                            enrollment: current,
                            reading: arcs.reading(current),
                            offer: arcs.phaseOffer(),
                            arcs: arcs,
                            forge: forge,
                            swords: swords,
                            onLeave: { isLeaving = true }
                        )
                        .padding(.bottom, ForgeTheme.Space.section)
                    }

                    startable
                        .padding(.bottom, ForgeTheme.Space.section)

                    finished
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Arcs")
            .navigationDestination(for: ArcID.self) { id in
                ArcDetailView(
                    program: ArcCatalog.program(id),
                    arcs: arcs,
                    forge: forge,
                    isLocked: isLocked,
                    onLocked: { paywallDoor = .locked }
                )
            }
        }
        .paywall($paywallDoor)
        // Back to the list once an Arc has been started from its own screen:
        // the card that now leads the tab is where it lives.
        .onChange(of: arcs.current?.id) { _, id in
            if id != nil { path = [] }
        }
        .confirmationDialog(
            leavingTitle,
            isPresented: $isLeaving,
            titleVisibility: .visible
        ) {
            if let current = arcs.current, !current.added.isEmpty, current.isApplied {
                Button("Keep its activities") { leave(takingOff: false) }
                Button("Take them off", role: .destructive) { leave(takingOff: true) }
            } else {
                Button("Leave", role: .destructive) { leave(takingOff: false) }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(leavingMessage)
        }
    }

    private var leavingTitle: String {
        guard let current = arcs.current else { return "Leave" }
        return "Leave \(current.program.name)?"
    }

    private var leavingMessage: String {
        guard let current = arcs.current else { return "" }
        if current.startDay > today {
            return "It has not started, so nothing is lost and nothing in your week changes."
        }
        let count = current.added.count
        guard count > 0 else {
            return "Your days stay exactly as they are. The Arc stays on your record as far as you took it."
        }
        let things = count == 1 ? "the one activity" : "the \(ForgeCount.spelled(count).lowercased()) activities"
        return "Your days kept stay yours. You can keep \(things) it added, or take them off your week."
    }

    private func leave(takingOff: Bool) {
        ForgeHaptics.shared.tap()
        withAnimation(.forgeRow) { arcs.leave(takingOff: takingOff) }
    }

    // MARK: - The ones to start

    private var startable: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            ArcHeading(title: arcs.current == nil ? "Start an Arc" : "The Arcs")
            ForEach(ArcCatalog.offered(on: today)) { program in
                NavigationLink(value: program.id) {
                    ArcRow(
                        program: program,
                        isInSeason: program.isSeasonal && ArcCatalog.isWinterSeason(today),
                        isRunning: arcs.current?.arc == program.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - The ones finished

    @ViewBuilder
    private var finished: some View {
        let done = arcs.finished
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
                ArcHeading(title: "Finished")
                ForEach(done) { enrollment in
                    FinishedArcRow(enrollment: enrollment, reading: arcs.reading(enrollment))
                }
            }
        }
    }
}

// MARK: - The running Arc

/// The Arc being lived in: where somebody is, whether it is on track, this
/// week's trial and its count, the current phase's changes if any are waiting,
/// and what the next phase brings.
private struct ArcRunningCard: View {
    let enrollment: ArcEnrollment
    let reading: ArcReading
    let offer: ArcPhaseOffer?
    var arcs: ArcStore
    var forge: ForgeViewModel
    var swords: SwordStore
    let onLeave: () -> Void

    private var program: ArcProgram { enrollment.program }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            ArcCover(program: program, height: 150)

            if reading.status == .upcoming {
                upcoming
            } else {
                standing
                if let trial = reading.trial { trialBlock(trial) }
                if let offer { phaseOffer(offer) }
                nextPhase
                if program.withChallenge {
                    Label("The daily challenge is part of every day of it. It is on the Forge tab.", systemImage: "flag")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                share
            }

            Button("Leave \(program.name)", action: onLeave)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(ForgeTheme.Space.row)
        .forgeCard()
    }

    // MARK: Where somebody is

    private var standing: some View {
        let phase = program.phases[min(reading.phase, program.phases.count - 1)]
        return VStack(alignment: .leading, spacing: 6) {
            Text(reading.counter)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(reading.day)))
                .accessibilityAddTraits(.isHeader)
            Text(program.phases.count > 1 ? "\(phase.name) \u{00B7} \(phase.span)" : phase.name)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(ForgeTheme.cream.opacity(0.85))
            Text(reading.paceLine)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(reading.isOnTrack ? AnyShapeStyle(.secondary) : AnyShapeStyle(ForgeTheme.cream))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var upcoming: some View {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let join = arcs.preview(enrollment.arc, wake: enrollment.wakeMinute, picks: enrollment.picks)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Starts \(format.string(from: enrollment.startDay.startOfDay()))")
                .font(.title3.weight(.semibold))
            Text("\(join.headline) Nothing changes in your week until then.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: This week's trial

    private func trialBlock(_ trial: ArcTrialProgress) -> some View {
        let definition = program.trials[trial.index]
        return VStack(alignment: .leading, spacing: 8) {
            ArcHeading(
                title: "This week's trial",
                detail: "\(trial.index + 1) of \(program.trials.count)"
            )
            HStack(alignment: .firstTextBaseline) {
                Text(definition.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(trial.count) of \(trial.target)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(trial.isMet ? AnyShapeStyle(ForgeTheme.accent) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(value: Double(trial.count)))
            }
            Text(definition.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TrialMarks(progress: trial)
                .padding(.top, 2)
            if trial.isTally {
                HStack(spacing: 10) {
                    Button {
                        ForgeHaptics.shared.ritualVerified()
                        withAnimation(.forgeSelection) { arcs.tally(1, trial: trial.index) }
                    } label: {
                        Label("Mark one", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.glass)
                    .disabled(trial.isMet)
                    if trial.count > 0 {
                        Button {
                            ForgeHaptics.shared.tap()
                            withAnimation(.forgeSelection) { arcs.tally(-1, trial: trial.index) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.medium))
                                .frame(width: 44, height: 40)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Take one back")
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: A phase's changes

    /// "Week 3: Build" and what it would change, applied only on the one tap.
    private func phaseOffer(_ offer: ArcPhaseOffer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ArcHeading(title: offer.title)
            Text(offer.changes.count == 1
                 ? "One change to your week, for this phase."
                 : "\(ForgeCount.spelled(offer.changes.count)) changes to your week, for this phase.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(offer.changes) { ArcChangeRow(change: $0) }
            HStack(spacing: 10) {
                ForgeButton(title: offer.changes.count == 1 ? "Apply it" : "Apply \(offer.changes.count)") {
                    ForgeHaptics.shared.detent()
                    withAnimation(.forgeRow) { _ = arcs.applyPhase(offer) }
                }
                Button {
                    ForgeHaptics.shared.tap()
                    withAnimation(.forgeRow) { arcs.keepPhase(offer) }
                } label: {
                    Text("Keep mine")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
                .tint(.secondary)
            }
        }
        .padding(ForgeTheme.Space.inner)
        .background(
            RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                .strokeBorder(ForgeTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: What comes next

    @ViewBuilder
    private var nextPhase: some View {
        let next = reading.phase + 1
        if program.phases.indices.contains(next) {
            let phase = program.phases[next]
            let steps = ArcPlan.steps(
                for: program, picks: enrollment.picks, from: reading.phase, to: next, find: forge.ritual
            )
            VStack(alignment: .leading, spacing: 6) {
                ArcHeading(title: "Next: \(phase.name)", detail: "from day \(phase.firstDay)")
                if steps.isEmpty {
                    Text(phase.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(steps) { ArcChangeRow(change: $0) }
                }
            }
        }
    }

    // MARK: The card to share

    private var share: some View {
        let six = forge.blended
        return ProofCardButton(
            occasion: .arc(
                ArcProof(
                    title: "\(program.name) \u{00B7} \(reading.counter)",
                    scores: six.dimensions.map { $0.hasScore ? $0.score : nil },
                    overall: six.overall,
                    blade: swords.equipped.asset,
                    winters: arcs.winterMarks.count
                )
            ),
            daysKept: forge.daysKept
        )
    }
}

// MARK: - The list

/// One Arc in the list: its cover, its length, its line.
private struct ArcRow: View {
    let program: ArcProgram
    let isInSeason: Bool
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArcCover(program: program, height: 128)
            VStack(alignment: .leading, spacing: 3) {
                if isRunning {
                    Text("RUNNING NOW")
                        .font(ForgeTheme.overline)
                        .kerning(ForgeTheme.overlineKerning)
                        .foregroundStyle(ForgeTheme.accent)
                } else if isInSeason {
                    Text("THIS WINTER \u{00B7} STARTS TODAY")
                        .font(ForgeTheme.overline)
                        .kerning(ForgeTheme.overlineKerning)
                        .foregroundStyle(ForgeTheme.accent)
                }
                Text(program.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows what it asks for and how to start it"))
    }
}

/// A finished Arc on the record, with its mark.
private struct FinishedArcRow: View {
    let enrollment: ArcEnrollment
    let reading: ArcReading

    var body: some View {
        HStack(spacing: 14) {
            ArcMark(arc: enrollment.arc, size: 26)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(enrollment.recordName)
                    .font(.body.weight(.medium))
                Text(reading.outcome)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(Self.ended(enrollment.endDay))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(ForgeTheme.Space.inner)
        .forgeCard(radius: ForgeTheme.Radius.control)
        .accessibilityElement(children: .combine)
    }

    private static func ended(_ day: ForgeDay) -> String {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return format.string(from: day.startOfDay())
    }
}

// MARK: - Settings, from the navigation bar

/// The gear that opens Settings, in the navigation bars of the Becoming and
/// Blade tabs. Settings stopped being a tab when Arcs took its place; every
/// screen in it is where it was, one tap from here.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            ForgeHaptics.shared.tap()
            action()
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}
