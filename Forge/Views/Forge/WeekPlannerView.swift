import SwiftUI

/// The week, as something you arrange rather than something you read.
///
/// # What this replaces, and why
///
/// The first version of this was seven rows with progress bars on them. It
/// looked fine and it was the wrong screen: it answered "how has this week
/// gone", which is a question the Blade tab already answers with twelve weeks
/// and a heatmap, and it answered nothing at all about the week that has not
/// happened yet. Nothing on it could be tapped. A planner where tapping a
/// Wednesday does nothing is a picture of a planner.
///
/// So this is the other thing: pick a day, see what is on it, change it. Every
/// row opens. Empty days offer to be filled. The strip along the top is
/// navigation, not a chart — the marks on it are there to make a day worth
/// choosing, not to grade it.
///
/// # What a day means here
///
/// Forge keeps a practice, not a calendar, so a day of the week is a *standing
/// arrangement*: "read, every evening, twenty minutes". Moving Wednesday's
/// reading to Thursday moves it every Thursday, because that is the only kind of
/// Wednesday this app has. The screen says so where it matters rather than
/// pretending otherwise — see `ForgeViewModel`'s note on the week.
///
/// Days already lived are the exception and are read-only: they show what was
/// actually planned and finished on the day, out of the record, because a past
/// Tuesday is a fact and today's routine is not a description of it.
struct WeekPlannerView: View {
    @Bindable var vm: ForgeViewModel
    var progress: ProgressStore
    /// What Forge would tell a model about this person. Only Plan reads it, and
    /// Plan lives on this screen — see `ForgeControlBar`.
    var brief: AIBrief
    var ai: ForgeAI

    /// Whether the panel is at its tall detent, so the timeline can size itself
    /// to it. The planner opens expanded — see `ForgeTabView`.
    var canExpand: Bool
    /// The panel's own drag, reported from this screen's chrome — everything
    /// above the timeline is grip band, exactly as the day header is in Today.
    var onGripChanged: (CGFloat) -> Void
    var onGripEnded: (DragGesture.Value) -> Void


    /// Which day is open. A `ForgeDay` rather than an index, so moving between
    /// weeks cannot silently change which day is selected.
    @State private var selected: ForgeDay?
    /// Weeks away from the one the app is in. Zero on every appearance — see
    /// `ForgeTabView`, which resets the mode for the same reason.
    @State private var offset = 0

    /// The activity being edited, or nil. One optional rather than a bool plus a
    /// payload, so there is no state in which the sheet is up with nothing in it.
    @State private var editing: Ritual?
    @State private var isAdding = false
    @State private var isPlanning = false
    /// Which way round the copy sheet is, or nil for closed.
    @State private var copying: CopyDirection?
    /// Which row is swiped open. One per list, as in the day panel.
    @State private var swipedID: String?

    /// Copying goes both ways, and both are the same sheet.
    ///
    /// The two are not symmetrical in use, which is why both exist. From a full
    /// day the thought is "Thursday should be like this" — that is `.out`, and it
    /// lives in the day's own menu. From an empty day the thought is "make this
    /// like Monday" — that is `.incoming`, and it belongs on the empty state,
    /// where it is the fastest way anybody will ever fill a day.
    enum CopyDirection: String, Identifiable {
        case out, incoming
        var id: String { rawValue }
    }

    // MARK: - The week in question

    private var weekStart: ForgeDay {
        let calendar = Calendar.current
        let index = (progress.currentDay.weekday - calendar.firstWeekday + 7) % 7
        return progress.currentDay.adding(days: -index + offset * 7)
    }

    private var days: [ForgeDay] { (0..<7).map { weekStart.adding(days: $0) } }

    private var openDay: ForgeDay {
        // Today when the week holds it, otherwise the top of whichever week is
        // on screen. Somebody paging back to March wants Monday, not a day that
        // happens to share a weekday with today.
        selected ?? days.first { $0 == progress.currentDay } ?? weekStart
    }

    private var isPast: Bool { openDay < progress.currentDay }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                weekHeader
                dayStrip
                dayHeader
            }
            .contentShape(.rect)
            .gesture(gripDrag)

            timeline
        }
        .sheet(item: $editing) { ritual in
            composer(for: ritual)
        }
        .sheet(isPresented: $isAdding) {
            AddToDaySheet(vm: vm, weekday: openDay.weekday) { isAdding = false }
        }
        .sheet(isPresented: $isPlanning) {
            PlanSheet(
                vm: vm,
                brief: brief,
                ai: ai,
                // Already on the week, which is where every change it makes
                // lands. Nothing to do but close.
                onApplied: {}
            )
        }
        .sheet(item: $copying) { direction in
            CopyDaySheet(
                vm: vm,
                anchor: openDay.weekday,
                direction: direction,
                // Land on whichever day now holds the copy. Copying Monday to
                // Thursday and being left looking at Monday is the app hiding
                // its own work — the point of the gesture is to see Thursday.
                onCopied: { weekday in
                    guard let day = days.first(where: { $0.weekday == weekday }) else { return }
                    withAnimation(.forgeRow) { selected = day }
                }
            )
        }
        // Paging weeks must not strand a selection in a week nobody is looking
        // at, and coming back to this week should land on today.
        .onChange(of: offset) { _, _ in
            selected = days.first { $0 == progress.currentDay } ?? weekStart
        }
    }

    // MARK: - The panel's own drag

    /// The panel's drag, on this screen's chrome.
    ///
    /// The same gesture the day panel's grip band carries, and deliberately not
    /// on the timeline: the timeline scrolls, and a drag competing with a scroll
    /// for the same finger is the conflict this whole arrangement exists to
    /// avoid. See `PanelListBehavior`.
    private var gripDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard canExpand else { return }
                onGripChanged(-value.translation.height)
            }
            .onEnded { value in
                guard canExpand else { return }
                onGripEnded(value)
            }
    }

    // MARK: - Which week

    private var weekHeader: some View {
        HStack(spacing: 0) {
            step(-1, "chevron.left", "Previous week")

            Spacer(minLength: 0)

            Button {
                guard offset != 0 else { return }
                ForgeHaptics.shared.tap()
                withAnimation(.forgeRow) { offset = 0 }
            } label: {
                Text(rangeLabel)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(offset == 0
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(ForgeTheme.accent))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 8)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(offset == 0)
            .accessibilityLabel(Text(offset == 0 ? rangeLabel : "\(rangeLabel). Back to this week"))

            Spacer(minLength: 0)

            step(1, "chevron.right", "Next week")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: rangeLabel)
    }

    private func step(_ by: Int, _ symbol: String, _ spoken: String) -> some View {
        Button {
            ForgeHaptics.shared.tap()
            withAnimation(.forgeRow) { offset += by }
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    private var rangeLabel: String {
        if offset == 0 { return "THIS WEEK" }
        let last = days[6]
        let start = Self.dayMonth.string(from: weekStart.startOfDay())
        let end = Self.dayMonth.string(from: last.startOfDay())
        return "\(start) – \(end)".uppercased()
    }

    // MARK: - Seven days

    /// Navigation, and only navigation.
    ///
    /// A letter, a date and one dot. The dot is deliberately not a score — see
    /// `mark(_:)` — and the date sits in a circle rather than in the filled
    /// rounded square this used to be.
    ///
    /// The circle is the whole of the change and it is worth the sentence: a
    /// 44pt slab of cream behind one date read as a *cell in a chart*, which is
    /// exactly what this screen is not, and it fought the capsule in the control
    /// bar directly above it for the same job. A 30pt disc is the shape iOS uses
    /// for a selected date everywhere it has one, it leaves the strip breathing,
    /// and — because it is smaller than the chip — the whole 52pt row is still
    /// the target while only the date looks selected.
    private var dayStrip: some View {
        HStack(spacing: 2) {
            ForEach(days) { day in
                dayChip(day)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func dayChip(_ day: ForgeDay) -> some View {
        let isOpen = day == openDay
        let isToday = day == progress.currentDay

        return Button {
            guard !isOpen else { return }
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { selected = day }
        } label: {
            VStack(spacing: 4) {
                Text(Self.initial(day))
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .opacity(isOpen ? 1 : 0.75)

                ZStack {
                    if isOpen {
                        Circle()
                            .fill(ForgeTheme.cream)
                            // One shared geometry, so the disc slides along the
                            // week instead of blinking out and in somewhere
                            // else. The same effect the TODAY/WEEK pill uses,
                            // which is what makes the two read as one control
                            // layer.
                            .matchedGeometryEffect(id: "openDay", in: strip)
                    } else if isToday {
                        // Today, unselected, is a ring: present without
                        // competing with the day somebody is actually planning.
                        Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                    }

                    Text("\(day.day)")
                        .font(.system(size: 14, weight: isOpen || isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dateStyle(isOpen: isOpen, isToday: isToday))
                }
                .frame(width: 30, height: 30)

                mark(day)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.spoken(day, isToday: isToday)))
        .accessibilityValue(Text(spokenState(day, record: progress.byDay[day])))
        .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
    }

    private func dateStyle(isOpen: Bool, isToday: Bool) -> AnyShapeStyle {
        if isOpen { return AnyShapeStyle(.black) }
        return isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    @Namespace private var strip

    // MARK: - Which day

    /// The open day's name, and the one button that adds to it.
    ///
    /// This is deliberately the same shape as the day panel's own header — a
    /// label on the left, a 34pt glass `+` on the right — so "add something"
    /// lives in the same place and looks the same whichever of the two views
    /// somebody is in.
    ///
    /// It replaces an "Add to Thursday" row at the *foot* of the timeline, which
    /// was the wrong place for the reason all footers are: on a full day you had
    /// to scroll past everything you already do in order to add one more thing.
    /// The commonest action on a planner should never be the furthest away.
    private var dayHeader: some View {
        HStack(spacing: 8) {
            Text(Self.weekdayName(openDay.weekday).uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.25), value: openDay)

            Spacer(minLength: 0)

            if !isPast {
                // Always present, unlike the version this replaces, which
                // appeared only on a day that already held something. Plan is
                // in here now — see `ForgeControlBar` for why it left the home
                // screen — and Plan is at its most useful on the week somebody
                // has not sorted out yet, which is exactly the week with an
                // empty day in it.
                Menu {
                    Button {
                        ForgeHaptics.shared.tap()
                        isPlanning = true
                    } label: {
                        Label("Plan the week", systemImage: "sparkle")
                    }

                    // Only where there is something to copy. An item that would
                    // do nothing is worse than no item, and an empty day has its
                    // own, better offer waiting on the empty state.
                    if !items.isEmpty {
                        Divider()
                        Button {
                            copying = .out
                        } label: {
                            Label("Copy \(Self.weekdayName(openDay.weekday)) to…",
                                  systemImage: "square.on.square")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.medium))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("More")
                .accessibilityHint("Plan the week, or copy this day to another day")

                Button {
                    ForgeHaptics.shared.tap()
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.medium))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Add to \(Self.weekdayName(openDay.weekday))")
                .accessibilityHint("Choose something to put on this day")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ForgeTheme.separator)
                .frame(height: 0.5)
        }
    }

    /// One dot under a date, and what it is allowed to mean.
    ///
    /// A planner is asked two questions about a week and only two: *what have I
    /// kept*, and *what is already on*. So a day that was earned takes the
    /// accent, and a day that is merely planned takes a faint dot — which is the
    /// half this screen was missing. A future day used to draw nothing at all,
    /// so an empty Thursday and a Thursday with four things on it looked
    /// identical, and the one question somebody opens a planner to answer could
    /// not be answered from the strip.
    ///
    /// Dots rather than the bars this drew before, and one size for all of them.
    /// Bars of two widths under seven dates is a chart, and the brief for this
    /// screen has always been that it must not become one.
    @ViewBuilder
    private func mark(_ day: ForgeDay) -> some View {
        let isPastDay = day < progress.currentDay
        let earned = progress.byDay[day]?.isEarned == true

        Group {
            if earned {
                Circle().fill(ForgeTheme.accent)
            } else if isPastDay {
                Circle().fill(.secondary.opacity(0.22))
            } else if !vm.rituals(onWeekday: day.weekday).isEmpty {
                Circle().fill(.secondary.opacity(0.55))
            } else {
                Color.clear
            }
        }
        .frame(width: 4, height: 4)
    }

    // MARK: - The day itself

    /// The day itself, and the only thing on this screen that scrolls.
    ///
    /// **Nothing here hands the panel a gesture, and that is the fix.** The day
    /// list shares its scroll with the panel — hauling it past its own top
    /// collapses the sheet — and on a list of three activities that is a fair
    /// trade. On a planner it is not: a week's worth of a day is long, the
    /// flick that reaches the top of it overshoots by more than any threshold
    /// worth setting, and the panel would shut under somebody who was only
    /// scrolling. So the timeline just scrolls, always, and the panel is moved
    /// from the grip band above it — which in this screen is three rows tall and
    /// impossible to miss.
    private var timeline: some View {
        ScrollView {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyDay
                } else {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        // Always, rather than `.basedOnSize`: a short day should still feel like
        // a surface that moves under the finger rather than a slab.
        .scrollBounceBehavior(.always)
        // Whatever the viewport cuts off dissolves rather than ending on a hard
        // edge — the same mask the day list carries. Without it a long day
        // ended on a row sliced in half against the glass, which reads as a
        // clipped row rather than as "there is more". Ten activities is where
        // it starts showing, and ten activities is not a rare day.
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
            }
        }
    }

    /// One row of somebody's day.
    struct Item: Identifiable {
        let ritual: Ritual
        let isDone: Bool
        var id: String { ritual.id }
    }

    /// What the open day holds.
    ///
    /// A day already lived is read out of the record — what it was planned to be
    /// and what was finished — because today's routine is not a description of
    /// last Tuesday. Today and everything after it come from the arrangement,
    /// which is the thing this screen edits.
    private var items: [Item] {
        if isPast {
            guard let record = progress.byDay[openDay] else { return [] }
            let done = record.completedIDs
            return Ritual.chronological(record.plannedIDs.compactMap { vm.ritual($0) })
                .map { Item(ritual: $0, isDone: done.contains($0.id)) }
        }
        return vm.rituals(onWeekday: openDay.weekday).map {
            Item(ritual: $0, isDone: openDay == progress.currentDay && vm.isDone($0.id))
        }
    }

    /// One row, and the swipe that takes it off this day.
    ///
    /// The swipe was left out of this screen once, on the grounds that a swipe
    /// inside a draggable panel is two gestures fighting for one finger. That
    /// was true of the version that existed then; `SwipeToDelete` settles the
    /// fight by taking priority over the row and leaving the scroll view alone,
    /// and it is the same gesture on the same kind of row in the day panel — so
    /// having it in one list and not the other was the worse inconsistency.
    ///
    /// It removes the activity **from this day**, which is the only thing the
    /// word can honestly mean on a screen showing one day: something that also
    /// happens on Tuesday keeps Tuesday. See `ForgeViewModel.removeFromDay`.
    ///
    /// A day already lived has no swipe. Editing the record of a past Tuesday is
    /// not a thing this screen does.
    @ViewBuilder
    private func row(_ item: Item) -> some View {
        if isPast {
            rowBody(item)
        } else {
            SwipeToDelete(id: item.id, openID: $swipedID) {
                vm.removeFromDay(item.ritual.id, weekday: openDay.weekday)
            } content: {
                rowBody(item)
            }
        }
    }

    private func rowBody(_ item: Item) -> some View {
        Button {
            guard !isPast else { return }
            ForgeHaptics.shared.tap()
            editing = item.ritual
        } label: {
            HStack(spacing: 12) {
                Text(item.ritual.startMinute.map(ClockMinute.label) ?? "—")
                    .font(ForgeTheme.mono(11, weight: .semibold))
                    .foregroundStyle(item.isDone ? .tertiary : .secondary)
                    .frame(width: 58, alignment: .leading)

                RitualGlyph(ritual: item.ritual, size: 17, color: item.isDone ? .secondary : .primary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.ritual.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .strikethrough(item.isDone, color: .secondary)
                        .lineLimit(1)

                    if let length = ClockMinute.duration(item.ritual.minutes) {
                        Text(length)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                if item.isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForgeTheme.accent)
                } else if !isPast {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isPast)
        .contextMenu { if !isPast { menu(item.ritual) } }
        .accessibilityLabel(Text(item.ritual.label))
        .accessibilityValue(Text(spokenRow(item)))
        .accessibilityHint(Text(isPast ? "" : "Opens this activity"))
    }

    /// Everything that can be done to a row without opening it.
    ///
    /// A context menu rather than swipe actions, and deliberately: swipe on a
    /// row inside a panel that is itself draggable is two gestures fighting for
    /// the same finger, and the one that loses is the one the panel needs.
    @ViewBuilder
    private func menu(_ ritual: Ritual) -> some View {
        Button("Edit", systemImage: "slider.horizontal.3") { editing = ritual }

        Menu("Move to", systemImage: "arrow.turn.up.right") {
            ForEach(Self.weekOrder, id: \.self) { weekday in
                Button(Self.weekdayName(weekday)) {
                    vm.moveActivity(ritual.id, from: openDay.weekday, to: weekday)
                }
                .disabled(weekday == openDay.weekday)
            }
        }

        // Only where it is honest: an activity that only happens today would be
        // removed from the week entirely, and that is the other button.
        if ritual.repeats.weekdays.count > 1 {
            Button("Not on \(Self.weekdayName(openDay.weekday))", systemImage: "minus.circle") {
                vm.setWeekday(ritual.id, openDay.weekday, on: false)
            }
        }

        Divider()

        Button("Remove from my week", systemImage: "trash", role: .destructive) {
            vm.removeRitual(ritual.id)
        }
    }

    /// A day with nothing on it.
    ///
    /// This used to be two lines of grey text pointing at a `+` in the corner,
    /// which is the shape of an empty state that has given up: it named the
    /// affordance instead of being one, and the commonest thing anybody does
    /// with an empty Thursday — make it like a day they have already thought
    /// about — was not offered at all.
    ///
    /// So it is a mark, a sentence and two buttons, in the order of how likely
    /// each is to be what somebody wants. **Copy** is second rather than hidden
    /// because it is the fastest way a week ever gets filled, and it is the one
    /// action here that a new user would not think of on their own.
    ///
    /// A day already lived says one thing and offers nothing. There is no
    /// planning to be done in a Tuesday that has been and gone.
    @ViewBuilder
    private var emptyDay: some View {
        if isPast {
            Text("Nothing recorded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
        } else {
            VStack(spacing: 0) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Text("\(Self.weekdayName(openDay.weekday)) is open.")
                    .font(.headline)
                    .padding(.top, 14)

                Text("A day off is a decision too.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                Button {
                    ForgeHaptics.shared.tap()
                    isAdding = true
                } label: {
                    Text("Add something")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 40)
                        .padding(.horizontal, 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(ForgeTheme.cream)
                .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
                .padding(.top, 20)

                // Offered only when there is a day worth copying. On a week with
                // nothing in it anywhere this is a button that can do nothing,
                // and the empty state should never contain one of those.
                if hasAnythingToCopy {
                    Button {
                        ForgeHaptics.shared.tap()
                        copying = .incoming
                    } label: {
                        Text("Copy another day here")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 36)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ForgeTheme.accent)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            // Weighted downward rather than centred: the planner opens tall, and
            // a fixed centre would put this halfway down a screen it does not
            // know the height of. This sits under the day it belongs to at
            // either detent.
            .padding(.top, 38)
            .padding(.bottom, 26)
        }
    }

    /// Whether any other day of the week holds something.
    private var hasAnythingToCopy: Bool {
        Self.weekOrder.contains { $0 != openDay.weekday && !vm.rituals(onWeekday: $0).isEmpty }
    }

    // MARK: - Editing

    private func composer(for ritual: Ritual) -> some View {
        NavigationStack {
            ActivityComposer(
                mode: .edit(id: ritual.id, draft: ritual.draft),
                suggest: { name, symbol in vm.suggestedVerification(name: name, symbol: symbol) },
                onCommit: { vm.editRitual(ritual.id, to: $0) },
                destructive: ritual.isCustom
                    ? .delete { vm.deleteCustomRitual(ritual.id) }
                    : (vm.isEdited(ritual.id) ? .reset { vm.resetRitual(ritual.id) } : nil)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editing = nil }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
    }

    // MARK: - Words

    /// Monday first, matching `RitualRepeat.label` and the rest of the app.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    private static func initial(_ day: ForgeDay) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = day.weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private static func spoken(_ day: ForgeDay, isToday: Bool) -> String {
        let name = weekdayName(day.weekday)
        return isToday ? "\(name) the \(day.day), today" : "\(name) the \(day.day)"
    }

    private func spokenState(_ day: ForgeDay, record: DayRecord?) -> String {
        if day > progress.currentDay { return "Not yet" }
        if record?.isEarned == true { return "Kept" }
        if day == progress.currentDay { return "Today, not finished" }
        return "Not kept"
    }

    private func spokenRow(_ item: Item) -> String {
        var parts: [String] = []
        if let start = item.ritual.startMinute { parts.append(ClockMinute.label(start)) }
        if let length = ClockMinute.duration(item.ritual.minutes) { parts.append(length) }
        parts.append(item.isDone ? "Done" : (isPast ? "Not done" : "Planned"))
        return parts.joined(separator: ", ")
    }

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

// MARK: - Copying a day

/// Pick a day, see what it would do, do it.
///
/// # Why this is a screen and not two menus
///
/// The flow is three decisions — copy, which day, yes — and the tempting way to
/// build it is a menu of seven weekdays followed by a confirmation dialog. That
/// version was rejected for one reason: at the moment somebody picks Thursday
/// they cannot see what Thursday already holds, so the confirmation is asking
/// them to agree to something they have not been shown. A list can carry that.
/// Every row says what is on that day, the button underneath says exactly what
/// pressing it will add and to which day, and nothing is confirmed twice.
///
/// # What it will not do
///
/// It cannot overwrite. Copying adds what is missing and touches nothing else —
/// see `ForgeViewModel.copyDay` — so the worst case is a day with more on it
/// than somebody meant, every row of which comes back off with one swipe. That
/// is what makes the single button honest: there is no version of pressing it
/// that loses work, which is why it is a button and not a warning.
struct CopyDaySheet: View {
    @Bindable var vm: ForgeViewModel
    /// The weekday the sheet was opened from: the source when copying out of it,
    /// the destination when copying into it.
    let anchor: Int
    let direction: WeekPlannerView.CopyDirection
    /// Which weekday ended up holding the copy, so the planner can show it.
    var onCopied: (Int) -> Void

    /// Where the activities are being taken from.
    ///
    /// # Why this is a control on one sheet and not a second sheet
    ///
    /// There are two honest answers to "fill this day from something I have
    /// already thought about", and they are genuinely different questions rather
    /// than two routes to one:
    ///
    /// - **A weekday** is the *arrangement* — what Tuesday is supposed to be.
    ///   It exists whether or not a Tuesday has ever been lived, which is what
    ///   makes it the right source inside the planner.
    /// - **A day** is the *record* — what the 26th actually held, read off
    ///   `DayRecord.plannedIDs`. It is the better source when somebody
    ///   remembers a good day rather than a rule.
    ///
    /// Shipping the second as its own button would have put two copy controls on
    /// a screen whose whole problem was already that copying was hard to find.
    /// One door, two sources, and the segment says which is which.
    ///
    /// Only offered when filling a day in. Copying a weekday *out* to another
    /// weekday is an edit to the arrangement, and "copy last Tuesday out to
    /// Thursday" is not a thing anybody means.
    enum Source: String, CaseIterable, Identifiable {
        case weekday, recent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekday: "Weekdays"
            case .recent: "Recent days"
            }
        }
    }

    @State private var source: Source = .weekday
    @State private var chosen: Int?
    @State private var chosenDay: ForgeDay?
    @Environment(\.dismiss) private var dismiss

    /// The record, taken once per appearance rather than on every redraw.
    @State private var past: [ForgeViewModel.PastDay] = []

    /// Whether the record is worth offering at all. A first week has nothing in
    /// it, and a segmented control with one empty half is a control that
    /// advertises an empty room.
    private var offersRecord: Bool {
        direction == .incoming && !past.isEmpty
    }

    private var destination: Int? {
        direction == .out ? chosen : anchor
    }

    /// What pressing the button would actually add, whichever source is open.
    private var addition: [Ritual] {
        switch source {
        case .weekday:
            guard let from = self.source(from: chosen), let destination else { return [] }
            return vm.dayCopyAddition(from: from, to: destination)
        case .recent:
            guard let chosenDay, let day = past.first(where: { $0.day == chosenDay })
            else { return [] }
            return vm.pastDayAddition(day, to: anchor)
        }
    }

    /// Disambiguates the weekday source from the `Source` case of the same name.
    private func source(from chosen: Int?) -> Int? {
        direction == .out ? anchor : chosen
    }

    private var others: [Int] {
        WeekPlannerView.weekOrder.filter { $0 != anchor }
    }

    var body: some View {
        NavigationStack {
            List {
                if offersRecord {
                    Section {
                        Picker("From", selection: $source) {
                            ForEach(Source.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                }

                switch source {
                case .weekday:
                    ForEach(others, id: \.self) { weekday in
                        dayRow(weekday)
                    }
                case .recent:
                    Section {
                        ForEach(past) { day in
                            pastRow(day)
                        }
                    } footer: {
                        Text("What each day actually held. Reusing one puts those activities on \(WeekPlannerView.weekdayName(anchor)) as well — nothing that already happened is changed.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear { past = vm.recentDays() }
            .scrollIndicators(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        // Medium first: seven rows and a button need about half a screen, and a
        // sheet that opens taller than its content reads as a screen somebody
        // has been sent to rather than a decision they are making.
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        direction == .out
            ? "Copy \(WeekPlannerView.weekdayName(anchor))"
            : "Fill \(WeekPlannerView.weekdayName(anchor))"
    }

    // MARK: - One day out of the record

    /// A day that happened, said in the two facts that decide whether anybody
    /// wants it back: what it held, and how much of it they kept.
    ///
    /// Deliberately no verdict and no colour on the count. A day where three of
    /// six were done is not a bad day being offered back — it is very often the
    /// most useful row here, because it is the day somebody planned well and ran
    /// out of time on.
    private func pastRow(_ day: ForgeViewModel.PastDay) -> some View {
        let isChosen = chosenDay == day.day

        return Button {
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { chosenDay = day.day }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Self.dayTitle(day.day))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        // The blade came out on this one. A mark rather than a
                        // word: it is a fact about the day, not a rating of it.
                        if day.isEarned {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(ForgeTheme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(Self.pastSummary(day))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ForgeTheme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.dayTitle(day.day)))
        .accessibilityValue(Text(
            day.isEarned
                ? "\(Self.pastSummary(day)). Earned."
                : Self.pastSummary(day)
        ))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// "Tuesday, 26 August". The weekday is what people actually navigate by.
    private static func dayTitle(_ day: ForgeDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day)
        ) else { return "" }
        return dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    /// "5 activities · four kept". Numbers as words below a hundred, like
    /// everywhere else Forge says a count to somebody.
    private static func pastSummary(_ day: ForgeViewModel.PastDay) -> String {
        let count = day.activities.count == 1 ? "1 activity" : "\(day.activities.count) activities"
        guard day.keptCount > 0 else { return "\(count) · none kept" }
        return "\(count) · \(ForgeCount.spelled(day.keptCount)) kept"
    }

    // MARK: - The seven

    private func dayRow(_ weekday: Int) -> some View {
        let held = vm.rituals(onWeekday: weekday)
        let isChosen = chosen == weekday

        return Button {
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { chosen = weekday }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeekPlannerView.weekdayName(weekday))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    // What is on that day, said before anybody commits to it.
                    Text(held.isEmpty ? "Empty" : summary(held))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ForgeTheme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(WeekPlannerView.weekdayName(weekday)))
        .accessibilityValue(Text(held.isEmpty ? "Empty" : summary(held)))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// "3 activities · Work, Gym, Read", cut to what a line can hold.
    private func summary(_ rituals: [Ritual]) -> String {
        let count = rituals.count == 1 ? "1 activity" : "\(rituals.count) activities"
        let names = rituals.prefix(3).map(\.label).joined(separator: ", ")
        return rituals.count > 3 ? "\(count) · \(names)…" : "\(count) · \(names)"
    }

    // MARK: - What it will do

    private var explanation: String {
        switch source {
        case .weekday: return weekdayExplanation
        case .recent: return recentExplanation
        }
    }

    private var weekdayExplanation: String {
        guard chosen != nil else {
            return direction == .out
                ? "Choose the day that should also have \(WeekPlannerView.weekdayName(anchor))'s activities."
                : "Choose the day to copy into \(WeekPlannerView.weekdayName(anchor))."
        }
        guard let from = source(from: chosen), let destination else { return "" }
        guard !addition.isEmpty else {
            return vm.rituals(onWeekday: from).isEmpty
                ? "\(WeekPlannerView.weekdayName(from)) has nothing on it yet."
                : "\(WeekPlannerView.weekdayName(destination)) already has all of it."
        }
        let count = addition.count == 1 ? "1 activity" : "\(addition.count) activities"
        return "\(WeekPlannerView.weekdayName(destination)) gets \(count), at the same times. "
            + "\(WeekPlannerView.weekdayName(from)) keeps everything."
    }

    private var recentExplanation: String {
        guard chosenDay != nil else {
            return "Choose a day you have already lived. Its activities come back onto \(WeekPlannerView.weekdayName(anchor))."
        }
        guard !addition.isEmpty else {
            return "\(WeekPlannerView.weekdayName(anchor)) already has all of it."
        }
        let count = addition.count == 1 ? "1 activity" : "\(addition.count) activities"
        return "\(WeekPlannerView.weekdayName(anchor)) gets \(count), at the same times."
    }

    /// The sentence and the button that carries it out, together at the foot of
    /// the sheet.
    ///
    /// The sentence started as the list's own footer and that was wrong twice
    /// over: at the medium detent it sat below the seventh row and off the
    /// screen, so the one line explaining what the button does was the one line
    /// nobody could see — and even in view it was a caption under a list rather
    /// than a label on an action. Anything that describes what pressing a button
    /// will do belongs against the button.
    private var footer: some View {
        VStack(spacing: 12) {
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .animation(.forgeFade, value: explanation)

            confirmButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // So the rows scrolling underneath do not read through the sentence.
        .background(.bar)
    }

    private var confirmButton: some View {
        Button(action: copy) {
            Text(buttonTitle)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(ForgeTheme.cream)
        .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
        .disabled(addition.isEmpty)
    }

    /// The button says the whole sentence, so nothing has to be remembered from
    /// the row above it.
    private var buttonTitle: String {
        switch source {
        case .weekday:
            guard let from = source(from: chosen), let destination else { return "Copy" }
            return direction == .out
                ? "Copy to \(WeekPlannerView.weekdayName(destination))"
                : "Copy \(WeekPlannerView.weekdayName(from)) here"
        case .recent:
            return "Reuse this day"
        }
    }

    private func copy() {
        guard !addition.isEmpty else { return }
        switch source {
        case .weekday:
            guard let from = source(from: chosen), let destination else { return }
            ForgeHaptics.shared.ritualVerified()
            vm.copyDay(from: from, to: destination)
            onCopied(destination)
        case .recent:
            guard let chosenDay, let day = past.first(where: { $0.day == chosenDay })
            else { return }
            ForgeHaptics.shared.ritualVerified()
            vm.copyPastDay(day, to: anchor)
            onCopied(anchor)
        }
        dismiss()
    }
}
