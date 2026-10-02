import SwiftUI

// The catalogue that used to open here — `ActivityLibraryView`, and
// `AddToDaySheet` around it — is QuickAdd since 1.1 (`QuickAddSheet`), with
// every guarantee its doc comments made carried over and written down there:
// the weekday is honoured, "Already in your week" adds the day instead of
// minting a copy, nothing is duplicated, and undo restores exactly. What is
// left in this file is making an activity and changing one.

// MARK: - Compose

/// Everything an activity can be told about itself.
///
/// It used to be three fields — a name, a mark and how it gets confirmed — and
/// three fields is what "the editing feels too basic" means. What was missing
/// was not more settings for their own sake; it was the answers to the questions
/// somebody actually has about their own day. How long is this. When do I do it.
/// What is it, in my words rather than ours. Does it happen on Sundays. Which of
/// these do I drop when the day falls apart.
///
/// The grouping is the design. Six sections in the order somebody fills them in
/// — what it is, how long, when, what counts as done, how often it matters, how
/// it is confirmed — and every one of them optional except the name. An activity
/// created by typing a name and pressing Add is exactly the activity this screen
/// made before any of this existed.
///
/// **Duration is the one that got a bespoke control.** It is the field people
/// touch most and it was a text box you typed "45" into. Now it is ten chips and
/// a wheel behind them, so three quarters of an hour is one tap.
struct ActivityComposer: View {
    /// How long a target is allowed to be.
    ///
    /// Room for "3 sets of 12 reps" and no room for a sentence. The day list
    /// puts this beside the activity's name on one line, and a target with no
    /// ceiling is a name with no space — the field stops accepting characters so
    /// that the row can never be the thing that discovers the limit.
    static let goalLimit = 20

    /// How long a note is allowed to be.
    ///
    /// Three lines at the default text size. This is a reminder to yourself
    /// about why the activity is on the list, not a journal — the journal is an
    /// activity you can add.
    static let noteLimit = 140

    enum Mode: Equatable {
        /// `name` prefills the field — what somebody searched the library for
        /// and did not find is already the name of the thing they wanted.
        ///
        /// `on` is which days it starts out repeating, and it is **one day**
        /// everywhere it is used. A brand new activity used to arrive as "every
        /// day", which is a commitment nobody made: somebody adding a dentist
        /// appointment on a Thursday had silently agreed to one every Thursday,
        /// Friday and Sunday too, and the only sign was a picker three sections
        /// down. Starting narrow means the day somebody was looking at is the
        /// day they get, and repeating is a thing they choose.
        case create(name: String, on: RitualRepeat)
        /// The activity, as it stands. One value rather than five arguments —
        /// see `ActivityDraft`.
        case edit(id: String, draft: ActivityDraft)
    }

    let mode: Mode
    /// Answers "how would this be verified" for a name-and-icon pair. Injected
    /// so the composer stays a view — the classifier and what the user has
    /// taught it live in the view model.
    let suggest: (String, String) -> VerificationMethod
    let onCommit: (ActivityDraft) -> Void
    /// The bottom action, which differs by what is being edited: something the
    /// user made can be thrown away, something we shipped can only be put back
    /// the way it was, and a brand new one has neither.
    var destructive: DestructiveAction? = nil

    enum DestructiveAction {
        case delete(() -> Void)
        case reset(() -> Void)
    }

    @State private var draft: ActivityDraft
    /// Once the user has said how they want this verified, the classifier stops
    /// talking. Nothing is more irritating than a field that argues back.
    @State private var userPickedVerification: Bool
    @State private var confirmingDelete = false
    /// Whether the duration wheel is showing under the chips. Closed by default,
    /// because the chips answer it nine times in ten.
    @State private var showingDurationWheel = false
    /// Which text field holds the caret.
    ///
    /// One enum rather than a `Bool` per field. The keyboard's own Done button
    /// needs a single thing to clear, and three booleans would mean three
    /// assignments — plus a fourth field silently not dismissing on the day
    /// somebody adds one.
    private enum Field: Hashable { case name, note, goal }
    @FocusState private var focus: Field?

    /// Whether the dimension has been chosen by hand. Stops the name-based guess
    /// overwriting a deliberate answer — the same rule, and the same reason, as
    /// `userPickedVerification`.
    @State private var userPickedCategory = false
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode,
        suggest: @escaping (String, String) -> VerificationMethod,
        onCommit: @escaping (ActivityDraft) -> Void,
        destructive: DestructiveAction? = nil
    ) {
        self.mode = mode
        self.suggest = suggest
        self.onCommit = onCommit
        self.destructive = destructive
        switch mode {
        case let .create(name, repeats):
            var seeded = ActivityDraft.blank(named: name)
            seeded.repeats = repeats
            _draft = State(initialValue: seeded)
            _userPickedVerification = State(initialValue: false)
        case let .edit(_, existing):
            _draft = State(initialValue: existing)
            // An existing activity's method is already settled; re-deciding it
            // because somebody fixed a typo would be the app changing its mind
            // about a choice the user already made.
            _userPickedVerification = State(initialValue: true)
        }
    }

    private var isEditing: Bool { if case .edit = mode { return true }; return false }

    private var canSave: Bool { !draft.trimmedLabel.isEmpty }

    /// A binding onto the start time as a `Date`, because that is what
    /// `DatePicker` speaks and minutes-since-midnight is what everything else
    /// does. The conversion lives here rather than in the model: a start time is
    /// a number of minutes, and only this one control has ever wanted a `Date`.
    private var startBinding: Binding<Date> {
        Binding(
            get: {
                let minute = draft.startMinute ?? ActivityDraft.defaultStartMinute
                var parts = DateComponents()
                parts.hour = minute / 60
                parts.minute = minute % 60
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.startMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var hasStartBinding: Binding<Bool> {
        Binding(
            get: { draft.startMinute != nil },
            set: { on in
                // Seven in the morning rather than now. An activity being given
                // a time for the first time is almost always part of a morning
                // somebody is designing, and offering them the current time
                // means the first thing they do is change it.
                draft.startMinute = on ? ActivityDraft.defaultStartMinute : nil
            }
        )
    }

    var body: some View {
        Form {
            identity
            dimensionSection
            durationSection
            timeSection
            goalSection
            treatmentSection
            verificationSection
            destructiveSection
        }
        .navigationTitle(isEditing ? "Edit Activity" : "New Activity")
        .navigationBarTitleDisplayMode(.inline)
        // Drag the form and the keyboard goes with it.
        //
        // Both text fields here are multi-line-capable and neither has anywhere
        // useful to send a Return, so there was no gesture that put the keyboard
        // away except tapping a control behind it — and the keyboard covers the
        // bottom two fifths, which on this form is Category, Priority, Repeat and
        // Verification. `.interactively` rather than `.immediately` because a
        // form is read while it is being filled in: an accidental scroll should
        // not dismiss the caret mid-sentence, and a deliberate downward drag
        // should.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add", action: commit)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
            // The explicit way out, above the keyboard, for the people who do
            // not discover the drag. It is not a second Save — dismissing the
            // caret and committing the activity are different intentions, and a
            // "Done" that silently did both would add activities somebody was
            // still writing.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .fontWeight(.medium)
            }
        }
        // The name is the only thing that has to be filled in, so the caret
        // starts there and the icon keeps a perfectly good default.
        .onAppear { if !isEditing { focus = .name } }
        // The suggestion settles a beat after typing stops rather than
        // flickering through three answers mid-word. `task(id:)` cancels the
        // pending guess on every keystroke, so only the pause produces one.
        .task(id: "\(draft.trimmedLabel)|\(draft.symbol)") {
            guard !draft.trimmedLabel.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if !userPickedVerification {
                draft.verification = suggest(draft.trimmedLabel, draft.symbol)
            }
            // Only ever moves a dimension nobody has chosen, and only to
            // something the name actually matched. A guess that fires on every
            // pause would drag a deliberate answer back on the next keystroke.
            if !userPickedCategory, isEditing == false,
               let guessed = Ritual.suggestedCategory(for: draft.trimmedLabel) {
                withAnimation(.forgeSelection) { draft.category = guessed }
            }
        }
    }

    // MARK: - What it is

    private var identity: some View {
        Group {
            Section {
                preview
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                TextField("Name", text: $draft.label)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focus, equals: .name)
                    .onSubmit(commit)
                    .accessibilityLabel("Activity name")

                // Vertical axis rather than a pushed screen. A note is a
                // sentence, and sending somebody to a second screen to write one
                // sentence is the reason nobody writes it.
                TextField("Description", text: $draft.note, axis: .vertical)
                    .font(.body)
                    .focused($focus, equals: .note)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: draft.note) { _, typed in
                        if typed.count > Self.noteLimit {
                            draft.note = String(typed.prefix(Self.noteLimit))
                        }
                    }
                    .accessibilityLabel("Description")

                NavigationLink {
                    IconPickerView(selection: $draft.symbol)
                } label: {
                    LabeledContent {
                        Image(systemName: draft.symbol)
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            // The mark changes under the label as a swap
                            // rather than a blink when you come back.
                            .contentTransition(.symbolEffect(.replace))
                    } label: {
                        Text("Icon")
                    }
                }
                .accessibilityLabel("Icon")
                .accessibilityValue(ActivityIcons.named(draft.symbol))
            } footer: {
                Text("The description is yours. It shows under the activity when you open it.")
            }
        }
    }

    // MARK: - How long

    /// Ten chips and a wheel, and the wheel is the fallback.
    ///
    /// The chips are the whole point of this screen's rebuild. Duration is the
    /// most-changed field in the app and it was a text box: to say
    /// three quarters of an hour somebody had to tap into a field, raise a
    /// number pad, type two digits and dismiss it. Now it is one tap, and the
    /// values are the ones people actually use rather than a uniform ramp.
    ///
    /// "Untimed" is a chip rather than an empty state, because it is a real
    /// answer — a made bed has no duration, and leaving the field blank should
    /// not be the only way to say so.
    private var durationSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: ForgeTheme.Space.tight) {
                    durationChip(label: "Untimed", minutes: 0)
                    ForEach(ClockMinute.commonDurations, id: \.self) { minutes in
                        durationChip(label: ClockMinute.duration(minutes) ?? "", minutes: minutes)
                    }
                }
                .padding(.vertical, ForgeTheme.Space.hair)
            }
            .scrollIndicators(.hidden)
            // The row's own inset is removed so the chips can run to the edge of
            // the card and read as a scrollable strip rather than a cut-off list.
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))

            // Behind a disclosure rather than always present: a wheel is 160pt
            // of screen to answer a question the chips above have already
            // answered, and it should cost a tap to see rather than a scroll to
            // get past.
            DisclosureGroup(isExpanded: $showingDurationWheel) {
                Picker("Minutes", selection: $draft.minutes) {
                    ForEach(Array(stride(from: 0, through: 240, by: 5)), id: \.self) { minutes in
                        Text(minutes == 0 ? "Untimed" : ClockMinute.duration(minutes) ?? "")
                            .tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                .accessibilityLabel("Duration in minutes")
            } label: {
                Text("Something else")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Duration")
        } footer: {
            Text(draft.minutes > 0
                 ? "About \(ClockMinute.duration(draft.minutes) ?? ""). Nothing is timed for you — this is how you plan the day."
                 : "Some things do not take a measurable amount of time, and that is a real answer.")
        }
        .animation(.forgeSelection, value: draft.minutes)
    }

    private func durationChip(label: String, minutes: Int) -> some View {
        let isSelected = draft.minutes == minutes
        return Button {
            ForgeHaptics.shared.detent()
            draft.minutes = minutes
            // Picking a chip settles the question, so the wheel that was open
            // to answer it puts itself away.
            if showingDurationWheel { withAnimation(.forgeRow) { showingDurationWheel = false } }
        } label: {
            Text(label)
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
        .accessibilityLabel(minutes == 0 ? "Untimed" : label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - When

    /// A start time, and an end time it is not allowed to disagree with.
    ///
    /// The end is displayed and never edited — it is the start plus the
    /// duration, and the moment both ends are typeable they can contradict each
    /// other and something has to guess which one was meant. See
    /// `Ritual.endMinute`.
    private var timeSection: some View {
        Section {
            Toggle("Start time", isOn: hasStartBinding.animation(.forgeRow))

            if draft.startMinute != nil {
                DatePicker(
                    "Starts",
                    selection: startBinding,
                    displayedComponents: .hourAndMinute
                )

                if let end = draft.startMinute.flatMap({ start in
                    draft.minutes > 0 ? start + draft.minutes : nil
                }) {
                    LabeledContent("Ends") {
                        Text(ClockMinute.label(end))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .accessibilityLabel("Ends at \(ClockMinute.label(end))")
                }
            }
        } header: {
            Text("When")
        } footer: {
            // Said plainly, because the alternative is somebody trusting it to
            // wake them up. This app deliberately does not schedule from these.
            Text(draft.startMinute == nil
                 ? "Optional. A time here helps you picture the day; it is not an alarm."
                 : "Forge will not remind you at this time, and nothing is late. The end time follows the duration.")
        }
    }

    // MARK: - What counts as done

    private var goalSection: some View {
        Section {
            // Whatever "done" is worth counting to — twenty, ten pages,
            // five minutes. Optional, and the placeholder says what happens
            // when it is left alone, so nobody has to guess whether an empty
            // field means nothing or means broken.
            LabeledContent("Goal") {
                TextField("None", text: $draft.goal)
                    .focused($focus, equals: .goal)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    // Stops at the limit rather than accepting a target the
                    // row cannot hold and quietly cutting it later.
                    .onChange(of: draft.goal) { _, typed in
                        if typed.count > Self.goalLimit {
                            draft.goal = String(typed.prefix(Self.goalLimit))
                        }
                    }
            }
            .accessibilityLabel("Goal")
            .accessibilityValue(draft.trimmedGoal.isEmpty ? "None" : draft.trimmedGoal)
        }
    }

    // MARK: - How it is treated

    /// Which part of the person this builds.
    ///
    /// # Why this is six chips and not the picker it used to be
    ///
    /// It was a wheel in a row labelled "Category", filed under how an activity
    /// is *treated* alongside priority and repeat — which is where you put a
    /// field nobody has to think about. It is now the field that decides which
    /// side of somebody's Shape this activity feeds, so it is a section of its
    /// own with the answer already filled in.
    ///
    /// Six chips rather than a menu because six is small enough to show, and a
    /// menu hides the one thing worth seeing here: that there are exactly six
    /// parts and this activity is going into one of them. Changing it is one tap
    /// from anywhere in the set; a `Picker` is two taps and a scroll.
    ///
    /// The guess arrives from the name — see `Ritual.suggestedCategory(for:)` —
    /// and is silently correct most of the time. It stops guessing the moment
    /// somebody chooses for themselves, the same rule the verification
    /// suggestion follows: an app that keeps re-deciding a field you have
    /// already answered is an app arguing with you.
    private var dimensionSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: ForgeTheme.Space.tight) {
                    ForEach(RitualCategory.dimensions, id: \.self) { dimension in
                        dimensionChip(dimension)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("What it builds")
        } footer: {
            Text(draft.category.meaning)
        }
    }

    private func dimensionChip(_ dimension: RitualCategory) -> some View {
        let isChosen = draft.category == dimension
        return Button {
            userPickedCategory = true
            withAnimation(.forgeSelection) { draft.category = dimension }
        } label: {
            HStack(spacing: 6) {
                // The glyph in its dimension's colour, as everywhere the six
                // are drawn; choosing one is still marked in the accent.
                Image(systemName: dimension.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(dimension.color)
                Text(dimension.label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isChosen
                ? .regular.tint(ForgeTheme.accent.opacity(0.28)).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .foregroundStyle(isChosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityLabel(Text(dimension.label))
        .accessibilityValue(Text(dimension.meaning))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private var treatmentSection: some View {
        Section {
            Picker(selection: $draft.priority) {
                ForEach(RitualPriority.allCases, id: \.self) { priority in
                    Text(priority.label).tag(priority)
                }
            } label: {
                Text("Priority")
            }

            NavigationLink {
                RepeatPicker(selection: $draft.repeats)
            } label: {
                LabeledContent("Repeat") {
                    Text(draft.repeats.label)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(draft.repeats.label)
        } footer: {
            Text(draft.priority == .normal
                 ? "Priority never changes whether a day counts as kept. It marks what to let go of first."
                 : "\(draft.priority.label). This marks the row — it does not change whether the day counts as kept.")
        }
    }

    // MARK: - How it is confirmed

    private var verificationSection: some View {
        Section {
            NavigationLink {
                VerificationPicker(selection: $draft.verification, onPick: {
                    userPickedVerification = true
                })
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: draft.verification.symbol)
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ForgeTheme.accent)
                        .frame(width: 26)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.verification.title)
                            .font(.body.weight(.medium))
                        Text(draft.verification.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel("Verification")
            .accessibilityValue("\(draft.verification.title). \(draft.verification.rationale)")
        } header: {
            Text("Verification")
        } footer: {
            Text(userPickedVerification
                 ? "You chose this one."
                 : "Chosen from what you named it. Change it any time.")
        }
        .animation(.forgeSelection, value: draft.verification)
    }

    // MARK: - The way out

    @ViewBuilder
    private var destructiveSection: some View {
        switch destructive {
        case let .delete(run):
            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Activity").frame(maxWidth: .infinity)
                }
                .confirmationDialog(
                    "Delete “\(draft.trimmedLabel)”?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Activity", role: .destructive) {
                        ForgeHaptics.shared.bottomOut()
                        run()
                        dismiss()
                    }
                } message: {
                    Text("This removes it from your day and from your activities.")
                }
            }
        case let .reset(run):
            // Nothing is lost and nothing is confirmed — putting a shipped
            // activity back the way it came is a tap away from being undone
            // by editing it again.
            Section {
                Button {
                    ForgeHaptics.shared.tap()
                    run()
                    dismiss()
                } label: {
                    Text("Reset to Default").frame(maxWidth: .infinity)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func commit() {
        guard canSave else { return }
        onCommit(draft.cleaned)
        dismiss()
    }

    /// The activity as it will actually read, at the size it deserves while it
    /// is the only thing on screen.
    ///
    /// It now carries the schedule line as well as the name, so the two fields
    /// that are hardest to picture from a form row — how long, and when — are
    /// answered at the top of the screen while they are being chosen.
    private var preview: some View {
        VStack(spacing: ForgeTheme.Space.inner) {
            Image(systemName: draft.symbol)
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 96, height: 96)
                .glassEffect(.regular, in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.34, dampingFraction: 0.7), value: draft.symbol)

            VStack(spacing: ForgeTheme.Space.hair) {
                Text(draft.trimmedLabel.isEmpty ? "Name it" : draft.trimmedLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(draft.trimmedLabel.isEmpty ? .tertiary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let summary = previewSummary {
                    Text(summary)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .animation(.forgeFade, value: draft.trimmedLabel.isEmpty)
            .animation(.forgeSelection, value: previewSummary)
        }
        .padding(.vertical, ForgeTheme.Space.inner)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue(
            draft.trimmedLabel.isEmpty
                ? "Unnamed, \(ActivityIcons.named(draft.symbol))"
                : "\(draft.trimmedLabel), \(ActivityIcons.named(draft.symbol)). \(previewSummary ?? "")"
        )
    }

    /// "6:30 AM – 7:15 AM · 45 min · Weekdays", with every part that has nothing
    /// to say left out. Nil when there is nothing to say at all, so the preview
    /// does not reserve a line for an empty one.
    private var previewSummary: String? {
        var parts: [String] = []
        if let start = draft.startMinute {
            let end = draft.minutes > 0 ? start + draft.minutes : nil
            parts.append(end.map { "\(ClockMinute.label(start)) – \(ClockMinute.label($0))" }
                         ?? ClockMinute.label(start))
        }
        if let duration = ClockMinute.duration(draft.minutes) { parts.append(duration) }
        if !draft.repeats.isDaily { parts.append(draft.repeats.label) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

// MARK: - Repeat picker

/// Which days this happens on: three presets and seven switches.
///
/// The presets are on top because they are what almost everybody wants, and the
/// days are underneath because they are what the presets are made of — picking
/// "Weekdays" ticks five boxes in view rather than replacing them with a word,
/// so the relationship between the two halves is visible rather than magic.
struct RepeatPicker: View {
    @Binding var selection: RitualRepeat

    /// Monday first. A week that starts on Sunday reads as a fortnight to most
    /// of the people who will see this.
    private let order = [2, 3, 4, 5, 6, 7, 1]

    private static let presets: [(String, RitualRepeat)] = [
        ("Every day", .daily),
        ("Weekdays", .weekdays5),
        ("Weekends", .weekends),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.presets, id: \.0) { name, preset in
                    Button {
                        ForgeHaptics.shared.detent()
                        withAnimation(.forgeSelection) { selection = preset }
                    } label: {
                        LabeledContent(name) {
                            if selection == preset {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(ForgeTheme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == preset ? [.isButton, .isSelected] : .isButton)
                }
            }

            Section {
                ForEach(order, id: \.self) { weekday in
                    Toggle(Self.fullName(weekday), isOn: binding(for: weekday))
                }
            } header: {
                Text("Days")
            } footer: {
                // The empty set is the one state worth explaining, because the
                // app's answer to it is generous rather than literal — see
                // `RitualRepeat.includes`.
                Text(selection.weekdays.isEmpty
                     ? "No days chosen, so this happens every day."
                     : "This appears in your day only on these days. It is still yours on the others.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { selection.includes(weekday) },
            set: { on in
                ForgeHaptics.shared.detent()
                var days = selection.weekdays
                // An empty set means every day, so the first tap on a "daily"
                // activity has to start from all seven rather than from nothing
                // — otherwise unticking Sunday would tick nothing and read as
                // having done nothing.
                if days.isEmpty { days = Set(1...7) }
                if on { days.insert(weekday) } else { days.remove(weekday) }
                selection = RitualRepeat(weekdays: days)
            }
        )
    }

    private static func fullName(_ weekday: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][
            max(0, min(6, weekday - 1))
        ]
    }
}


// MARK: - Verification picker

/// Three ways to be confirmed, each explained in its own words.
///
/// Written so no row reads as the compromise. "Your Word" is not the option you
/// settle for when nothing can measure it — for a prayer it is the only honest
/// answer, and the copy has to carry that or the tier reads as a consolation
/// prize. "Basic Check" is not a lesser promise either; it is the same promise
/// without the ceremony, which is what a bottle of vitamins deserves.
struct VerificationPicker: View {
    @Binding var selection: VerificationMethod
    var onPick: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(VerificationMethod.allCases) { method in
                    Button { choose(method) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: method.symbol)
                                .font(.body)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(ForgeTheme.accent)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(method.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(method.pickerDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            if method == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(ForgeTheme.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(method == selection ? [.isButton, .isSelected] : .isButton)
                }
            } footer: {
                Text("Forge suggests one of these from what you named the activity. It is only ever a suggestion.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Verification")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.forgeSelection, value: selection)
    }

    private func choose(_ method: VerificationMethod) {
        ForgeHaptics.shared.detent()
        selection = method
        onPick()
        dismiss()
    }
}

extension VerificationMethod {
    /// The longer explanation, shown only in the picker where somebody is
    /// actually deciding.
    var pickerDetail: String {
        switch self {
        case .honor:
            "For everything else. You say it was done, and that settles it."
        case .basic:
            "A checkbox. Tap it and the activity is done — nothing else is asked."
        }
    }
}

// MARK: - Icon picker

/// A curated, searchable grid of marks.
///
/// Selection commits and returns in one tap — the preview waiting on the screen
/// behind is the confirmation, so a second "Done" would only be a toll.
struct IconPickerView: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The grid relaxes to fewer, larger cells as text grows, so the label
    /// under each mark keeps its own line instead of being squeezed.
    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 3 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var results: [ActivityIcons.Group] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ActivityIcons.groups
        }
        return ActivityIcons.groups.compactMap { group in
            let hits = group.icons.filter { $0.matches(query) }
            return hits.isEmpty ? nil : ActivityIcons.Group(name: group.name, icons: hits)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: [.sectionHeaders]) {
                ForEach(results) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.icons) { icon in
                                IconCell(
                                    icon: icon,
                                    isSelected: icon.symbol == selection
                                ) { choose(icon.symbol) }
                            }
                        }
                        .padding(.horizontal, 20)
                    } header: {
                        Text(group.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search icons")
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    private func choose(_ symbol: String) {
        ForgeHaptics.shared.detent()
        selection = symbol
        dismiss()
    }
}

/// One mark in the picker. The whole tile is the target — 64pt of it before the
/// caption — rather than the glyph alone.
private struct IconCell: View {
    let icon: ActivityIcons.Icon
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? ForgeTheme.cream : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background {
                        RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                            .fill(.white.opacity(isSelected ? 0.12 : 0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                            .strokeBorder(ForgeTheme.cream, lineWidth: isSelected ? 2 : 0)
                    }

                Text(icon.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.64), value: isSelected)
        .accessibilityLabel(icon.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
