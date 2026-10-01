import SwiftUI

// MARK: - One Arc

/// An Arc's own screen: the cover, the length, what each phase adds, the
/// weekly trials, one honest line of why, and Start today / Start Monday.
///
/// Nothing on it writes anything. Both buttons open `ArcJoinSheet`, which says
/// exactly what joining adds before it adds it (§5 #9).
struct ArcDetailView: View {
    let program: ArcProgram
    var arcs: ArcStore
    var forge: ForgeViewModel
    /// Whether new days — and so the Arcs — are open to this person.
    let isLocked: Bool
    let onLocked: () -> Void

    @State private var joining: ArcJoinRequest?

    private var today: ForgeDay { forge.progress.currentDay }

    /// The coming Monday, never today: "Start Monday" pressed on a Monday
    /// means the next one, because today already has a button of its own.
    private var monday: ForgeDay {
        let ahead = (2 - today.weekday + 7) % 7
        return today.adding(days: ahead == 0 ? 7 : ahead)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArcCover(program: program, showsName: false, height: 220)
                    .padding(.bottom, ForgeTheme.Space.row)

                header
                    .padding(.bottom, ForgeTheme.Space.section)

                ArcHeading(title: "Phases", detail: program.phases.count == 1 ? nil : "\(program.phases.count)")
                    .padding(.bottom, ForgeTheme.Space.tight)
                phases
                    .padding(.bottom, ForgeTheme.Space.section)

                ArcHeading(title: "The weekly trials", detail: "\(program.trials.count)")
                    .padding(.bottom, ForgeTheme.Space.tight)
                trials
                    .padding(.bottom, ForgeTheme.Space.section)

                start
            }
            .padding(.horizontal, ForgeTheme.Space.gutter)
            .padding(.bottom, ForgeTheme.Space.chapter)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $joining) { request in
            ArcJoinSheet(request: request, arcs: arcs, forge: forge)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text(program.name)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(program.lengthLabel.uppercased())
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(.secondary)
            Text(program.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text(program.why)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let source = program.source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reward = program.reward, forge.daysKept < 7 {
                Label(reward, systemImage: "flame")
                    .font(.footnote)
                    .foregroundStyle(ForgeTheme.cream.opacity(0.85))
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Phases

    private var phases: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            ForEach(Array(program.phases.enumerated()), id: \.offset) { index, phase in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(phase.name)
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text(phase.span)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(phase.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    phaseContents(index)
                }
                .padding(ForgeTheme.Space.row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeCard(radius: ForgeTheme.Radius.control)
            }
        }
    }

    /// What a phase adds: for the first, everything the Arc asks for; for each
    /// after it, what changes from the one before.
    @ViewBuilder
    private func phaseContents(_ index: Int) -> some View {
        if index == 0 {
            if program.activities.isEmpty && program.picks == 0 {
                Label("Your plan as it is, and the daily challenge", systemImage: "flag")
                    .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(program.activities, id: \.ritualID) { activity in
                        activityRow(activity)
                    }
                    if program.picks > 0 {
                        Label("Three activities you choose, every day", systemImage: "hand.point.up.left")
                            .font(.subheadline)
                    }
                }
            }
        } else {
            let steps = ArcPlan.steps(for: program, from: index - 1, to: index, find: forge.ritual)
            if steps.isEmpty {
                Text("Nothing new.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { ArcChangeRow(change: $0) }
                }
            }
        }
    }

    private func activityRow(_ activity: ArcActivity) -> some View {
        let ritual = forge.ritual(activity.ritualID)
        let standard = activity.standard(inPhase: 0)
        var parts: [String] = []
        if let minute = activity.time.minute(wake: ArcProgram.defaultWake) {
            parts.append(ClockMinute.label(minute))
        }
        parts.append(RitualRepeat(weekdays: standard.weekdays).label)
        if let minutes = standard.minutes, let length = ClockMinute.duration(minutes) {
            parts.append(length)
        } else if let goal = standard.goal {
            parts.append(goal)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ritual.map { $0.symbolName ?? ForgeIcons.symbol(for: $0.iconKey) } ?? "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ritual?.category.color ?? .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(ritual?.label ?? activity.ritualID)
                    .font(.subheadline.weight(.medium))
                Text(parts.joined(separator: " \u{00B7} "))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Trials

    private var trials: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(program.trials.enumerated()), id: \.offset) { index, trial in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trial.title)
                            .font(.subheadline.weight(.medium))
                        Text(trial.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Start

    @ViewBuilder
    private var start: some View {
        VStack(spacing: 10) {
            if let current = arcs.current {
                Text(current.arc == program.id
                     ? "You are in this Arc now. It is on the Arcs tab."
                     : "One Arc at a time. Leave \(current.program.name) to start this one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForgeButton(title: "Start today") { open(on: today) }
                Button {
                    open(on: monday)
                } label: {
                    Text(today.weekday == 2 ? "Start next Monday" : "Start Monday")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
                .tint(.secondary)
                Text("Monday is a fresh start on the calendar's side. Either way, you see what is added before anything is.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
    }

    private func open(on day: ForgeDay) {
        ForgeHaptics.shared.tap()
        guard !isLocked else { onLocked(); return }
        joining = ArcJoinRequest(arc: program.id, startDay: day)
    }
}

/// Which Arc somebody is about to join, and from when.
struct ArcJoinRequest: Identifiable, Equatable {
    let arc: ArcID
    let startDay: ForgeDay
    var id: String { "\(arc.rawValue).\(startDay.year)-\(startDay.month)-\(startDay.day)" }
}

// MARK: - Joining

/// What joining adds, said before it is added: "Adds five activities to your
/// week", every one with its days and its hour, and the choices the Arc asks
/// for — a wake time, three activities — above them.
///
/// **Nothing is removed and nothing already in the week is changed** (§5 #7):
/// the Arc's activities somebody already keeps are listed as theirs. The one
/// button applies exactly the list on screen (§5 #9).
struct ArcJoinSheet: View {
    let request: ArcJoinRequest
    var arcs: ArcStore
    var forge: ForgeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var wake = Date()
    @State private var picks: [String] = []

    private var program: ArcProgram { ArcCatalog.program(request.arc) }

    private var wakeMinute: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: wake)
        return (parts.hour ?? 6) * 60 + (parts.minute ?? 30)
    }

    private var preview: ArcJoin {
        arcs.preview(request.arc, wake: wakeMinute, picks: picks)
    }

    private var isToday: Bool { request.startDay == forge.progress.currentDay }

    private var canStart: Bool { picks.count >= program.picks }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview.headline)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                        Text(startLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if program.asksForWake {
                        DatePicker("Wake time", selection: $wake, displayedComponents: .hourAndMinute)
                            .font(.body.weight(.medium))
                    }

                    if program.picks > 0 {
                        PickList(forge: forge, picks: $picks, limit: program.picks)
                    }

                    if !preview.additions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ArcHeading(title: "Added to your week")
                            ForEach(preview.additions) { addition in
                                additionRow(addition)
                            }
                        }
                    }

                    if !preview.alreadyKept.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ArcHeading(title: "Already in your week")
                            Text(preview.alreadyKept.joined(separator: ", "))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Counted as they are. If this Arc asks for something different, it says so on its card, and changes it only when you tap.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if program.withChallenge {
                        Label("The daily challenge is part of every day.", systemImage: "flag")
                            .font(.subheadline)
                    }

                    Text("Nothing is removed. Every activity stays yours to move or take off.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                ForgeButton(title: isToday ? "Start today" : "Start on Monday") {
                    ForgeHaptics.shared.detent()
                    arcs.start(
                        request.arc, on: request.startDay,
                        wake: program.asksForWake ? wakeMinute : nil,
                        picks: picks
                    )
                    dismiss()
                }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.5)
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, 12)
                .background(.bar)
            }
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            var parts = DateComponents()
            parts.hour = ArcProgram.defaultWake / 60
            parts.minute = ArcProgram.defaultWake % 60
            wake = Calendar.current.date(from: parts) ?? wake
        }
    }

    private var startLine: String {
        guard !isToday else { return "\(program.name) starts today and runs \(program.length) days." }
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let date = format.string(from: request.startDay.startOfDay())
        return "\(program.name) starts on \(date). Nothing changes in your week until then."
    }

    private func additionRow(_ addition: ArcJoin.Addition) -> some View {
        HStack(spacing: 12) {
            Image(systemName: addition.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(forge.ritual(addition.id)?.category.color ?? .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(addition.name)
                    .font(.body.weight(.medium))
                Text(addition.schedule)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(ForgeTheme.cream)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Choosing three

/// Discipline 66's three: chosen from what somebody already keeps first, then
/// from the library. Exactly `limit`, and the fourth tap does nothing until one
/// is put back.
private struct PickList: View {
    var forge: ForgeViewModel
    @Binding var picks: [String]
    let limit: Int

    /// What somebody keeps now, without the wake-up the Arc brings itself.
    private var kept: [Ritual] { forge.activeRituals.filter { $0.id != "wake" } }

    /// The library's first few per dimension that are not already kept.
    private var library: [Ritual] {
        let held = Set(forge.activeRitualIDs)
        return RitualCategory.dimensions.flatMap { dimension in
            (IdentityActivities.starters[dimension] ?? [])
                .filter { !held.contains($0) && $0 != "wake" }
                .prefix(2)
                .compactMap(forge.ritual)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArcHeading(title: "Your three", detail: "\(picks.count) of \(limit)")
            if !kept.isEmpty {
                Text("From your week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(kept) { row($0) }
            }
            Text("From the library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(library) { row($0) }
        }
    }

    private func row(_ ritual: Ritual) -> some View {
        let chosen = picks.contains(ritual.id)
        return Button {
            ForgeHaptics.shared.tap()
            if chosen {
                picks.removeAll { $0 == ritual.id }
            } else if picks.count < limit {
                picks.append(ritual.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ritual.symbolName ?? ForgeIcons.symbol(for: ritual.iconKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ritual.category.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ritual.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !ritual.sub.isEmpty {
                        Text(ritual.sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? AnyShapeStyle(ForgeTheme.accent) : AnyShapeStyle(.tertiary))
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
