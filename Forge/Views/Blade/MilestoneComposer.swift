import SwiftUI

/// Setting yourself a marker.
///
/// Four questions and a name, in the order somebody thinks of them: what am I
/// counting, how many, what do I call it. The name is last and pre-filled,
/// because "Read 30 days" is exactly what somebody would have typed and making
/// them type it is the step that stops people bothering.
///
/// Nothing here is a goal in the productivity sense. There is no deadline
/// field, no reminder, no "you are behind" — a milestone that could be *late*
/// would be one more thing to fail at, on the screen that exists to show
/// somebody how far they have actually come.
struct MilestoneComposer: View {
    /// `Identifiable` so the sheet can be driven by "which milestone", which is
    /// the only state there is — a separate `isPresented` beside it would be a
    /// second answer to the same question and one of the two would go stale.
    enum Mode: Equatable, Identifiable {
        case create
        case edit(id: String)

        var id: String {
            switch self {
            case .create: "new"
            case let .edit(id): id
            }
        }
    }

    let mode: Mode
    /// Every activity a milestone could be about, in the user's own words.
    let subjects: [(id: String, name: String)]
    let onCommit: (MilestoneDraft) -> Void
    var onDelete: (() -> Void)?

    @State private var draft: MilestoneDraft
    /// Whether the name has been typed in. Until it has, it follows whatever
    /// the milestone is being built out of — see `suggestedName`.
    @State private var nameIsMine: Bool
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode,
        draft: MilestoneDraft = .blank(),
        subjects: [(id: String, name: String)],
        onCommit: @escaping (MilestoneDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.subjects = subjects
        self.onCommit = onCommit
        self.onDelete = onDelete
        _draft = State(initialValue: draft)
        // An existing one has a name somebody settled on. Re-deriving it
        // because they nudged the target would be the app overwriting a
        // decision that has already been made.
        _nameIsMine = State(initialValue: mode != .create)
    }

    private var isEditing: Bool { mode != .create }

    private var subjectName: String? {
        draft.subject.activityID.flatMap { id in subjects.first { $0.id == id }?.name }
    }

    private var suggestedName: String {
        CustomMilestone.suggestedName(
            target: draft.target, unit: draft.unit, activityName: subjectName
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                subjectSection
                targetSection
                nameSection
                if isEditing { deleteSection }
            }
            .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit).fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    // MARK: - What it counts

    private var subjectSection: some View {
        Section {
            preview
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Picker(selection: subjectBinding) {
                Text("Days kept").tag("")
                ForEach(subjects, id: \.id) { subject in
                    Text(subject.name).tag(subject.id)
                }
            } label: {
                Text("Count")
            }

            NavigationLink {
                IconPickerView(selection: $draft.symbol)
            } label: {
                LabeledContent {
                    Image(systemName: draft.symbol)
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                } label: {
                    Text("Icon")
                }
            }
            .accessibilityLabel("Icon")
        } footer: {
            Text(draft.subject == .daysKept
                 ? "Whole days you earned, however they were made up."
                 : "Days you finished this one. It counts once a day, however many times you did it.")
        }
    }

    /// The picker speaks in ids, and the empty string stands for the day itself
    /// — a tag has to be one type, and `MilestoneSubject` is not `Hashable` in a
    /// way a `Picker` tag can carry without wrapping every row.
    private var subjectBinding: Binding<String> {
        Binding(
            get: { draft.subject.activityID ?? "" },
            set: { id in
                draft.subject = id.isEmpty ? .daysKept : .activity(id)
                // Counting a different thing changes what the milestone is, so
                // an untouched name follows it.
                syncName()
            }
        )
    }

    // MARK: - How many

    /// A stepper and a row of the numbers people actually pick.
    ///
    /// The chips are there for the same reason the duration chips are on the
    /// activity composer: thirty is the answer nine times in ten, and reaching
    /// it by holding a stepper for twenty-nine taps is the kind of thing that
    /// makes a feature go unused.
    private var targetSection: some View {
        Section {
            Stepper(value: $draft.target, in: CustomMilestone.targetRange) {
                LabeledContent("How many") {
                    Text(draft.unit.phrase(draft.target))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .onChange(of: draft.target) { _, _ in syncName() }

            ScrollView(.horizontal) {
                HStack(spacing: ForgeTheme.Space.tight) {
                    ForEach(Self.commonTargets, id: \.self) { target in
                        targetChip(target)
                    }
                }
                .padding(.vertical, ForgeTheme.Space.hair)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))

            Picker(selection: $draft.unit) {
                ForEach(MilestoneUnit.allCases) { unit in
                    Text(unit.plural.capitalized).tag(unit)
                }
            } label: {
                Text("Called")
            }
            .onChange(of: draft.unit) { _, _ in syncName() }
        } header: {
            Text("Target")
        } footer: {
            // Said plainly, because the three words mean the same arithmetic and
            // somebody choosing between them deserves to know that rather than
            // wonder which one counts differently.
            Text("Days, times and sessions all count the same thing — pick whichever sounds like you.")
        }
        .animation(.forgeSelection, value: draft.target)
    }

    private static let commonTargets = [7, 21, 30, 50, 100, 180, 365]

    private func targetChip(_ target: Int) -> some View {
        let isSelected = draft.target == target
        return Button {
            ForgeHaptics.shared.detent()
            draft.target = target
        } label: {
            Text("\(target)")
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .monospacedDigit()
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color(red: 0.063, green: 0.063, blue: 0.078) : .primary)
        .background {
            Capsule().fill(isSelected ? AnyShapeStyle(ForgeTheme.cream) : AnyShapeStyle(.quaternary))
        }
        .accessibilityLabel(draft.unit.phrase(target))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - What it is called

    private var nameSection: some View {
        Section {
            TextField(suggestedName, text: $draft.name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: draft.name) { _, typed in
                    // Clearing it hands the name back to the suggestion rather
                    // than leaving a blank one, so there is no way to end up
                    // with an unnamed row.
                    nameIsMine = !typed.trimmingCharacters(in: .whitespaces).isEmpty
                }
                .accessibilityLabel("Milestone name")
        } header: {
            Text("Name")
        } footer: {
            Text("Leave it and Forge will call it “\(suggestedName)”.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("Delete Milestone").frame(maxWidth: .infinity)
            }
            .confirmationDialog(
                "Delete this milestone?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Milestone", role: .destructive) {
                    ForgeHaptics.shared.bottomOut()
                    onDelete?()
                    dismiss()
                }
            } message: {
                // Worth saying: nothing about the practice is being deleted,
                // only the marker, and somebody hesitating over this button is
                // usually hesitating over exactly that.
                Text("The days you kept are untouched. Only the marker goes.")
            }
        }
    }

    // MARK: - The preview

    /// What the row will say, at the size it deserves while it is the only
    /// thing on screen. The same idea as the activity composer's preview, and
    /// for the same reason: a form of five rows is hard to picture as a card.
    private var preview: some View {
        VStack(spacing: ForgeTheme.Space.inner) {
            Image(systemName: draft.symbol)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.34, dampingFraction: 0.7), value: draft.symbol)

            VStack(spacing: ForgeTheme.Space.hair) {
                Text(draft.trimmedName.isEmpty ? suggestedName : draft.trimmedName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(subjectName ?? "Days kept")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .animation(.forgeSelection, value: suggestedName)
        }
        .padding(.vertical, ForgeTheme.Space.inner)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue(draft.trimmedName.isEmpty ? suggestedName : draft.trimmedName)
    }

    // MARK: - Commit

    /// Keeps an untouched name tracking whatever the milestone is being built
    /// out of, so the field reads as a live description rather than as a box to
    /// fill in.
    private func syncName() {
        guard !nameIsMine else { return }
        draft.name = ""
    }

    private func commit() {
        var outgoing = draft
        // The suggestion is resolved here rather than stored blank, so what is
        // saved is what the screen was showing.
        if outgoing.trimmedName.isEmpty { outgoing.name = suggestedName }
        ForgeHaptics.shared.tap()
        onCommit(outgoing)
        dismiss()
    }
}
