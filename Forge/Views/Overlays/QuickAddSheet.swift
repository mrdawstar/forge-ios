import SwiftUI
import TipKit

/// QuickAdd: anything onto a day in one tap.
///
/// # What this replaces
///
/// The `+` on the Forge tab used to open "Your Day" — the editor — and adding
/// was a push from there into the library, a tap on a row, and the whole stack
/// closing behind it: three screens and a dismissal per activity, which made
/// adding the third thing as much work as adding the first. Adding is the
/// commonest change anybody makes to a day, so it is the `+` now, and it is one
/// tap: the row gets a check, a light haptic lands, a toast says "Added to
/// today · Undo", and the sheet stays open for the next one. Done closes it.
/// Editing the day moved to "Edit day" in the panel's ⋯ menu, and to a long
/// press on any row.
///
/// # It adds to a day, and the day is told to it
///
/// `weekday` is the day being filled, and every route through this screen
/// honours it: the week planner's `+` fills the day it is showing, and
/// somebody who has selected Thursday and picked "Read" means Thursday. Nil
/// means today, which is what every route from the Forge tab means.
///
/// # What every row is guaranteed to do (from `ActivityLibraryView`, which this replaces)
///
/// - **Something already in the week gains the day; it is never copied.** An
///   activity kept on Mondays is offered under "Already in your week" on every
///   other day, saying which days it runs on, and taking it adds Thursday and
///   leaves Monday exactly as it was (`ForgeViewModel.quickAdd`, `setWeekday`).
/// - **Something new lands on the day it was added from, and no other**
///   (`addRitual(_:onWeekday:)`, which pins it to that weekday unless it
///   already carries days somebody chose).
/// - **Nothing is ever duplicated.** One tap per row; a second tap on a row
///   already added does nothing, and an activity already on the day cannot be
///   added again.
/// - **Undo restores exactly.** The toast's Undo puts back the week as it was
///   the moment before that add — the list, the activities somebody made, the
///   edits to library activities and the day's parts (`WeekSnapshot`) — so an
///   add and its undo leave nothing behind, not even a pinned day.
///
/// # A search that finds nothing
///
/// Somebody who searched for a thing that is not here has already named it, so
/// the list offers "Create “name”" inline, which opens the composer with the
/// name in it, on this day, one tap from saved — and comes back here.
///
/// # Making one without searching first
///
/// "Create your own activity" sits right under Suggested for you whenever the
/// search is empty, so nobody has to find the no-results trick to learn that
/// they can. It is one quiet row, smaller than the activities around it, and it
/// opens the same composer on the same day, with the name left blank.
struct QuickAddSheet: View {
    @Bindable var vm: ForgeViewModel
    /// For the running Arc's gaps under "Suggested for you". Optional, so a
    /// screen without one still adds.
    var arcs: ArcStore?
    /// The day being filled. Nil is today.
    var weekday: Int?

    var body: some View {
        NavigationStack {
            QuickAddView(vm: vm, arcs: arcs, weekday: weekday)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}

/// QuickAdd's content, for the sheet above and for the two screens that push
/// it inside their own navigation (the day editor and the evening's Tomorrow).
struct QuickAddView: View {
    @Bindable var vm: ForgeViewModel
    var arcs: ArcStore?
    var weekday: Int?
    /// Whether this is the sheet's root, which owns the Done. Pushed, the back
    /// button is the way out.
    var isRoot = true

    @State private var catalog: QuickAddCatalog?
    @State private var query = ""
    @State private var category: RitualCategory = .all
    /// Ids added in this visit — the rows that carry a check.
    @State private var added: Set<String> = []
    @State private var toast: Toast?
    @State private var creatingNamed: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The last add, and how to put it back.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let ritualID: String
        let text: String
        let snapshot: ForgeViewModel.WeekSnapshot
    }

    /// The day everything here lands on.
    private var target: Int { weekday ?? vm.progress.currentDay.weekday }

    private var dayName: String {
        target == vm.progress.currentDay.weekday ? "today" : WeekPlannerView.weekdayName(target)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // The toast sits under the list, and the list's touches end where the
        // list does. Without `contentShape`, a row scrolled out of sight below
        // the list's frame still took a tap at its old place — on the iOS 26.5
        // Simulator a tap anywhere on the toast landed on the row behind it
        // and *added* that one, whether the toast was over the list (a ZStack,
        // an overlay, a bottom inset) or under it. The frames were right; the
        // hit area was not. `clipped` keeps the drawing to the same edge.
        VStack(spacing: 0) {
            list
                .clipped()
                .contentShape(.rect)
            toastBar
        }
        .animation(reduceMotion ? nil : .forgeFade, value: toast?.id)
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(weekday == nil ? "Add to Today" : "Add to \(WeekPlannerView.weekdayName(target))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search activities")
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if trimmedQuery.isEmpty { chips }
        }
        .navigationDestination(item: $creatingNamed) { name in composer(name) }
        .onAppear {
            // Read once, when the sheet opens — see `QuickAddCatalog`.
            guard catalog == nil else { return }
            catalog = makeCatalog()
        }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.forgeFade) { toast = nil }
        }
    }

    private func makeCatalog() -> QuickAddCatalog {
        let running = arcs?.current
        return QuickAddCatalog.make(
            week: vm.activeRituals,
            library: vm.libraryRituals,
            unusedCustom: vm.unusedCustomRituals,
            weekday: target,
            weakest: vm.weakestDimension,
            arcGaps: arcs?.gaps ?? [],
            arcName: running?.program.name,
            find: vm.ritual
        )
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        List {
            if let catalog {
                ForEach(QuickAddCatalog.Section.allCases) { section in
                    let rows = catalog.rows(in: section, matching: query, category: category)
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row in
                                QuickAddRow(
                                    ritual: row.ritual,
                                    detail: row.detail,
                                    isAdded: added.contains(row.id),
                                    dayName: dayName
                                ) { add(row) }
                            }
                        } header: {
                            Text(section.title)
                        } footer: {
                            if section == .inWeek {
                                Text("These run on other days. Adding one puts it on \(dayName) as well — nothing else about it changes.")
                            }
                        }
                    }
                    // After the fast picks, before the rest: found without a
                    // search, and quieter than the rows it sits between.
                    if section == .suggested, trimmedQuery.isEmpty {
                        createOwn
                    }
                }

                if !trimmedQuery.isEmpty, catalog.isEmpty(matching: query, category: category) {
                    Section {
                        Button {
                            create(named: trimmedQuery)
                        } label: {
                            Label("Create \u{201C}\(trimmedQuery)\u{201D}", systemImage: "plus.circle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(ForgeTheme.accent)
                        }
                    } footer: {
                        Text("Nothing in the library is called that. Make it yours, on \(dayName).")
                    }
                } else if trimmedQuery.isEmpty, catalog.isEmpty(matching: "", category: category) {
                    Section {
                        Text(category == .all
                             ? "Everything here is already on \(dayName)."
                             : "Everything in \(category.label.lowercased()) is already on \(dayName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The way in to the composer that does not need a search first.
    private var createOwn: some View {
        Section {
            Button {
                create(named: "")
            } label: {
                Label("Create your own activity", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ForgeTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens a new activity for \(dayName)"))
        }
    }

    // MARK: - The chips

    /// All, then the six in the hexagon's order, each in its own colour. They
    /// narrow what is offered — Suggested and the library — and never what is
    /// already somebody's (`QuickAddCatalog.rows`).
    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 7) {
                HStack(spacing: 7) {
                    chip(.all)
                    ForEach(RitualCategory.dimensions, id: \.self) { chip($0) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ dimension: RitualCategory) -> some View {
        let isSelected = category == dimension
        let tint = dimension == .all ? ForgeTheme.cream : dimension.color
        return Button {
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { category = dimension }
        } label: {
            HStack(spacing: 5) {
                if dimension != .all {
                    Image(systemName: dimension.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(dimension.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .frame(minHeight: 34)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(tint.opacity(0.32)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .accessibilityLabel(Text(dimension == .all ? "All" : dimension.label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Adding

    private func add(_ row: QuickAddCatalog.Row) {
        guard !added.contains(row.id) else {
            ForgeHaptics.shared.detent()
            return
        }
        let before = vm.weekSnapshot
        switch vm.quickAdd(row.id, onWeekday: target) {
        case .added:
            ForgeTelemetry.send(.activityAdded(.library))
        case .dayAdded:
            break
        case .alreadyThere:
            // Already on the day: marked, never added a second time.
            added.insert(row.id)
            return
        }
        ForgeHaptics.shared.tap()
        AddTip().invalidate(reason: .actionPerformed)
        added.insert(row.id)
        withAnimation(.forgeFade) {
            toast = Toast(ritualID: row.id, text: "Added to \(dayName)", snapshot: before)
        }
    }

    private func undo(_ toast: Toast) {
        ForgeHaptics.shared.tap()
        vm.restore(toast.snapshot)
        added.remove(toast.ritualID)
        withAnimation(.forgeFade) { self.toast = nil }
    }

    // MARK: - The toast

    /// "Added to today · Undo", above the home indicator, for five seconds or
    /// until the next add replaces it. Only ever the last add: Undo puts back
    /// the week as it was just before it, and nothing older.
    ///
    /// The whole capsule is the button: a target the size of one word, on a
    /// toast that leaves on its own, is the wrong size.
    @ViewBuilder
    private var toastBar: some View {
        if let toast {
            Button { undo(toast) } label: {
                HStack(spacing: 10) {
                    // The check and the dot go at the accessibility sizes, so
                    // the two words that matter keep whole lines.
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ForgeTheme.accent)
                    }
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    if !typeSize.isAccessibilitySize {
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForgeTheme.accent)
                        .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 48)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            // Plain glass, not `.interactive()`: with the interactive kind a
            // tap on the toast went unanswered on the Simulator.
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            .accessibilityLabel(Text("\(toast.text). Undo"))
            .accessibilityHint(Text("Takes it off again"))
        }
    }

    // MARK: - Making one

    /// Both ways in — the row and a search that found nothing — open the one
    /// composer below, on this day.
    private func create(named name: String) {
        ForgeHaptics.shared.tap()
        creatingNamed = name
    }

    private func composer(_ name: String) -> some View {
        ActivityComposer(
            // The day being filled, and no other. See `ActivityComposer.Mode`.
            mode: .create(name: name, on: .onlyToday(target)),
            suggest: { name, symbol in vm.suggestedVerification(name: name, symbol: symbol) },
            onCommit: { draft in
                let before = vm.weekSnapshot
                let made = vm.createCustomRitual(draft)
                ForgeTelemetry.send(.activityAdded(.custom))
                ForgeHaptics.shared.ritualVerified()
                added.insert(made.id)
                query = ""
                withAnimation(.forgeFade) {
                    toast = Toast(ritualID: made.id, text: "Added to \(dayName)", snapshot: before)
                }
                // The composer pops itself, back to this list.
            }
        )
        .navigationSubtitle(WeekPlannerView.weekdayName(target))
    }
}

// MARK: - One row

/// One activity, one tap.
///
/// The act and its standard, the dimension it feeds as a glyph in that
/// dimension's colour, and a `+` that becomes a check once it is on the day.
/// A whole-row button: nothing about adding needs aiming.
struct QuickAddRow: View {
    let ritual: Ritual
    /// What this row says instead of the subtitle — the days it runs on, or
    /// why it is suggested.
    var detail: String?
    let isAdded: Bool
    /// "today", "Thursday" — for VoiceOver.
    let dayName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                RitualGlyph(ritual: ritual, size: 20)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: .rect(cornerRadius: ForgeTheme.Radius.glyph))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ritual.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    let line = detail ?? ritual.sub
                    if !line.isEmpty {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: ritual.category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ritual.category.color)
                    .accessibilityHidden(true)

                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .symbolRenderingMode(isAdded ? .palette : .monochrome)
                    .foregroundStyle(isAdded ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                                     ForgeTheme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(ritual.label), \(ritual.category.label)"))
        .accessibilityValue(Text(isAdded ? "Added to \(dayName)" : (detail ?? "")))
        .accessibilityHint(Text(isAdded ? "" : "Adds it to \(dayName)"))
    }
}
