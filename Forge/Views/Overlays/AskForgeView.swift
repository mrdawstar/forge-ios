import SwiftUI

/// Ask Forge: a coach that reads somebody's own record (DIRECTION_1_1 §9).
///
/// # What it is, and what it is not
///
/// A calm conversation. A list of messages, an input, send, a typing indicator
/// and three starters built from the record. **No avatar, no persona name, no
/// emoji** — the app never plays a character (§5 #6). Forge's side is plain
/// text with a small line saying what wrote it.
///
/// # What leaves the phone, and when
///
/// Only when a message is sent, only with Forge Pro (the doors that open this
/// screen check, `ContentView.openAskForge`), and only once the person has
/// pressed Allow on the disclosure, which is raised by the first send exactly
/// as Plan's "Work it out" raises it. A request carries `CoachBrief` and the
/// last eight turns; the history itself stays on the phone (`CoachHistory`).
///
/// # Safety
///
/// - A message that suggests a crisis is answered **here**, before anything is
///   sent, with one caring line and the 988 lifeline, and Call and Text under
///   it (`CoachSafety`). It is never carried by a later request.
/// - "Not medical advice" sits under the title, always.
/// - A long press on a reply offers Report: a pre-filled email to support that
///   the person reads and sends themselves.
///
/// # A proposal is never applied from here (§5 #9, #10)
///
/// It opens Plan's review, marked as written by Forge's AI, and only the button
/// there that says how many changes it makes writes anything.
struct AskForgeView: View {
    /// The record as it was when the screen opened.
    let coach: CoachBrief
    let topic: CoachTopic
    @Bindable var history: CoachHistory
    /// For Plan's review of a proposal, and the week a proposal is checked
    /// against when it is opened.
    var forge: ForgeViewModel
    /// Plan's own AI, handed to its review screen.
    var planAI: ForgeAI
    /// Whether a model is reachable from this build: the consent sheet is
    /// raised only where it is.
    var isConnected: Bool
    /// One answer. `RemoteForgeAI.coach` in the app.
    var ask: @Sendable (CoachBrief, [CoachTurn]) async throws -> CoachReply

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AIConsentStore.self) private var consent: AIConsentStore?

    @State private var draft = ""
    @State private var isSending = false
    @State private var isAskingConsent = false
    /// What was typed when the consent sheet went up, sent if they allow it.
    @State private var pending: String?
    /// "Nothing was sent", after Not now. On screen only, never kept.
    @State private var showsDeclined = false
    @State private var isClearing = false
    @State private var reviewing: SchedulePlan?
    /// A report no mail app could take: offered to copy instead.
    @State private var unsentReport: String?
    @FocusState private var isTyping: Bool

    private let bottomID = "ask.bottom"

    private var starters: [String] { CoachStarters.make(coach, topic: topic) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                        if history.messages.isEmpty { opening }
                        ForEach(history.messages) { message in
                            row(message)
                                .id(message.id)
                        }
                        if isSending {
                            TypingIndicator()
                                .transition(.opacity)
                        }
                        if showsDeclined { declinedNote }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, ForgeTheme.Space.gutter)
                    .padding(.top, ForgeTheme.Space.inner)
                    .padding(.bottom, ForgeTheme.Space.row)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: history.messages.count) { _, _ in
                    withAnimation(.forgeRow) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onChange(of: isSending) { _, _ in
                    withAnimation(.forgeRow) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
            .navigationTitle(AskForgeCopy.title)
            .navigationSubtitle(AskForgeCopy.disclaimer)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if !history.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") { isClearing = true }
                            .disabled(isSending)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .confirmationDialog(
                "Clear this conversation?",
                isPresented: $isClearing,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    withAnimation(.forgeRow) { history.clear() }
                }
            } message: {
                Text("It is kept only on this phone. Clearing removes it.")
            }
        }
        .presentationDragIndicator(.visible)
        .aiConsent(
            isPresented: $isAskingConsent,
            briefs: AIDisclosureBriefs(brief: coach.brief, readingBrief: coach.brief, coach: coach)
        ) { allowed in
            let text = pending
            pending = nil
            if allowed {
                if let text { send(text) }
            } else {
                // Kept in the field, so the question is not lost: it can be
                // sent the moment they allow it, or edited, or cleared.
                if let text { draft = text }
                showsDeclined = true
            }
        }
        .sheet(item: $reviewing) { plan in
            PlanSheet(vm: forge, brief: currentBrief, ai: planAI, proposing: plan)
        }
        // No mail app on this phone: the report is the person's to copy and
        // send from wherever they write email.
        .alert(
            "No mail app to send it with",
            isPresented: Binding(get: { unsentReport != nil }, set: { if !$0 { unsentReport = nil } })
        ) {
            Button("Copy the report") {
                UIPasteboard.general.string = Self.reportBody(for: unsentReport ?? "")
                unsentReport = nil
            }
            Button("Cancel", role: .cancel) { unsentReport = nil }
        } message: {
            Text("Copy it and send it to \(ForgeLinks.supportEmail).")
        }
    }

    // MARK: - Before anything is said

    private var opening: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            Text(AskForgeCopy.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ForgeTheme.Space.tight) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        ForgeHaptics.shared.tap()
                        send(starter)
                    } label: {
                        HStack(spacing: ForgeTheme.Space.inner) {
                            Text(starter)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(ForgeTheme.Space.row)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
                    .disabled(isSending)
                    .accessibilityHint(Text("Sends this question"))
                }
            }
        }
        .padding(.top, ForgeTheme.Space.tight)
    }

    // MARK: - One line

    @ViewBuilder
    private func row(_ message: CoachMessage) -> some View {
        switch (message.role, message.kind) {
        case (.user, _):
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        ForgeTheme.accent.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("You: \(message.text)"))

        case (.forge, .message):
            reply(message, label: AskForgeCopy.modelLabel, isModelWritten: true)

        case (.forge, .local):
            reply(message, label: AskForgeCopy.local, isModelWritten: false)

        case (.forge, .safety):
            safetyReply(message)

        case (.forge, .notice):
            Label(message.text, systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }

    private func reply(_ message: CoachMessage, label: String, isModelWritten: Bool) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text(message.text)
                .font(.body)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let proposal = message.proposal {
                proposalCard(proposal, isModelWritten: isModelWritten)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 24)
        .contentShape(.rect)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
            if isModelWritten, let report = Self.reportURL(for: message.text) {
                Button("Report", systemImage: "flag") {
                    openURL(report) { accepted in
                        if !accepted { unsentReport = message.text }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The 988 reply: the line, and the two ways to reach it.
    private func safetyReply(_ message: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            Text(message.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ForgeTheme.Space.tight) {
                Link(destination: CoachSafety.callURL) {
                    Label("Call 988", systemImage: "phone")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                Link(destination: CoachSafety.textURL) {
                    Label("Text 988", systemImage: "message")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
    }

    /// A proposed change: what it would do, and the way into Plan's review.
    /// Checked against the week as it is now; one that no longer fits says so.
    @ViewBuilder
    private func proposalCard(_ proposal: CoachProposal, isModelWritten: Bool) -> some View {
        if let plan = proposal.plan(against: currentBrief, isModelWritten: isModelWritten) {
            Button {
                ForgeHaptics.shared.tap()
                isTyping = false
                reviewing = plan
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.changes.count == 1
                         ? "ONE CHANGE PROPOSED"
                         : "\(ForgeCount.spelled(plan.changes.count).uppercased()) CHANGES PROPOSED")
                        .font(ForgeTheme.overline)
                        .kerning(ForgeTheme.overlineKerning)
                        .foregroundStyle(.tertiary)
                    Text(plan.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("Review the changes")
                        Image(systemName: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ForgeTheme.accent)
                    .padding(.top, 2)
                }
                .padding(ForgeTheme.Space.row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
            .accessibilityHint(Text("Shows every change before anything moves"))
        } else {
            Text("Nothing left to review: this is already in your week, or no longer fits it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var declinedNote: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text(AskForgeCopy.declined)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Read what is sent") {
                ForgeHaptics.shared.tap()
                if pending == nil, !draft.isEmpty { pending = draft }
                showsDeclined = false
                isAskingConsent = true
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
    }

    // MARK: - The input

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: ForgeTheme.Space.tight) {
            TextField("Ask about your record", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .focused($isTyping)
                .submitLabel(.send)
                .onSubmit { if canSend { send(draft) } }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .forgeCard(radius: ForgeTheme.Radius.control)
                .onChange(of: draft) { _, value in
                    if value.count > CoachHistory.messageLimit {
                        draft = String(value.prefix(CoachHistory.messageLimit))
                    }
                }

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: - Sending

    /// The week as it is now, which a proposal is checked against when it is
    /// opened: an activity removed since the reply was written drops out of it.
    private var currentBrief: AIBrief {
        var brief = coach.brief
        brief.activities = forge.scheduledActivities
        return brief
    }

    private func send(_ raw: String) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CoachHistory.messageLimit))
        guard !text.isEmpty, !isSending else { return }
        showsDeclined = false

        // A crisis is answered here, whatever the consent, the purchase or the
        // network, and nothing about it is sent.
        if CoachSafety.suggestsCrisis(text) {
            draft = ""
            ForgeHaptics.shared.tap()
            var said = CoachMessage(role: .user, text: text)
            said.isWithheld = true
            history.append(said)
            history.append(CoachMessage(role: .forge, kind: .safety, text: CoachSafety.crisisReply))
            return
        }

        // The first send asks, exactly as Plan's "Work it out" does. A "Not
        // now" given before is not asked over again unprompted.
        if isConnected, let consent, !consent.isAllowed {
            pending = text
            if consent.hasDecided {
                showsDeclined = true
            } else {
                isTyping = false
                isAskingConsent = true
            }
            return
        }

        draft = ""
        ForgeHaptics.shared.tap()
        let said = CoachMessage(role: .user, text: text)
        history.append(said)
        let turns = history.turns
        let brief = coach
        withAnimation(.forgeFade) { isSending = true }

        Task {
            do {
                let reply = try await ask(brief, turns)
                if reply.isSafety {
                    history.withhold(said.id)
                    history.append(CoachMessage(role: .forge, kind: .safety, text: reply.text))
                } else {
                    history.append(CoachMessage(role: .forge, text: reply.text, proposal: reply.proposal))
                }
            } catch {
                history.append(CoachMessage(role: .forge, kind: .notice, text: AskForgeCopy.unreachable))
                // The local fallback, where one exists: a sentence the phone's
                // own planner understands still gets its proposal, labelled as
                // the phone's.
                if let plan = try? await LocalForgeAI().plan(brief: currentBrief, request: text),
                   !plan.isEmpty, let proposal = CoachProposal(plan) {
                    history.append(CoachMessage(role: .forge, kind: .local, text: plan.summary, proposal: proposal))
                }
            }
            withAnimation(.forgeFade) { isSending = false }
        }
    }

    // MARK: - Report

    /// A pre-filled email to support, which the person reads and sends
    /// themselves: nothing is reported without them.
    static func reportURL(for reply: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ForgeLinks.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Ask Forge: reporting a reply"),
            URLQueryItem(name: "body", value: reportBody(for: reply)),
        ]
        return components.url
    }

    static func reportBody(for reply: String) -> String {
        "This reply from Ask Forge was wrong or inappropriate:\n\n\"\(reply)\"\n\nWhat was wrong with it (optional):\n\n"
    }
}

// MARK: - The typing indicator

/// Three dots, breathing. Still under Reduce Motion.
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: reduceMotion)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.32) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 0.6 : (index == step ? 0.9 : 0.3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(Text("Forge's AI is answering"))
    }
}
