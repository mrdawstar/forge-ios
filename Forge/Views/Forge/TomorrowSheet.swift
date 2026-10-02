import SwiftUI

/// Tomorrow, looked at the night before.
///
/// The whole of it is: here is what tomorrow is, change it if you want to, say
/// yes. Nothing on this screen asks anybody to promise they will finish, and
/// nothing here will be brought up again if they do not — a day that gets
/// missed is a day that gets missed, and this screen has no memory of ever
/// having been visited.
///
/// It edits `activeRitualIDs` directly, which is the real day. There is no
/// draft to apply and nothing to discard: reordering a row reorders tomorrow the
/// moment the finger comes off it, and the button at the foot is not a save, it
/// is the deliberate act of saying so.
struct TomorrowSheet: View {
    @Bindable var vm: ForgeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.activeRitualIDs.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Tomorrow")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                // The screen used to be held in edit mode permanently, and edit
                // mode is precisely the state in which a `List` stops passing
                // taps through to its rows: every `NavigationLink` on it was
                // inert. "Swap something in" did nothing at all, and there was
                // no way to open an activity to change it.
                //
                // So the list is left alone and reordering asks for itself, the
                // way it does in Reminders. Tapping a row opens it, swiping a
                // row removes it, and Edit puts the handles and the minuses up
                // for anybody who wants to move things around.
                if !vm.activeRitualIDs.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
            .safeAreaInset(edge: .bottom) { commit }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var subtitle: String {
        vm.totalKept == 1 ? "1 activity" : "\(vm.totalKept) activities"
    }

    // MARK: - The list

    private var list: some View {
        List {
            Section {
                // Every row opens, which it did not before. The screen's whole
                // promise is "change it if you want to", and until now the only
                // changes it accepted were reordering and removal — the one
                // thing somebody looking at tomorrow actually wants to do,
                // which is move an activity half an hour later, needed the
                // other editor and a different day.
                ForEach(vm.activeRituals) { ritual in
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
                        TomorrowRow(ritual: ritual)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: remove)
            } footer: {
                Text("Tap one to change it. Swipe to take it out. Edit to reorder.")
            }

            Section {
                NavigationLink {
                    QuickAddView(vm: vm, isRoot: false)
                } label: {
                    Label("Swap something in", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Yet", systemImage: "sunrise")
        } description: {
            Text("Add what you want tomorrow to be made of.")
        } actions: {
            NavigationLink("Add an activity") { QuickAddView(vm: vm, isRoot: false) }
        }
    }

    // MARK: - The one tap

    /// One button, and it changes into a statement rather than disappearing.
    ///
    /// A control that vanishes on use leaves somebody wondering whether the tap
    /// landed. This says what is now true and stops being a button, which is the
    /// same answer without the doubt — and there is deliberately no way to un-set
    /// it, because taking it back is not a thing anybody needs to do to a
    /// day that has not happened yet.
    @ViewBuilder
    private var commit: some View {
        Group {
            if vm.isTomorrowSet {
                Label("Set for tomorrow", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            } else {
                Button {
                    ForgeHaptics.shared.ritualVerified()
                    vm.setTomorrow()
                    dismiss()
                } label: {
                    Text("Set for tomorrow")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(ForgeTheme.cream)
                .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
                .disabled(vm.activeRitualIDs.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .animation(.smooth(duration: 0.4), value: vm.isTomorrowSet)
    }

    // MARK: - Mutation

    private func move(from source: IndexSet, to destination: Int) {
        ForgeHaptics.shared.detent()
        withAnimation(.forgeRow) {
            vm.activeRitualIDs.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Ids are read before anything is removed, so a multi-row delete cannot
    /// index a list that has already shifted under it.
    private func remove(at offsets: IndexSet) {
        let ids = offsets.map { vm.activeRitualIDs[$0] }
        ForgeHaptics.shared.tap()
        withAnimation(.forgeRow) {
            for id in ids { vm.removeRitual(id) }
        }
    }
}

/// One activity as it will be tomorrow.
///
/// Quieter than the editor's row: this is a review, not a settings screen, so
/// the row says what the activity *is* rather than how it gets confirmed.
private struct TomorrowRow: View {
    let ritual: Ritual

    var body: some View {
        HStack(spacing: 14) {
            RitualGlyph(ritual: ritual, size: 20)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .rect(cornerRadius: ForgeTheme.Radius.glyph))

            VStack(alignment: .leading, spacing: 2) {
                Text(ritual.label)
                    .font(.body.weight(.medium))
                if !ritual.sub.isEmpty {
                    Text(ritual.sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
