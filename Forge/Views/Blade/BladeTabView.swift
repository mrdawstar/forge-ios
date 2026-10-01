import SwiftUI

/// A portrait of a person, not a dashboard.
///
/// # What this used to be
///
/// A four-page stats carousel, an analytics door, a gallery of seven blades, a
/// ladder of five shipped milestones and then the user's own. Everything on it
/// was true and the screen said nothing: two progressions counting the same
/// number two hundred points apart, four swipeable cards of figures, and the one
/// genuinely irreplaceable thing on it — a marker somebody set for themselves —
/// at the very bottom under everything Forge had generated.
///
/// The test it kept failing is the only one that matters for a screen like this:
/// **could somebody read it and describe the person it belongs to?** A dashboard
/// answers "how am I doing" and this app has never been about that. So the order
/// is now a description rather than a report:
///
/// 1. **The blade**, at its current state, with the metaphor said out loud. Who
///    you are becoming, as an object.
/// 2. **Who you're becoming**, in the user's own sentences, with what the record
///    says about each. This is the thing the whole app was missing.
/// 3. **The chapter** you are inside, and what it was for.
/// 4. **The heatmap**, which is the only figure on the page that is worth
///    leading with, and one summary card behind it.
/// 5. **Your own milestones.**
/// 6. **One row** into everything else.
///
/// Nothing here is for sale. There used to be two things on this screen that
/// money changed — the grid reached five weeks instead of twelve, and trends was
/// a locked card — and both are gone. What somebody has done is theirs to look
/// at.
///
/// **It still works for somebody with nothing.** No identities, no chapter, no
/// custom milestones: sections that have nothing to say are not drawn, and what
/// is left is the blade, the grid and the door — the app as it was, minus the
/// duplication.
struct BladeTabView: View {
    @Bindable var vm: BladeViewModel
    var swords: SwordStore
    /// Who the user says they are becoming. Read here rather than through the
    /// environment because this screen needs the *store* — the environment
    /// carries only the active list, and this is the one screen that should be
    /// able to say something about a retired identity later.
    var identities: IdentityStore
    var chapters: ChapterStore
    /// The Arcs: a finished one is on the record, a Winter Arc is cut into
    /// the blade, and a running one suspends the chapter. See `chapter`.
    var arcs: ArcStore
    /// The gear: Settings is a sheet since Arcs took its tab.
    var onSettings: () -> Void = {}

    /// The milestone composer, open on a new one or on one being changed.
    @State private var composing: MilestoneComposer.Mode?
    /// The collection, which is no longer on the front page.
    @State private var showCollection = false
    /// The two chapter controls. Separate flags because they are different acts
    /// reached from different states, and one shared flag would be a sheet whose
    /// contents depended on a value somewhere else.
    @State private var isOpeningChapter = false
    @State private var isClosingChapter = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    portrait

                    becoming

                    chapter

                    record

                    arcRecord

                    milestones
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Blade")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton(action: onSettings)
                }
            }
        }
        .sheet(isPresented: $vm.showAnalytics) {
            AnalyticsSheet(vm: vm)
        }
        .sheet(item: $composing) { mode in
            composer(mode)
        }
        .sheet(isPresented: $showCollection) {
            BladeCollectionSheet(swords: swords, state: vm.bladeState)
        }
        .sheet(isPresented: $isOpeningChapter) {
            ChapterStartSheet(identities: identities) { name, intention, identityIDs in
                chapters.open(name: name, identityIDs: identityIDs, intention: intention)
            }
        }
        // A milestone can be reached while the app is closed — most of them move
        // when a day is earned, which happens on the Forge tab — so the
        // congratulation is owed on arrival rather than at the moment of
        // crossing. See `MilestoneStore.refresh(against:)`.
        .onAppear { vm.refreshMilestones() }
        .overlay { celebration }
    }

    // MARK: - 1. The blade

    /// The blade, large, with the sentence that explains what it is.
    ///
    /// **The metaphor, finally said where somebody can read it.** The first run
    /// has told everybody that the blade is who they are becoming and that every
    /// day kept is a strike, and then the app never mentioned it again — so the
    /// blades read as unlockable cosmetics, which is the one thing they must not
    /// be. One line, on the screen the blade lives on, and the whole progression
    /// becomes legible: the seven are the blade being made, and everything past
    /// them is what the work has done to it.
    ///
    /// The state is derived from days kept on every read — see `Ladder` — so
    /// this can no more disagree with the history than the count can.
    private var portrait: some View {
        VStack(spacing: 16) {
            SwordArt(
                assetName: swords.equipped.asset,
                width: 74,
                height: 168,
                solid: 0.55,
                crossfade: true
            )
            .bladeState(vm.bladeState)
            // Every winter finished, cut into the steel. See `WinterEngraving`.
            .winterEngraving(arcs.winterMarks.count, width: 74, spriteHeight: 74 * 1771 / 483)
            .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: swords.equippedID)

            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Text(vm.rung.name)
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)

                    // The state is named beside the blade rather than instead of
                    // it: at four hundred days somebody is carrying the Proven
                    // Sword, honed — two facts about one object, and dropping
                    // either would be a different sentence.
                    if let state = vm.bladeState.label, vm.rung.mark.state == nil {
                        Text(state)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .glassEffect(.regular, in: .capsule)
                    }
                }

                Text(Self.metaphor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ladderRow

            collectionRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .forgeCard()
        .padding(.bottom, 26)
    }

    /// The way into the collection, which used to be a gallery on this page.
    ///
    /// It came off the front page because seven cards of blades — most of them
    /// locked, all of them the same object at different ranks — is a shelf of
    /// unlockables, and a shelf of unlockables is the exact reading of the
    /// blades that the metaphor above exists to prevent. What is left here is
    /// the one thing somebody actually comes for: choosing which one they carry.
    ///
    /// It is a row rather than a tap on the artwork, because an image that
    /// silently opens a sheet is a control nobody finds.
    private var collectionRow: some View {
        Button {
            ForgeHaptics.shared.tap()
            showCollection = true
        } label: {
            HStack(spacing: 8) {
                Text("Your blades")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if !swords.newIDs.isEmpty {
                    Circle()
                        .fill(ForgeTheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(swords.ownedLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your blades, \(swords.ownedLabel)")
        .accessibilityHint("Choose which blade you carry")
    }

    /// Said once, here, and nowhere else in the app outside the first run. A
    /// sentence repeated on four screens stops being a metaphor and becomes a
    /// tagline.
    ///
    /// It reads *what you are building* rather than *who you're becoming*, so
    /// it is the same sentence the first run's metaphor beat says — the one
    /// place the app explains its own image should not have two wordings of it.
    private static let metaphor =
        "The blade is what you are building. Every day you keep is a strike."

    /// Where the ladder is, and what is next on it.
    ///
    /// One row rather than the old "NEXT BLADE" card, because past sixty days
    /// there is no next blade — there is a next *state*, and the same row has to
    /// carry both. It says the distance in days rather than a percentage: a
    /// percentage of a practice is a completion bar, and this is not a thing
    /// being completed.
    @ViewBuilder
    private var ladderRow: some View {
        if let next = vm.nextRung {
            Divider()

            HStack(spacing: 14) {
                ProgressRing(progress: vm.rungProgress, size: 42, lineWidth: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    Text(next.name)
                        .font(.subheadline.weight(.medium))
                    if let label = vm.nextRungLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Next, \(next.name). \(vm.nextRungLabel ?? "")"))
        }
    }

    // MARK: - 2. Who you're becoming

    /// The identities, with what the record says about each.
    ///
    /// Not drawn at all for somebody who has named nothing, and that is not an
    /// empty state — it is most installs. An app that put "You haven't set an
    /// identity yet" on the record screen would be marking somebody absent from
    /// a question they were asked once and declined.
    @ViewBuilder
    private var becoming: some View {
        if !identities.active.isEmpty {
            SectionHeader(title: "WHO YOU'RE BECOMING")
                .padding(.bottom, 12)

            VStack(spacing: 9) {
                ForEach(identities.active) { identity in
                    identityRow(identity)
                }
            }
            .padding(.bottom, 26)
        }
    }

    /// "Someone who trains · Thirty-four days of evidence · since March".
    ///
    /// Three facts and no bar. A progress bar under an identity would be asking
    /// what percentage of a person somebody has completed, which is both
    /// meaningless and unpleasant — an identity is not a thing you finish, it is
    /// a thing you accumulate evidence for.
    private func identityRow(_ identity: Identity) -> some View {
        let evidence = vm.evidence(for: identity)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: identity.symbol)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(identity.accent.palette.accent)
                .frame(width: 32, height: 32)
                .background(ForgeTheme.separator, in: RoundedRectangle(
                    cornerRadius: ForgeTheme.Radius.glyph - 4, style: .continuous
                ))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(identity.statement)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.evidenceLine(evidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .forgeCard(radius: ForgeTheme.Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(identity.statement). \(Self.evidenceLine(evidence))"))
    }

    /// What the record honestly supports, and nothing more.
    ///
    /// Three states, and the first two matter as much as the third. An identity
    /// with nothing tagged to it says so rather than reporting a confident zero
    /// — "no evidence" and "nothing points at this" are different facts and only
    /// the second is true. Numbers as words, like everywhere else Forge says a
    /// count to somebody.
    static func evidenceLine(_ evidence: BladeViewModel.IdentityEvidence) -> String {
        guard evidence.hasActivities else {
            return "Nothing in your day is tagged to this yet."
        }
        guard evidence.days > 0 else { return "No days of evidence yet." }
        let days = evidence.days == 1
            ? "One day of evidence"
            : "\(ForgeCount.spelled(evidence.days)) days of evidence"
        guard let since = evidence.since else { return days }
        return "\(days) · since \(since)"
    }

    // MARK: - 3. The chapter

    /// What somebody is in the middle of.
    ///
    /// The section that gives a four-hundred-day practice something to be
    /// *inside* rather than something to be maintaining — see `Chapter`. Drawn
    /// only when there is one open: a closed chapter is history and belongs to
    /// the review that has not been built yet, and no chapter at all is an
    /// ordinary state that needs no announcement.
    ///
    /// # While an Arc runs
    ///
    /// **The chapter is suspended.** An Arc is a stretch of days with a start,
    /// an end and a counter, and a chapter is too; two bars running two
    /// lengths over the same days ask somebody to keep two scores. So while an
    /// Arc runs the chapter is one quiet line, nothing is drawn against it, and
    /// its six-week close is not offered (`ContentView.isChapterDue`). Nothing
    /// about it changes: it is a window over the record, it goes on covering
    /// the same days, and it is back, exactly as true, the day the Arc ends.
    ///
    /// Why not run the Arc *as* a chapter: a chapter is a name, an intention
    /// and an open date, with no length or program of its own, and it is a
    /// synced row. Carrying an Arc would mean new columns on the server's
    /// chapters table and a six-week close that would fire forty-eight days
    /// into a Winter Arc.
    @ViewBuilder
    private var chapter: some View {
        if let running = arcs.currentReading, running.isRunning {
            suspendedChapter(running)
        } else if let chapter = chapters.current {
            openChapter(chapter)
        } else {
            noChapter
        }
    }

    /// The chapter, while an Arc has the days.
    @ViewBuilder
    private func suspendedChapter(_ running: ArcReading) -> some View {
        let name = ArcCatalog.program(running.arc).name
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: chapters.current == nil ? "CHAPTERS" : "THIS CHAPTER")
            Text(chapters.current.map { "\($0.name) waits while \(name) runs." }
                 ?? "Chapters wait while \(name) runs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 26)
    }

    /// The offer, for somebody who is not in a chapter.
    ///
    /// # Why this is drawn at all
    ///
    /// Chapters were reachable from exactly one place: the end of the first run
    /// opened the first one, and the six-week close offered the next. Anybody
    /// who closed one deliberately, or who arrived before chapters existed, had
    /// no route back into the system for the rest of their life in the app — so
    /// the most considered thing Forge has to offer was, for those people,
    /// simply absent with no explanation.
    ///
    /// # Why it says what a chapter *is* rather than "Start a chapter"
    ///
    /// Because a bare button here would be the random button this section was
    /// added to avoid. "Chapter" is Forge's word, not a word somebody arrives
    /// knowing, and a control whose label is jargon is a control people press
    /// once to find out and then never again. Three lines, in the order a
    /// stranger needs them: what it is, what it does not do, and what they get
    /// at the end of it. The second line is the load-bearing one — the first
    /// question anybody sensibly asks of a new thing in a habit app is whether
    /// it can be failed, and the answer here is no.
    private var noChapter: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "CHAPTERS")
                .padding(.bottom, 0)

            Text("Six weeks with a name on it.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("A chapter gives a stretch of days something to be for. It changes nothing about how they are counted — nothing here can be failed, and closing one early costs you nothing. At the end you read the six weeks back, in your own words.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                ForgeHaptics.shared.tap()
                isOpeningChapter = true
            } label: {
                Text("Start a chapter")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .forgeCard()
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private func openChapter(_ chapter: Chapter) -> some View {
        Group {
            let reading = vm.reading(for: chapter)

            SectionHeader(title: "THIS CHAPTER", detail: vm.place(of: chapter))
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 12) {
                Text(chapter.name)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                // The sentence they wrote about what it is for. Shown back
                // verbatim and never scored against — nothing in the app reads
                // this except the person who wrote it.
                if !chapter.intention.isEmpty {
                    Text(chapter.intention)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Where it is in its six weeks. A bar is honest here in a way it
                // is not under an identity: a chapter genuinely has a length,
                // and this is elapsed time rather than an assessment.
                ProgressView(value: vm.progress(of: chapter))
                    .progressViewStyle(.linear)
                    .tint(ForgeTheme.accent)

                Text(Self.chapterLine(reading))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // The way out, and it is deliberately the quietest thing on the
                // card. A chapter that can only end by running its six weeks is
                // a commitment somebody made once and cannot revise, which is
                // the opposite of what this system is for — see
                // `ChapterStore.close`, where the same argument is made about
                // the storage. Confirmed once, because it is a line drawn and
                // an accidental one would be a strange thing to find later.
                //
                // Hidden for the first fortnight — see
                // `ChapterReading.canClose`.
                if reading.canClose {
                    Divider()
                        .padding(.top, 2)

                    Button("Close this chapter") {
                        ForgeHaptics.shared.tap()
                        isClosingChapter = true
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .confirmationDialog(
                        "Close this chapter?",
                        isPresented: $isClosingChapter,
                        titleVisibility: .visible
                    ) {
                        Button("Close chapter") { chapters.close() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        // Says the one thing somebody standing here needs to know:
                        // that this is not a reset. Nothing about a chapter ever
                        // owned any of the history it lay over.
                        Text("The days inside it stay exactly as they are — nothing is reset and nothing is lost. You can start another whenever you like.")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .forgeCard()
            .padding(.bottom, 26)
        }
    }

    /// "Nineteen days kept, of twenty-eight." Two cumulative figures and no
    /// verdict: a chapter cannot be failed, so nothing here may read as a mark.
    ///
    /// The singular is not pedantry — a chapter's first card is the one
    /// everybody sees, and it read "One days kept, of 1 so far."
    static func chapterLine(_ reading: ChapterReading) -> String {
        guard reading.daysKept > 0 else { return "Nothing kept in it yet." }
        let word = reading.daysKept == 1 ? "day" : "days"
        return "\(ForgeCount.spelled(reading.daysKept)) \(word) kept, of \(reading.daysElapsed) so far."
    }

    // MARK: - 4b. The Arcs finished

    /// Every Arc run to its end, with its mark — "Winter Arc 2026 · Completed,
    /// 84 of 90 days". Part of the record, so it is never locked (§5 #1), and
    /// not drawn at all until there is one.
    @ViewBuilder
    private var arcRecord: some View {
        let finished = arcs.finished
        if !finished.isEmpty {
            SectionHeader(title: "ARCS")
                .padding(.bottom, 12)
            VStack(spacing: 9) {
                ForEach(finished) { enrollment in
                    HStack(spacing: 12) {
                        ArcMark(arc: enrollment.arc, size: 20)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(enrollment.recordName)
                                .font(.subheadline.weight(.medium))
                            Text(arcs.reading(enrollment).outcome)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .forgeCard(radius: ForgeTheme.Radius.control)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.bottom, 26)
        }
    }

    // MARK: - 4. The record

    private var record: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "THE RECORD")
                .padding(.bottom, 12)

            statsCarousel

            analyticsRow
                .padding(.top, 2)
        }
        .padding(.bottom, 26)
    }

    /// One row, and everything that needs room is behind it.
    ///
    /// The alternative was four more cards on this screen, and that is how a
    /// record of a practice turns into a dashboard: every statistic wins its own
    /// argument for being on the front page, and the front page stops saying
    /// anything. **Two pages and a door** — it was written as "three pages and a
    /// door", then grew to four, which is how it read as a dashboard in the end.
    /// Habits and trends are behind this row now, where they were always meant
    /// to be: both need months of history before they say anything, and neither
    /// is a description of a person.
    private var analyticsRow: some View {
        Button {
            ForgeHaptics.shared.tap()
            vm.showAnalytics = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ForgeTheme.accent)
                Text("All analytics")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                Text(analyticsHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .forgeInteractiveCard(radius: ForgeTheme.Radius.control)
        .accessibilityLabel("All analytics")
        .accessibilityHint("Habits, trends, the chain, week by week, and any year on file")
    }

    /// The one number worth putting on the door. It is the answer to the
    /// question people open an analytics screen with, so showing it here means
    /// most of them never need to.
    private var analyticsHint: String {
        let summary = vm.summary
        guard !summary.isEmpty else { return "" }
        return "\(summary.completionPercent)% completion"
    }

    // MARK: - 5. Milestones

    /// The ones somebody set themselves, and only those.
    ///
    /// The shipped ladder used to sit above this under its own heading, counting
    /// days kept at 1/7/30/100/365 — the same number the blades count, told
    /// again in different words. It is gone into `Ladder`, at the top of this
    /// screen, where it is one progression instead of two.
    ///
    /// What is left is the best thing on the page: a marker Forge could not have
    /// derived, because nothing in a history says somebody *wanted* to read for
    /// thirty days. No count on the header — how many of these somebody has
    /// reached is a score, and these are not things to collect.
    private var milestones: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "YOUR MILESTONES",
                detail: vm.milestones.canAddMore ? nil : "Twelve is the limit"
            )
            .padding(.bottom, 12)

            VStack(spacing: 9) {
                ForEach(vm.customMilestones) { milestone in
                    Button {
                        ForgeHaptics.shared.tap()
                        composing = .edit(id: milestone.id)
                    } label: {
                        MilestoneRow(milestone: milestone, isEditable: true)
                    }
                    .buttonStyle(.plain)
                }

                if vm.customMilestones.isEmpty { emptyMilestones }
                if vm.milestones.canAddMore { addMilestoneButton }
            }
            .padding(.bottom, 28)
        }
    }

    /// Said as an invitation rather than as an empty state, because there is
    /// nothing missing here — somebody who never sets one has lost nothing, and
    /// the ladder above is already a complete answer to "how far along is this".
    private var emptyMilestones: some View {
        Text("Set yourself one. Read thirty days, meditate a hundred times — anything you are already counting in your head.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }

    private var addMilestoneButton: some View {
        Button {
            ForgeHaptics.shared.tap()
            composing = .create
        } label: {
            Label("New Milestone", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
        .accessibilityHint("Set yourself a marker to work toward")
    }

    @ViewBuilder
    private func composer(_ mode: MilestoneComposer.Mode) -> some View {
        switch mode {
        case .create:
            MilestoneComposer(
                mode: .create,
                subjects: vm.milestoneSubjects,
                onCommit: { vm.addMilestone($0) }
            )
        case let .edit(id):
            if let draft = vm.draft(for: id) {
                MilestoneComposer(
                    mode: .edit(id: id),
                    draft: draft,
                    subjects: vm.milestoneSubjects,
                    onCommit: { vm.updateMilestone(id, to: $0) },
                    onDelete: { vm.deleteMilestone(id) }
                )
            }
        }
    }

    @ViewBuilder
    private var celebration: some View {
        if let reached = vm.milestones.pendingCelebration {
            MilestoneCelebration(
                milestone: reached,
                subtitle: reached.note(
                    activityName: reached.subject.activityID.flatMap(vm.activityName)
                ),
                onDismiss: { vm.milestones.dismissCelebration() }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }

    // MARK: - Stats

    /// Both pages are laid into exactly this rect.
    ///
    /// Each card used to size itself to its own content, and the page view
    /// centred whatever it got — so the two pages were different heights and
    /// the card appeared to grow and shrink mid-swipe. Fixing the rect and
    /// letting the content fill it is what makes a swipe read as turning a page
    /// rather than resizing a box.
    private static let statsCardHeight: CGFloat = 208
    /// The band below the card that the page dots sit in. They are bottom-
    /// aligned within it, so this is what sets the gap between the card and the
    /// dots — deep enough that they read as belonging to the card below it,
    /// rather than crowding its edge.
    private static let statsIndexHeight: CGFloat = 38

    /// The grid, and one card of figures behind it. **Two pages**, down from
    /// four: habits and trends moved behind the analytics door, which is where
    /// the file's own comment said they belonged before they were promoted onto
    /// the front page one at a time.
    private var statsCarousel: some View {
        TabView(selection: $vm.statPage) {
            statsPage { heatmapContent }.tag(0)
            statsPage { summaryContent }.tag(1)
        }
        // Native page indicator replaces the hand-drawn capsule dots.
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .frame(height: Self.statsCardHeight + Self.statsIndexHeight)
    }

    private func statsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(18)
                // Fill the card, then fix the card: the inner content stretches
                // to the rect so its spacers do the balancing, and the rect
                // itself never changes between pages.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: Self.statsCardHeight)
                .forgeCard()

            // Leaves the page indicator its own room instead of letting it sit
            // on top of the card.
            Spacer(minLength: 0)
        }
    }

    private var heatmapContent: some View {
        let heatmap = vm.heatmap
        return VStack(spacing: 0) {
            SectionHeader(title: vm.heatWindow, detail: vm.heatCount(heatmap))

            Spacer(minLength: 12)

            HeatmapView(data: heatmap.columns, rest: heatmap.restColumns)

            Spacer(minLength: 10)

            HStack {
                Text(BladeViewModel.shortDate(heatmap.start))
                Spacer()
                Text(BladeViewModel.shortDate(heatmap.end))
            }
            .font(ForgeTheme.mono(9))
            .tracking(1.0)
            .foregroundStyle(.tertiary)
        }
    }

    /// Three facts about a practice, side by side with air between them rather
    /// than cells in a ruled table. The drawn crosshair of dividers was what
    /// made this read as a generic dashboard; whitespace and a tinted glyph
    /// carry the same grouping without the furniture.
    ///
    /// A fourth used to sit here: the longest streak ever run. It is gone from
    /// the app entirely now — not just off this card — because it is a personal
    /// best and nothing else, a number whose only job is to be beaten and which
    /// spends most of its life describing somebody the user no longer is.
    private var summaryContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "SO FAR", detail: vm.since)

            Spacer(minLength: 14)

            HStack(spacing: 12) {
                summaryStat(icon: "calendar", label: "Days kept", value: vm.daysKept)
                // The chain, which this codebase has always called a chain.
                summaryStat(icon: "link", label: "In a row", value: vm.streak)
                // Replaces the running total of activities ever finished, which
                // was the one figure here that only ever went up and therefore
                // said the same thing as "Days kept" in a bigger font. A rate
                // says something neither of the other two can: not how much has
                // been done, but how much of what was actually asked for.
                // The raw total is still on the analytics sheet.
                summaryStat(
                    icon: "percent",
                    label: "Completion",
                    value: vm.summary.completionPercent,
                    suffix: "%"
                )
            }

            Spacer(minLength: 8)

            // Deliberately a sentence at the foot of the card rather than a
            // fifth stat block. Rest is not a score, and giving it a number of
            // its own next to the streak would make it one.
            if let note = vm.restNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summaryStat(
        icon: String, label: String, value: Int, suffix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(ForgeTheme.cream.opacity(0.7))
                    .frame(width: 12, alignment: .leading)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 26, weight: .semibold))
                    // Monospaced digits keep the figures on a common rhythm, and
                    // let the count roll rather than jump when a day lands.
                    .monospacedDigit()
                    .contentTransition(.numericText())

                // A step down rather than the same size: the unit is not part of
                // the figure, and "42%" set solid reads as a three-character
                // number beside two two-character ones.
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(value)\(suffix)"))
    }
}

// MARK: - The collection

/// The seven blades, behind a door.
///
/// They were a gallery on the front of the Blade tab, and that is where they did
/// the damage: seven cards, four of them locked at any given time, reading as a
/// set to be completed. The blades are not a set — they are one blade at seven
/// stages of being made, which is what the portrait behind this sheet now says.
///
/// So the collection is what it always actually was: the place you go to choose
/// which one you carry. Every earned blade is shown in the **state the practice
/// has put it in**, so the card and the stone and the portrait cannot disagree
/// about how old somebody's blade is.
struct BladeCollectionSheet: View {
    var swords: SwordStore
    let state: BladeState

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(swords.swords) { sword in
                        SwordCardView(
                            sword: sword,
                            isEquipped: swords.isEquipped(sword.id),
                            isNew: swords.isNew(sword.id),
                            onTap: { equip(sword) }
                        )
                        // Only what has been earned wears its age. A locked
                        // blade has had no practice put into it.
                        .bladeState(sword.isUnlocked ? state : .raw)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Your blades")
            .navigationSubtitle(swords.ownedLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// Tapping an owned blade carries it, immediately. A locked one only
    /// acknowledges the tap — there is nothing to buy and nothing to explain
    /// that the card is not already saying.
    private func equip(_ sword: Sword) {
        guard sword.isUnlocked else {
            ForgeHaptics.shared.detent()
            return
        }
        guard !swords.isEquipped(sword.id) else {
            swords.acknowledge(sword.id)
            return
        }
        ForgeHaptics.shared.tap()
        swords.equip(sword.id)
    }
}

// MARK: - Starting one

/// Naming six weeks, and nothing else.
///
/// # Why the name is required and the rest is not
///
/// The name is the whole handle somebody has on a stretch of their life — it is
/// what the close reads back to them and what makes a chapter a thing rather
/// than a date range. `ChapterStore.open` refuses a blank one, so the button
/// here is disabled rather than the refusal being discovered after the fact.
///
/// The intention is optional and stays optional. Forcing a sentence about what
/// six weeks are *for* in front of somebody who wants to name them "Winter" and
/// get on with it is the app requiring the answer to a question it asked — and
/// the field is still there in six weeks if they think of something.
///
/// There is no length picker. Six weeks is the length, it is a suggestion rather
/// than a deadline, and nothing is lost by running over — see `Chapter`.
struct ChapterStartSheet: View {
    var identities: IdentityStore
    /// Name, intention, and which identities this chapter is about.
    var onOpen: (String, String, [String]) -> Void

    @State private var name = ""
    @State private var intention = ""
    @State private var chosen: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var canOpen: Bool {
        !Chapter.trimmed(name, to: Chapter.nameLimit).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name it", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Chapter name")

                    TextField("What is it for?", text: $intention, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("What this chapter is for")
                } footer: {
                    Text("\"Winter\", \"Getting back to it\", \"Six weeks of mornings\". The second line is optional and you can write it later.")
                }

                // Only offered to somebody who has named an identity. A picker
                // with nothing in it would be a section explaining a feature
                // they have not met yet, on a screen about something else.
                if !identities.active.isEmpty {
                    Section {
                        ForEach(identities.active) { identity in
                            Button {
                                if chosen.contains(identity.id) {
                                    chosen.remove(identity.id)
                                } else {
                                    chosen.insert(identity.id)
                                }
                            } label: {
                                HStack {
                                    Text(identity.statement)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if chosen.contains(identity.id) {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(ForgeTheme.accent)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                chosen.contains(identity.id) ? [.isButton, .isSelected] : .isButton
                            )
                        }
                    } header: {
                        Text("What it is about")
                    } footer: {
                        Text("Optional. The close reads back what the record says about each one.")
                    }
                }
            }
            .navigationTitle("New Chapter")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        ForgeHaptics.shared.ritualVerified()
                        onOpen(name, intention, Array(chosen))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canOpen)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}
