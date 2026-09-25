import SwiftUI

/// One activity, in the day's list.
///
/// # The tap finishes it, and nothing else
///
/// This was briefly split — glyph completes, name opens the editor, the way
/// Reminders does it — and it was wrong for this app. Forge is a list of
/// promises and keeping one is the primary act of the whole product; asking
/// somebody to aim at a 55pt column to do the thing they opened the app for
/// makes the most common gesture the fussiest one. A habit list is not a task
/// manager, and the difference shows up exactly here.
///
/// So the full width of the row is the completion again, and editing moved to
/// where secondary actions belong on iOS: a long press. The context menu is not
/// a hidden feature — it is the standard shelf for "everything else about this
/// row", it previews the row while it is open, and it is the same gesture that
/// edits a reminder, a message or a home screen icon.
struct RitualRowView: View {
    let ritual: Ritual
    let isDone: Bool
    /// Tick it, or take it back.
    let onComplete: () -> Void
    /// Open it for editing.
    let onOpen: () -> Void
    /// Take it out of the day. Optional, because not every list that draws this
    /// row is a list you can remove things from.
    ///
    /// It lives here as well as on the swipe because a gesture is a pointer
    /// affordance: the menu and the accessibility action below are how the same
    /// thing is reached by VoiceOver, Switch Control, a keyboard and anybody who
    /// has never discovered that rows in this app swipe. See `SwipeToDelete`.
    var onDelete: (() -> Void)? = nil

    /// The row is two columns of text side by side, and that stops being a
    /// layout somewhere around the first accessibility size: the name is left
    /// narrower than a word and starts breaking one character to a line.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The row, and why the tap is a `TapGesture` rather than a `Button`.
    ///
    /// It was a `Button`, and a `Button` fires on touch-up **anywhere inside its
    /// own bounds, however far the finger travelled to get there**. That is
    /// correct for a button and wrong for a row that also swipes: a swipe across
    /// a row revealed Delete and completed the activity underneath it in the
    /// same gesture. It never showed while `SwipeToDelete` used
    /// `highPriorityGesture`, because winning the gesture cancelled the press —
    /// and it appeared the moment that had to become simultaneous so the day
    /// list could scroll. See `SwipeToDelete`.
    ///
    /// `TapGesture` has the movement tolerance a button does not. A drag of more
    /// than a few points fails it, which is exactly the rule this row wants: tap
    /// to finish, swipe to remove, and no gesture that is both.
    ///
    /// Nothing is lost by not being a `Button`. The style was `.plain`, so there
    /// was no pressed appearance to give up; the traits, label, value and hint
    /// are all still stated below; and the context menu and accessibility
    /// actions never came from the button in the first place.
    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 13) {
            priorityRail

            RitualGlyph(
                ritual: ritual,
                size: 20,
                color: isDone ? .secondary : .primary
            )
            .frame(width: 24, height: 24)

            if typeSize.isAccessibilitySize {
                // One column instead of two. The target goes under the name
                // rather than competing with it for a width that no longer
                // holds both.
                VStack(alignment: .leading, spacing: 6) {
                    names
                    metadata
                }
                Spacer(minLength: 8)
            } else {
                names
                Spacer(minLength: 8)
                metadata
            }

            if isDone { completionMark }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
        .onTapGesture(perform: handleComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isDone ? "Done" : "Not done"))
        // "Double tap to verify" was read out for every row, including the ones
        // nobody verifies. For an honor activity that is not a shorthand, it is
        // the wrong promise about what happens next.
        .accessibilityHint(Text(hint))
        // The long press, and the only route to editing for a pointer or a
        // keyboard. Completion is repeated here rather than left implicit: a
        // menu that offers the secondary action and not the primary one reads as
        // though the primary one is unavailable.
        .contextMenu {
            Button(
                isDone ? "Mark not done" : "Mark done",
                systemImage: isDone ? "arrow.uturn.backward" : "checkmark"
            ) { handleComplete() }
            Button("Edit", systemImage: "slider.horizontal.3") { onOpen() }
            if let onDelete {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    ForgeHaptics.shared.bottomOut()
                    onDelete()
                }
            }
        }
        // A builder rather than two `accessibilityAction(named:)` modifiers, so
        // the second one can be absent instead of present-and-inert on a list
        // that has nothing to remove.
        .accessibilityActions {
            Button("Edit activity") { onOpen() }
            if let onDelete {
                Button("Delete activity") { onDelete() }
            }
        }
    }

    // MARK: - Pieces

    private var names: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ritual.label)
                .font(.body.weight(.medium))
                .foregroundStyle(isDone ? .secondary : .primary)
                .strikethrough(isDone, color: .secondary)
                // Two lines and then an ellipsis. A name that needs a third is
                // one nobody reads to the end of anyway, and the rows either
                // side of it keep their height.
                .lineLimit(2)

            // One subtitle, and the row picks which. A second and third line
            // would be the honest way to show all three of these and would also
            // be the end of a list anybody can scan — so they are ranked
            // instead, and the row shows the most specific thing it knows.
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// What goes under the name, in order of how much it tells you.
    ///
    /// 1. **The clock**, if this activity has been given one. Somebody who set a
    ///    time did it so they would see it here.
    /// 2. **Their own note**, if they wrote one, because their words about their
    ///    own activity outrank ours about it.
    /// 3. **The shipped subtitle**, which is what the row has always shown.
    ///
    /// Nil when there is none of the three — a user-made activity with no note
    /// and no time is just a name, and a blank second line under it would be a
    /// gap rather than a subtitle.
    private var subtitle: String? {
        if let schedule = ritual.scheduleLabel { return schedule }
        if !ritual.note.isEmpty { return ritual.note }
        return ritual.sub.isEmpty ? nil : ritual.sub
    }

    /// A hairline down the leading edge of an activity marked non-negotiable.
    ///
    /// A word would be louder than the activity it labels, and a coloured glyph
    /// would fight the completion mark for the same meaning. Two points of
    /// accent says "this one" and costs no reading — and it is drawn for exactly
    /// one of the three priorities, so a day of ordinary rows has no rails in it
    /// at all.
    @ViewBuilder
    private var priorityRail: some View {
        if ritual.priority == .essential && !isDone {
            Capsule()
                .fill(ForgeTheme.accent)
                .frame(width: 2, height: 18)
                .accessibilityHidden(true)
        } else {
            // Held open so the glyphs stay in one column whether or not the row
            // above has a rail. A list whose icons shift sideways by two points
            // per row is the sort of thing nobody can name and everybody feels.
            Color.clear.frame(width: 2, height: 18)
        }
    }

    /// The right-hand column, which every row has and no row leaves empty.
    ///
    /// One font, one colour and one set of digits for the whole cluster, so the
    /// mark inherits the metadata's own weight instead of arriving with its
    /// own. `monospacedDigit` is what holds "20", "350 ml" and "2:00" in a
    /// column between rows.
    ///
    /// `fixedSize` rather than a layout priority: the target is short by
    /// construction — the composer will not accept a long one — so letting it
    /// take exactly the width it needs and giving the rest to the name is both
    /// simpler and impossible to get wrong. A priority did the opposite, and let
    /// a wide target squeeze the name down to a character a line.
    @ViewBuilder
    private var metadata: some View {
        if !isDone {
            HStack(spacing: 5) {
                if let mark = rowMark { VerificationMark(method: mark) }
                if !ritual.metadata.isEmpty { Text(ritual.metadata) }
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Which mark the day list draws, or none.
    ///
    /// The day list is stricter than the picker and the editor, and the
    /// difference is the point. Those two are showing somebody a *setting*, so
    /// they draw whatever was chosen. This is showing them their day, so it
    /// draws what is going to happen:
    ///
    /// * **The heart, only when the phone can really settle it.** An activity
    ///   marked Health with nothing behind it — see `Ritual.isHealthVerified` —
    ///   would be wearing a promise the sweep cannot keep, and the tap on it
    ///   already falls back to asking — so it is drawn as what it behaves like,
    ///   which is Your Word, and `metadata` says so in the same column.
    /// * **The checkbox, for Basic Check**, which is the whole affordance: the
    ///   empty circle is what the completion mark fills in.
    /// * **Nothing for Your Word**, because the column already says "Honor" in
    ///   words, and a glyph beside the word is the same fact twice.
    private var rowMark: VerificationMethod? {
        switch ritual.verification {
        case .basic: .basic
        case .honor: nil
        }
    }

    /// Completion is the accent colour — a finished ritual should read as
    /// finished at a glance, and it takes the column over from the target it
    /// has just answered.
    private var completionMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.body)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, ForgeTheme.accent)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Words

    /// The mark is hidden from VoiceOver, so the fact it carries has to arrive
    /// in words instead — and in the label rather than the hint, because it is a
    /// property of the activity rather than of the tap.
    ///
    /// Read off `rowMark` rather than off the setting, for the same reason the
    /// glyph is: an activity that says "Apple Health" and then asks you to
    /// confirm it has told a sighted user one thing and a VoiceOver user a
    /// worse one.
    private var label: String {
        var parts = [ritual.label]
        if ritual.priority == .essential { parts.append("Non-negotiable") }
        if let schedule = ritual.scheduleLabel { parts.append(schedule) }
        if let mark = rowMark, !isDone { parts.append(mark.title) }
        return parts.joined(separator: ", ")
    }

    private var hint: String {
        if isDone { return "Double tap to mark not done" }
        return ritual.verification.asksForConfirmation
            ? "Double tap to say you kept it"
            : "Double tap to mark done"
    }

    /// A Basic Check finishes on this tap and nothing follows it, so the tap
    /// has to carry the weight of a completion rather than of a selection.
    ///
    /// The other two methods deliberately do not get it here: Health's arrives
    /// from `ForgeViewModel.settle` once the phone has actually answered, and
    /// Your Word's from the button on the prompt — in both cases *after* the
    /// thing is known to be done. Firing it on the way in as well would be the
    /// app congratulating somebody for opening a sheet.
    private func handleComplete() {
        if !isDone, ritual.verification == .basic {
            ForgeHaptics.shared.ritualVerified()
        } else {
            ForgeHaptics.shared.tap()
        }
        onComplete()
    }
}

// MARK: - Swipe to take one out

/// The trailing action a left swipe reveals, for rows that cannot live in a
/// `List`.
///
/// The day list is a `ScrollView` over a plain `VStack` rather than a `List` —
/// rows have to animate *past each other* when one is finished, and a lazy list
/// gives a travelling row nowhere to travel to — so `.swipeActions` is not
/// available to it. This is the hand-built equivalent, and it copies the
/// system's behaviour rather than inventing a gesture of its own: drag to
/// reveal, tap the action, drag far enough and it commits without the tap, tap
/// the row to close it again, and only ever one row open at a time.
///
/// # Why the gesture outranks the row, and why it checks its direction first
///
/// It has to be a `highPriorityGesture`, and that was found the hard way. As a
/// `simultaneousGesture` the swipe worked and the row *also* completed on the
/// way up: opting out of arbitration means nothing ever cancels the button
/// underneath, so a swipe on "Drink water" slid the row open and raised its
/// honor prompt at the same time. Taking priority is what cancels the press,
/// which is exactly what a table view's own pan does to a cell it starts
/// dragging.
///
/// The scroll view is unaffected by that — it is a `UIScrollView` underneath and
/// arbitrates separately — so the list still scrolls, which was verified on a
/// device before this comment was written. What keeps the two out of each
/// other's way is the direction test: it is decided once, on the first movement
/// past the threshold, and a drag that started out vertical is somebody
/// scrolling and is left alone for the rest of its life. Deciding per-frame
/// instead would let a wobble halfway down a flick start dragging a row
/// sideways.
struct SwipeToDelete<Content: View>: View {
    /// This row's identity, which is all the shared state needs to name it.
    let id: String
    /// Which row in the list is open. Shared, so opening one closes the other —
    /// the one piece of this that cannot be held by the row itself.
    @Binding var openID: String?
    var title: String = "Delete"
    let action: () -> Void
    @ViewBuilder var content: Content

    /// Where the row is sitting right now, resting or under a finger.
    @State private var offset: CGFloat = 0
    /// The row's own width, so a full swipe can be judged against it rather than
    /// against a number that happens to be right on one phone.
    @State private var width: CGFloat = 0
    /// Whether this drag is sideways. Decided once per gesture; nil until the
    /// first movement past the threshold says which kind it is.
    @State private var isSideways: Bool?

    /// Wide enough for the glyph and the word beneath it at the default text
    /// size, and the same order of width as the system's own.
    private let actionWidth: CGFloat = 84

    private var isOpen: Bool { openID == id }

    /// How far a swipe has to run before it means it, without the tap.
    private var fullSwipe: CGFloat { max(actionWidth * 2, width * 0.55) }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Built only once the row has actually moved. Hiding it with
            // `opacity` instead would leave a full-size destructive button
            // sitting under the trailing edge of every row in the day, invisible
            // and still able to take a tap — which is the one bug in here that
            // would cost somebody an activity without ever showing itself.
            if offset < -0.5 { deleteAction }

            content
                // Open, the row itself is the way out. A tap on a row that is
                // showing a Delete must not also finish the activity under it.
                .overlay {
                    if isOpen {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                    }
                }
                // The other half of moving off `highPriorityGesture`.
                //
                // A high-priority drag cancelled the row's own button the
                // instant it recognised, which is where the swipe used to get
                // its "and the tap does not also fire" for free. Simultaneous
                // recognition does not: a `Button` fires on touch-up anywhere
                // inside its own bounds however far the finger travelled, so a
                // swipe across a row both revealed Delete *and* completed the
                // activity underneath it.
                //
                // A second belt on top of the row's own tap tolerance: while a
                // drag is known to be sideways the content takes nothing at all.
                // `isSideways` is cleared on `onEnded` and on `onDisappear`, so
                // this is only ever off for the remainder of one sideways drag
                // and nothing about the row is less tappable at rest.
                .allowsHitTesting(isSideways != true)
                .offset(x: offset)
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // **Simultaneous, never high-priority**, and this one line is the
        // difference between the day list scrolling and not.
        //
        // `highPriorityGesture` wins the touch outright: the drag recogniser
        // claims it at 12pt, the enclosing `ScrollView`'s pan is cancelled for
        // the rest of that touch, and the direction test below then decides the
        // drag was vertical and does nothing with it. The row swallowed the
        // swipe and the list stayed exactly where it was — which is precisely
        // the "it takes three swipes before it starts scrolling" report, and
        // why it was worst on a short panel where every touch lands on a row.
        //
        // Simultaneous recognition lets both run and lets the direction test do
        // the arbitrating instead. A vertical drag scrolls, because
        // `isSideways` is decided `false` on the first movement and this
        // gesture then ignores the whole rest of it. A sideways drag opens the
        // row, and the scroll view sees nearly no vertical travel to act on.
        .simultaneousGesture(swipe)
        // Another row opened, or something else put this one away.
        .onChange(of: openID) { _, current in
            guard current != id, offset != 0 else { return }
            withAnimation(.forgeRow) { offset = 0 }
        }
        // The other half of the cancellation problem above. A row that leaves
        // the screen mid-drag — which is exactly what happens when completing an
        // activity re-sorts the list under the finger — never receives
        // `onEnded`, so this is where its direction decision is thrown away.
        .onDisappear { isSideways = nil }
    }

    // MARK: - Pieces

    /// The action under the row, as wide as the swipe has made it.
    ///
    /// It grows with the drag rather than sitting at a fixed width, which is
    /// what makes a long swipe read as one continuous thing rather than as a
    /// button being overshot.
    private var deleteAction: some View {
        Button(action: commit) {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: max(actionWidth, -offset))
            .frame(maxHeight: .infinity)
            .background(ForgeTheme.destructive)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(!isOpen)
    }

    // MARK: - The gesture

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if isSideways == nil {
                    isSideways = abs(value.translation.width) > abs(value.translation.height)
                }
                guard isSideways == true else { return }
                offset = clamped(resting + value.translation.width)
            }
            // `onEnded` does not always run. A gesture the system cancels —
            // the scroll view claiming the touch, the row being recycled as the
            // list re-sorts under it when an activity is completed — ends
            // without it, and the decision made on the first 12pt of the last
            // drag would then still be sitting here when the finger came back.
            // A stale `false` is a row that has quietly stopped swiping; a
            // stale `true` is a row that starts moving sideways with no
            // direction test at all. Both were reachable, and both are the kind
            // of fault that reads as "the gesture is flaky" rather than as a
            // bug anybody can describe.
            .onEnded { value in
                defer { isSideways = nil }
                guard isSideways == true else { return }
                let travel = clamped(resting + value.translation.width)
                // A flick is judged on where it was going, not where the finger
                // happened to leave the glass.
                let momentum = value.predictedEndTranslation.width - value.translation.width
                settle(at: travel, heading: clamped(travel + momentum))
            }
    }

    private var resting: CGFloat { isOpen ? -actionWidth : 0 }

    /// Left as far as the row is wide, and never right of home — there is no
    /// leading action, so pulling that way should feel like a wall rather than
    /// like a thing that has not been built yet.
    private func clamped(_ x: CGFloat) -> CGFloat {
        min(0, max(x, -max(width, actionWidth)))
    }

    private func settle(at travel: CGFloat, heading: CGFloat) {
        if -travel >= fullSwipe {
            commit()
            return
        }
        if -heading >= actionWidth / 2 { open() } else { close() }
    }

    private func open() {
        if !isOpen { ForgeHaptics.shared.detent() }
        withAnimation(.forgeRow) {
            openID = id
            offset = -actionWidth
        }
    }

    private func close() {
        withAnimation(.forgeRow) {
            if isOpen { openID = nil }
            offset = 0
        }
    }

    /// Run it, and put the row back where it started on the way.
    ///
    /// The offset is reset rather than left at the edge of the screen because
    /// nothing here destroys the row — taking an activity out of the day leaves
    /// it in the picker to be put back — so the same row can be on screen again
    /// a moment later, and it must not arrive already swiped open.
    private func commit() {
        ForgeHaptics.shared.bottomOut()
        openID = nil
        offset = 0
        action()
    }
}
