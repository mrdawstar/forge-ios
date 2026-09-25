import SwiftUI

struct FreeStateView: View {
    @Bindable var vm: ForgeViewModel

    /// What the finished day earned, resolved by the tab that holds both the day
    /// and today's challenge. Nil until the day is actually earned, and nil for
    /// the first pull, which is given rather than earned.
    var reflection: AttributedQuote?

    /// The panel's height is driven by this, so opening the review has to move
    /// the disclosure and the panel on one curve. Left to itself the disclosure
    /// used SwiftUI's default and arrived ahead of the panel it lives in.
    private var review: Binding<Bool> {
        Binding(
            get: { vm.reviewOpen },
            set: { isOpen in
                ForgeHaptics.shared.detent()
                withAnimation(.sheetPanel) { vm.reviewOpen = isOpen }
            }
        )
    }

    /// The height of the space this actually has, so the content can be centred
    /// inside it when it is short and scroll when it is not.
    @State private var viewport: CGFloat = 0

    /// How many activities still read as a row of dots rather than as a chart.
    private static let dotLimit = 12

    /// The freed panel, which can now be taller than the panel.
    ///
    /// # Why this became a `ScrollView`
    ///
    /// Because the panel is a **fixed** height here and the content is not. It
    /// held a header, a quotation, an optional evening card and a disclosure
    /// listing every activity in the day, and the last of those grows without
    /// limit: at nine activities the review ran past the bottom edge of the
    /// glass and the rows below it were drawn outside the panel, clipped and
    /// untappable, with no gesture in the app that would reach them. The freed
    /// panel does not drag and the content did not scroll, so there was no way
    /// out of that state except finishing the day differently.
    ///
    /// Two halves to the fix and this is the one that cannot fail. The other is
    /// `ForgeTabView.sheetFreeReviewH`, which now grows with the number of
    /// activities up to the panel's own ceiling — so on an ordinary day nothing
    /// scrolls at all and this is inert. Past the ceiling, or at an
    /// accessibility text size, or with a three-line quotation and an evening
    /// card, the scroll is what makes the overflow reachable instead of lost.
    ///
    /// `minHeight` is what keeps the short case looking exactly as it did: a
    /// `Spacer` inside a scroll view collapses to nothing, so without it the
    /// quotation would stop being centred and rise to sit under the header.
    var body: some View {
        ScrollView {
            content
                .frame(minHeight: viewport)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Free.")
                    .font(.title3.weight(.semibold))
                Text(vm.finishTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                // The same button the day header carries, kept for the state
                // that outlives the day list.
                //
                // An earned day is exactly when somebody has the room to think
                // about the next one, and until this was here it was the moment
                // the app stopped letting them: the header — and the only door
                // to adding, renaming or rescheduling anything — went away with
                // the list it sat on. What is being edited is the day itself,
                // which is to say tomorrow and every day after it, so this is
                // not a second editor; it is the same one, still reachable.
                Button {
                    ForgeHaptics.shared.tap()
                    vm.showEditRituals = true
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.medium))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Edit activities")
                .accessibilityHint("Add, reorder or remove activities for the days ahead")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            // The last word of the day, and now it stays.
            //
            // The old objection to a quotation here was right about the wrong
            // thing: a borrowed sentence about the secret of your future is the
            // sound of every other habit app — but a line chosen for *what today
            // actually was*, arriving only after the work, is not that. It was
            // already being shown; it was being shown on a black screen for
            // three seconds after a sword animation, and it vanished. The one
            // sentence in Forge written to be read after the work was the one
            // nobody read.
            //
            // So the slot has three sources and one rule of precedence — see
            // `DailyLine`. A walked archetype's own line still wins, because
            // that is the world speaking and somebody chose it. Otherwise the
            // day's reflection sits here until tomorrow's replaces it, and
            // Forge's own line about the count is what shows before the day is
            // finished at all.
            DailyLine(reflection: reflection, fallback: vm.identityLine)
            Spacer()

            if vm.isEveningOpen { tomorrow }

            // Native disclosure replaces the hand-built button + rotated
            // chevron + manual transition.
            DisclosureGroup(isExpanded: review) {
                VStack(spacing: 0) {
                    Text("Tap one to take it back — the sword settles into the stone.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)

                    // Each row says whether it was actually finished. The blade
                    // can be out with the list unfinished — the first day
                    // is given rather than earned — and a review that ticked
                    // everything regardless would be reporting a day the
                    // user did not have.
                    ForEach(vm.todayRituals) { ritual in
                        let isDone = vm.isDone(ritual.id)
                        Button { if isDone { vm.undoRitual(ritual.id) } } label: {
                            HStack(spacing: 12) {
                                RitualGlyph(ritual: ritual, size: 18, color: .secondary)

                                Text(ritual.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isDone ? .primary : .secondary)

                                Spacer()

                                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                    .symbolRenderingMode(isDone ? .palette : .monochrome)
                                    .foregroundStyle(
                                        isDone ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                                        AnyShapeStyle(ForgeTheme.accent)
                                    )
                            }
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isDone)
                        .accessibilityLabel(Text(ritual.label))
                        .accessibilityValue(Text(isDone ? "Done" : "Not done"))
                        .accessibilityHint(Text(isDone ? "Double tap to undo" : ""))
                    }
                }
            } label: {
                HStack {
                    Text("TODAY")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.9)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // A dot each, until there are too many for a dot each.
                    //
                    // Twelve is where a 9pt-per-dot row starts crowding the
                    // word beside it; past that the row is not a picture of a
                    // day any more, it is a bar chart of one — so the count
                    // takes over, which is what somebody keeping twenty
                    // activities wanted to read anyway.
                    if vm.totalActive <= Self.dotLimit {
                        HStack(spacing: 4) {
                            ForEach(0..<vm.totalActive, id: \.self) { index in
                                Circle()
                                    .fill(index < vm.totalDone ? ForgeTheme.accent : Color.secondary)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(vm.totalDone) of \(vm.totalActive) done"))
                    } else {
                        Text(vm.listLabel)
                            .font(.caption2.weight(.semibold))
                            .tracking(1.9)
                            .monospacedDigit()
                            .foregroundStyle(ForgeTheme.accent)
                            .accessibilityLabel(Text("\(vm.totalDone) of \(vm.totalActive) done"))
                    }
                }
            }
            .tint(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .forgeCard(radius: ForgeTheme.Radius.control)
        }
        // 16 to match the ritual list's rows and the header above them, so
        // "Free." lands on the same left edge that "TODAY" and every
        // activity label sat on a moment earlier. It used to be 18 plus 3 of its
        // own, which put the freed state 5pt in from everything it replaced.
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    // MARK: - Tomorrow

    /// The evening's offer, and it is only ever an offer.
    ///
    /// Once tomorrow is set the row says so — and stays a way back in, which is
    /// the part that was missing. Setting it used to turn the card into a
    /// sentence, and since the sheet has no other entrance that single act
    /// sealed tomorrow for the night: somebody who remembered one more thing
    /// thirty seconds later had nowhere to put it, and somebody who set it by
    /// accident had no way to look at what they had agreed to.
    ///
    /// Nothing about the commitment itself changed. There is still no undo, and
    /// nothing counts it — a pre-commitment that could be scored would be one
    /// more thing to keep on top of, which is the opposite of what it is for.
    /// What is editable is what it was always editable: the day. Going back in
    /// and taking an activity out leaves tomorrow set, because it is still set —
    /// it is simply set to something else now.
    private var tomorrow: some View {
        Button {
            ForgeHaptics.shared.tap()
            vm.showTomorrow = true
        } label: {
            HStack(spacing: 8) {
                if vm.isTomorrowSet {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(vm.isTomorrowSet ? "Tomorrow is set." : "Tomorrow")
                    .font(.subheadline.weight(vm.isTomorrowSet ? .regular : .medium))
                    .foregroundStyle(vm.isTomorrowSet ? .secondary : .primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .forgeInteractiveCard(radius: ForgeTheme.Radius.control)
        .padding(.bottom, 10)
        .animation(.forgeSelection, value: vm.isTomorrowSet)
        .accessibilityHint(
            Text(vm.isTomorrowSet ? "Change what tomorrow is made of" : "Review tomorrow and set it")
        )
    }
}
