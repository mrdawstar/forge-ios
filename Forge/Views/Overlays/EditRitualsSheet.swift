import SwiftUI

/// Everything "what is my day" in one place — reorder it, take things out
/// of it, rename what you made, put more in.
///
/// This is what the one `+` in the day header opens. Editing used to be a
/// second button below the list ("Reorder & remove") competing with a `+` that
/// went somewhere else; a day is one thing, so changing it is one door.
struct DayEditorSheet: View {
    @Bindable var vm: ForgeViewModel
    @Environment(\.dismiss) private var dismiss

    /// The movement being renamed, and the words so far.
    ///
    /// A rename alert rather than a pushed screen or an inline field: it is the
    /// pattern iOS already uses to rename a folder, a list or a shortcut, it
    /// costs no navigation, and it puts the keyboard where the eye already is.
    @State private var renaming: ShapedPart?
    @State private var draftName = ""

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.activeRitualIDs.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Your Day")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        ForgeHaptics.shared.tap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                // The list is no longer pinned open in edit mode. It was, and
                // edit mode is exactly the state in which a `List` swallows the
                // tap on a row — so the footer promised "Tap to edit" over rows
                // that could not be tapped, and the composer behind every one of
                // them was unreachable from this screen.
                if !vm.activeRitualIDs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .safeAreaInset(edge: .bottom) { addButton }
        }
        // Large and round, and only one detent: a sheet that resizes underneath
        // a row being dragged is a sheet fighting the drag.
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var subtitle: String {
        vm.totalKept == 1 ? "1 activity" : "\(vm.totalKept) activities"
    }

    // MARK: - List

    /// One section per movement, or one unnamed section for a day that has no
    /// shape — which is every day until somebody takes a routine, and stays that
    /// way forever for somebody who never does.
    private var list: some View {
        List {
            if vm.isDayShaped {
                ForEach(vm.dayParts) { part in
                    Section {
                        ForEach(part.activities) { ritual in
                            row(for: ritual, in: part)
                        }
                        // Local to the section, which is what `ForEach` reports
                        // and what `reorderPart` expects. Drag stays the gesture
                        // for *where in a movement* something sits.
                        .onMove { vm.reorderPart(part.id, from: $0, to: $1) }
                        .onDelete { remove(at: $0, in: part) }
                    } header: {
                        movementHeader(part)
                    } footer: {
                        if part.id == vm.dayParts.last?.id { Text(footerText) }
                    }
                }
            } else {
                Section {
                    // Native reorder and delete. Nothing hand-built comes close
                    // to the lift, the gap opening under the finger, or the drop.
                    ForEach(vm.activeRituals) { ritual in
                        row(for: ritual, in: nil)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                } footer: {
                    Text(footerText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .alert("Rename", isPresented: renamingBinding) {
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { vm.renamePart(renaming.id, to: draftName) }
                renaming = nil
            }
        } message: {
            Text("What do you call this part of your day?")
        }
    }

    /// The movement's name, and the only place a movement can be renamed.
    ///
    /// A context menu rather than a visible button, and rather than an
    /// always-live text field in the header. The reason is about prominence:
    /// "Before the world" is the world's language and a good deal of why the
    /// Path reads as a philosophy instead of a folder, so renaming it should be
    /// available to anyone who wants it and invisible to everyone who does not.
    /// A rename field sitting open in every header would be an invitation to
    /// flatten the poetry into "Morning".
    private func movementHeader(_ part: ShapedPart) -> some View {
        Text(part.name.isEmpty ? "Unnamed" : part.name)
            .foregroundStyle(part.name.isEmpty ? .tertiary : .secondary)
            .contextMenu {
                Button {
                    draftName = part.name
                    renaming = part
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            .accessibilityHint(Text("Touch and hold to rename"))
    }

    /// One sentence per gesture, and only the ones that are not already obvious
    /// from the affordance sitting next to them.
    ///
    /// The swipe is back, and it is back because it works again: holding the
    /// list in edit mode turned off both the swipe *and* the tap this copy has
    /// always promised. Copy that names a gesture the screen has turned off is
    /// worse than no copy — which is true of the version that named the minus,
    /// too, now that the minus only appears once Edit has been pressed.
    private var footerText: String {
        let base = "Tap one to change it. Swipe to take it out of your day. Edit to reorder."
        // Named only when there is somewhere to move to. A sentence describing a
        // gesture that does nothing is worse than no sentence, which is why the
        // promise of a left swipe came out of here in the first place.
        guard vm.isDayShaped else { return base }
        return base + " Hold one to move it to another part of your day, or hold a heading to rename it."
    }

    /// Every row drills in, whichever kind of activity it holds.
    ///
    /// Custom rows used to be the only editable ones, which left a list where
    /// some rows opened and some did nothing, with no way to tell them apart
    /// until you had already tapped. Nothing about "we shipped this one" is the
    /// user's problem — and wanting push-ups off the camera is at least as
    /// common as wanting to rename something you invented.
    /// Every row drills in, whichever kind of activity it holds — and, on a day
    /// with movements, carries the one interaction that moves it between them.
    ///
    /// **Why a context menu rather than dragging across sections.** Dragging is
    /// the right gesture for *where in a movement* a row sits, and it is used
    /// for exactly that. It is the wrong gesture for which movement a row
    /// belongs to, and the difference is what the user is actually thinking.
    /// Reordering is spatial — four rows down — and the finger is the natural
    /// instrument. Moving between movements is a reclassification: "I lift in
    /// the evening." Nothing about that thought is spatial, and expressing it by
    /// dragging a row across two section boundaries in a scrolling list, hunting
    /// for a target that may be off-screen, is the fiddliest thing this app
    /// would ask anybody to do.
    ///
    /// It is also what Apple does. A reminder is dragged to reorder it and moved
    /// between lists from a menu, and the reason is the same one: a long press
    /// and a tap is two gestures with no aim required, it works when the
    /// destination is nowhere near the finger, and it is the only version of
    /// this that VoiceOver and Switch Control can drive at all.
    private func row(for ritual: Ritual, in part: ShapedPart?) -> some View {
        NavigationLink {
            ActivityComposer(
                mode: .edit(id: ritual.id, draft: ritual.draft),
                suggest: { name, symbol in
                    vm.suggestedVerification(name: name, symbol: symbol)
                },
                onCommit: { vm.editRitual(ritual.id, to: $0) },
                destructive: ritual.isCustom
                    ? .delete { vm.deleteCustomRitual(ritual.id) }
                    : (vm.isEdited(ritual.id) ? .reset { vm.resetRitual(ritual.id) } : nil)
            )
        } label: {
            DayEditorRow(ritual: ritual)
        }
        .contextMenu { moveMenu(for: ritual, from: part) }
    }

    /// Where else this activity could go. Absent when there is nowhere else,
    /// which is every day that has no movements — so a menu never opens onto a
    /// single disabled item.
    @ViewBuilder
    private func moveMenu(for ritual: Ritual, from part: ShapedPart?) -> some View {
        if let part, vm.dayParts.count > 1 {
            // Flat buttons rather than a "Move to" submenu. With three
            // destinations a submenu costs an extra tap and a disclosure to save
            // one line of menu, and the destinations are the only thing in here.
            Section("Move to") {
                ForEach(vm.dayParts.filter { $0.id != part.id }) { destination in
                    Button {
                        ForgeHaptics.shared.detent()
                        vm.moveActivity(ritual.id, toPart: destination.id)
                    } label: {
                        Text(destination.name.isEmpty ? "Unnamed" : destination.name)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Yet", systemImage: "sunrise")
        } description: {
            Text("Add what you want your days to be made of.")
        }
    }

    private var addButton: some View {
        NavigationLink {
            ActivityLibraryView(vm: vm)
        } label: {
            Label("Add Activity", systemImage: "plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(ForgeTheme.cream)
        .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Mutation

    private func move(from source: IndexSet, to destination: Int) {
        ForgeHaptics.shared.detent()
        withAnimation(.forgeRow) {
            vm.activeRitualIDs.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Takes activities out of the day without destroying them — a library
    /// one goes back to the library, one the user made goes back to "Yours", and
    /// either is a tap away from returning. Nothing here needs confirming;
    /// throwing a custom activity away for good is asked about in the composer.
    ///
    /// Ids are read before anything is removed. Reading them one at a time out
    /// of the array being mutated meant a multi-row delete indexed a list that
    /// had already shifted under it.
    private func remove(at offsets: IndexSet) {
        remove(ids: offsets.map { vm.activeRitualIDs[$0] })
    }

    /// The same removal, from indices local to one movement's section.
    private func remove(at offsets: IndexSet, in part: ShapedPart) {
        remove(ids: offsets.compactMap { part.activities.indices.contains($0)
            ? part.activities[$0].id : nil })
    }

    private func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        ForgeHaptics.shared.tap()
        withAnimation(.forgeRow) {
            for id in ids { vm.removeRitual(id) }
        }
    }
}

/// One activity in the editor. Deliberately quieter than `RitualRowView` — here
/// the row is cargo being moved, not a thing to tick off.
private struct DayEditorRow: View {
    let ritual: Ritual

    var body: some View {
        HStack(spacing: 14) {
            RitualGlyph(ritual: ritual, size: 20)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .rect(cornerRadius: ForgeTheme.Radius.glyph))

            VStack(alignment: .leading, spacing: 2) {
                Text(ritual.label)
                    .font(.body.weight(.medium))
                // The settings, not the subtitle. In an editing context these
                // are what somebody came to change, and showing them here is
                // what makes the row worth tapping — a disclosure arrow on its
                // own never says what is behind it.
                //
                // Marked the same way as the picker and the day list. Three
                // lists of the same activities that disagreed about how to draw
                // them would be worse than none of them marking it at all.
                HStack(spacing: 4) {
                    VerificationMark(method: ritual.verification)
                    Text(settings)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Only the two states that mean something. "Normal" is the default
            // and the majority, and a badge on every ordinary row would make the
            // list louder without telling anybody anything.
            if let badge = ritual.priority.badge {
                Text(badge.uppercased())
                    .font(ForgeTheme.overline)
                    .kerning(0.6)
                    .foregroundStyle(
                        ritual.priority == .essential
                            ? AnyShapeStyle(ForgeTheme.accent)
                            : AnyShapeStyle(.tertiary)
                    )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Change the name, icon, duration, time, priority or how it's verified"))
    }

    /// What this activity is currently set to, in one line, most specific first.
    ///
    /// Verification is always last and always present, because it is the one
    /// setting every activity has — so the line ends the same way on every row
    /// and the eye can find it without reading the rest.
    private var settings: String {
        var parts: [String] = []
        if let schedule = ritual.scheduleLabel {
            parts.append(schedule)
        } else if let duration = ClockMinute.duration(ritual.minutes) {
            parts.append(duration)
        }
        if !ritual.repeats.isDaily { parts.append(ritual.repeats.label) }
        parts.append(ritual.verification.title)
        return parts.joined(separator: "  ·  ")
    }
}
