import SwiftUI
import Testing
import UIKit

@testable import Forge

/// The parts of accessibility a test can actually hold.
///
/// VoiceOver labels, Dynamic Type reflow and Reduce Motion are checked by hand
/// on a device — a unit test cannot tell whether a label reads well out loud.
/// **What a test can hold is that every control has one**: the 1.1 release
/// pass (FORGE_CONTEXT §17.7) renders each control 1.1 added in a window, the
/// way the app does, and reads back what VoiceOver would be handed — its
/// label, its traits, its hint — so a control that loses its label, or a
/// chosen answer that stops saying it is chosen, fails here rather than in
/// somebody's ear.
@MainActor
@Suite("Accessibility: every 1.1 control says what it is", .serialized)
struct AccessibilityTests {

    // MARK: - Reading the tree

    /// One element as VoiceOver meets it.
    struct Node: CustomStringConvertible {
        let label: String
        let value: String
        let hint: String
        let traits: UIAccessibilityTraits
        let actions: [String]

        var isButton: Bool { traits.contains(.button) }
        var isHeader: Bool { traits.contains(.header) }
        var isSelected: Bool { traits.contains(.selected) }

        var description: String {
            "[\(label)] value=\(value) hint=\(hint) button=\(isButton) header=\(isHeader) selected=\(isSelected) actions=\(actions)"
        }
    }

    /// SwiftUI builds the elements VoiceOver reads only once something asks
    /// for them — VoiceOver, Switch Control, the Accessibility Inspector, a UI
    /// test. A unit test is none of those, so it says it is one the way UI
    /// testing does: through the accessibility library's own switch. Test
    /// code only; nothing in the app touches it.
    private static let isAccessibilityOn: Bool = {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSApplicationAccessibilitySetEnabled")
        else { return false }
        typealias SetEnabled = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(true)
        return true
    }()

    /// Draws the view in a window at an iPhone 17 Pro's size, dark, and reads
    /// every accessibility element in it.
    static func nodes(
        of view: some View,
        size: CGSize = CGSize(width: 402, height: 874),
        typeSize: DynamicTypeSize = .large
    ) -> [Node] {
        _ = isAccessibilityOn
        let host = UIHostingController(
            rootView: view
                .environment(\.dynamicTypeSize, typeSize)
                .preferredColorScheme(.dark)
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // One turn of the run loop, so SwiftUI commits what it drew.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()

        var found: [Node] = []
        collect(host.view, into: &found, depth: 0)
        window.isHidden = true
        return found
    }

    private static func collect(_ element: Any, into found: inout [Node], depth: Int) {
        guard depth < 80, let object = element as? NSObject else { return }
        if object.isAccessibilityElement {
            found.append(Node(
                label: object.accessibilityLabel ?? "",
                value: object.accessibilityValue ?? "",
                hint: object.accessibilityHint ?? "",
                traits: object.accessibilityTraits,
                actions: (object.accessibilityCustomActions ?? []).map(\.name)
            ))
        }
        if let elements = object.accessibilityElements, !elements.isEmpty {
            // The container says what is in it; its subviews would only say
            // the same things again.
            for child in elements { collect(child, into: &found, depth: depth + 1) }
            return
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) {
                    collect(child, into: &found, depth: depth + 1)
                }
            }
            return
        }
        if let view = object as? UIView {
            for sub in view.subviews { collect(sub, into: &found, depth: depth + 1) }
        }
    }

    private func dump(_ nodes: [Node], _ title: String = #function) {
        print("AX \(title):\n" + nodes.map { "  \($0)" }.joined(separator: "\n"))
    }

    /// No element VoiceOver can land on is silent.
    private func expectNoneUnlabelled(_ nodes: [Node], sourceLocation: SourceLocation = #_sourceLocation) {
        for node in nodes where node.label.trimmingCharacters(in: .whitespaces).isEmpty {
            Issue.record("an element with no label: \(node)", sourceLocation: sourceLocation)
        }
    }

    private func node(_ label: String, in nodes: [Node]) -> Node? {
        nodes.first { $0.label == label }
    }

    // MARK: - The first run (§17.1)

    @Test("The first run's bar: Back and Skip are labelled buttons, and an absent Back is not there at all")
    func onboardingBar() throws {
        let nodes = Self.nodes(of: OnboardingTopBar(progress: 0.4, onBack: {}, onSkip: {}))
        dump(nodes)
        expectNoneUnlabelled(nodes)
        let back = try #require(node("Back", in: nodes))
        #expect(back.isButton)
        let skip = try #require(node("Skip", in: nodes))
        #expect(skip.isButton)

        let first = Self.nodes(of: OnboardingTopBar(progress: 0.1))
        #expect(node("Back", in: first) == nil, "hidden on the cold open")
    }

    @Test("A question: the prompt is a header, each answer a button, the chosen one says so")
    func question() throws {
        let nodes = Self.nodes(of: QuestionBeat(question: .training, selected: 2, isFirst: true) { _ in })
        dump(nodes)
        expectNoneUnlabelled(nodes)
        let prompt = try #require(nodes.first { $0.label == Assessment.Question.training.prompt })
        #expect(prompt.isHeader)
        let options = Assessment.Question.training.options
        for (index, option) in options.enumerated() {
            let row = try #require(node(option.label, in: nodes), Comment(rawValue: option.label))
            #expect(row.isButton)
            #expect(row.isSelected == (index == 2), Comment(rawValue: option.label))
        }
    }

    private var assessment: Assessment {
        Assessment(
            day: ForgeDay(year: 2026, month: 10, day: 4),
            answers: Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        )
    }

    @Test("The drawing is one button that says how to move on")
    func drawing() throws {
        let nodes = Self.nodes(of: DrawingBeat(assessment: assessment) {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        let drawing = try #require(nodes.first { $0.label.contains(FirstRunCopy.drawingTitle) })
        #expect(drawing.isButton)
        #expect(drawing.hint == "Double tap to continue")
    }

    @Test("The four stops: each a button, the one shown selected; every number said with its name")
    func transformation() throws {
        let plan = OnboardingPlan.propose(focus: [.discipline], assessment: assessment).compactMap(\.ritual)
        let frames = Transformation.frames(plan: plan, assessment: assessment)
        let nodes = Self.nodes(of: TransformationBeat(frames: frames) {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        for stop in Transformation.Stop.allCases {
            let button = try #require(node(stop.title, in: nodes.filter(\.isButton)), Comment(rawValue: stop.title))
            #expect(button.isSelected == (stop == .now), Comment(rawValue: stop.title))
        }
        for category in RitualCategory.dimensions {
            let tile = try #require(node(category.label, in: nodes), Comment(rawValue: category.label))
            #expect(!tile.value.isEmpty, Comment(rawValue: category.label))
        }
        #expect(nodes.contains { $0.label.hasPrefix("Overall ") })
    }

    @Test("Why it works: Sources says whether it is open and what it will do")
    func science() throws {
        let nodes = Self.nodes(of: ScienceBeat {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        let sources = try #require(nodes.first { $0.label.hasPrefix("Sources") })
        #expect(sources.isButton)
        #expect(sources.value == "Hidden")
        #expect(sources.hint == "Shows each finding in full, with its reference")
    }

    @Test("The plan: each Arc a labelled choice, each row says its days and time and how to change it")
    func plan() throws {
        let entries = OnboardingPlan.propose(focus: [.discipline], assessment: assessment)
        let nodes = Self.nodes(of: PlanBeat(
            entries: .constant(entries), arc: .constant(.lockIn), arcRows: [],
            today: 1, day: ForgeDay(year: 2026, month: 10, day: 4)
        ) {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        let lockIn = try #require(nodes.first { $0.label.hasPrefix("Lock In 7") })
        #expect(lockIn.isSelected)
        #expect(nodes.contains { $0.label.hasPrefix("Winter Arc") && $0.label.hasSuffix("starts today") })
        for entry in entries {
            guard let name = entry.ritual?.label else { continue }
            let row = try #require(nodes.first { $0.label.hasPrefix("\(name). ") }, Comment(rawValue: name))
            #expect(row.isButton)
            #expect(row.label.contains(entry.repeats.spokenLabel))
            #expect(row.hint == "Double tap to change its days or time, or swap it")
        }
    }

    // MARK: - Forge Pro (§17.2)

    @Test("The locked state: a heading, and Continue says it opens Forge Pro; the badge says Forge Pro")
    func locked() throws {
        let nodes = Self.nodes(of: ProLockedState {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        #expect(node(PremiumCopy.lockedTitle, in: nodes)?.isHeader == true)
        let button = try #require(node("Continue", in: nodes))
        #expect(button.isButton)
        #expect(button.hint == "Opens Forge Pro")

        let badge = Self.nodes(of: ProBadge())
        #expect(badge.map(\.label) == ["Forge Pro"])

        let row = Self.nodes(of: ProLockedRow(feature: .weeklyReading) {})
        dump(row, "lockedRow")
        let reading = try #require(row.first { $0.label.contains(ProFeature.weeklyReading.title) })
        #expect(reading.isButton)
        #expect(reading.hint == "Opens Forge Pro")
    }

    @Test("The paywall: a heading, the documents and Not now are buttons; a plan reads name, trial and price")
    func paywall() throws {
        let defaults = try #require(UserDefaults(suiteName: "forge.ax.paywall.\(UUID().uuidString)"))
        let store = ForgeStore(defaults: defaults, readsAppTransaction: false)
        let nodes = Self.nodes(of: PaywallView(door: .settings, store: store) {})
        dump(nodes)
        expectNoneUnlabelled(nodes)
        #expect(nodes.contains { $0.isHeader && $0.label == PremiumCopy.headline(trialDays: nil) })
        for label in ["Not now", "Restore Purchases", "Terms of Use", "Privacy Policy"] {
            #expect(node(label, in: nodes)?.isButton == true, Comment(rawValue: label))
        }
        #expect(node("Not now", in: nodes)?.hint == "Closes Forge Pro. Nothing changes.")
        #expect(PaywallView.spokenPlan(name: "Annual", badge: "7 days free", price: "$49.99 a year", perWeek: "$0.96 a week")
            == "Annual, 7 days free, $49.99 a year, $0.96 a week")
        #expect(PaywallView.spokenPlan(name: "Monthly", badge: nil, price: "$12.99 a month", perWeek: nil)
            == "Monthly, $12.99 a month")
    }

    // MARK: - Becoming (§17.4)

    @Test("A stat tile: its name, building or not, its score and change, and what it opens")
    func statTile() throws {
        let six = BlendedShape.read([:], today: ForgeDay(year: 2026, month: 10, day: 4), activities: [], assessment: assessment)
        let tiles = StatGlance.tiles(now: six, weekAgo: nil, focus: [.discipline])
        let discipline = try #require(tiles.first { $0.category == .discipline })
        let nodes = Self.nodes(of: StatTileView(tile: discipline) {}.frame(width: 120, height: 100))
        dump(nodes)
        let tile = try #require(nodes.first)
        #expect(tile.label == "Discipline, building")
        #expect(tile.value.hasPrefix("\(discipline.dimension.score)"))
        #expect(tile.value.contains("from your answers"))
        #expect(tile.hint == "Shows what feeds it")
        #expect(tile.isButton)
    }

    // MARK: - Arcs (§17.3)

    @Test("A trial's marks say how far it has got")
    func trialMarks() {
        let nodes = Self.nodes(of: TrialMarks(progress: ArcTrialProgress(index: 0, count: 3, target: 5, isTally: false)))
        #expect(nodes.map(\.label) == ["3 of 5"])
    }

    // MARK: - Apple Health (§17.5)

    @Test("The Health primer: a heading, each type read as one, and both answers buttons")
    func healthPrimer() throws {
        let nodes = Self.nodes(of: HealthPrimerView(activities: { _ in ["Hit your steps"] }) { _ in })
        dump(nodes)
        expectNoneUnlabelled(nodes)
        #expect(node("Apple Health can tick these off.", in: nodes)?.isHeader == true)
        #expect(node("Continue", in: nodes)?.isButton == true)
        #expect(node("Keep it Your Word", in: nodes)?.isButton == true)
        for metric in ActivityMetric.allCases {
            #expect(nodes.contains { $0.label.hasPrefix(metric.healthName) }, Comment(rawValue: metric.healthName))
        }
    }

    // MARK: - Ask Forge (§17.6)

    @Test("Ask Forge: Send is labelled, a starter says it sends, and a line says who said it")
    func askForge() throws {
        let defaults = try #require(UserDefaults(suiteName: "forge.ax.coach.\(UUID().uuidString)"))
        let history = CoachHistory(defaults: defaults)
        history.append(CoachMessage(role: .user, text: "How do I raise Discipline?"))
        let emptyHistory = CoachHistory(defaults: try #require(UserDefaults(suiteName: "forge.ax.coach.empty.\(UUID().uuidString)")))
        let progress = ProgressStore(defaults: defaults)
        let forge = ForgeViewModel(progress: progress)
        let coach = CoachBrief(
            brief: AIBrief(),
            scores: RitualCategory.dimensions.map { CoachBrief.Score(category: $0, score: 40) },
            overall: 40
        )

        let empty = Self.nodes(of: AskForgeView(
            coach: coach, topic: .general, history: emptyHistory, forge: forge,
            planAI: LocalForgeAI(), isConnected: true, ask: { _, _ in throw CancellationError() }
        ))
        dump(empty, "askForge.empty")
        expectNoneUnlabelled(empty)
        #expect(node("Send", in: empty)?.isButton == true)
        let starters = empty.filter { $0.hint == "Sends this question" }
        #expect(!starters.isEmpty)
        #expect(starters.allSatisfy { $0.isButton })

        let talking = Self.nodes(of: AskForgeView(
            coach: coach, topic: .general, history: history, forge: forge,
            planAI: LocalForgeAI(), isConnected: true, ask: { _, _ in throw CancellationError() }
        ))
        dump(talking, "askForge.talking")
        #expect(node("You: How do I raise Discipline?", in: talking) != nil)
        // The field has a name of its own, typed into or not.
        #expect(node("Message to Ask Forge", in: talking) != nil)
    }

    // MARK: - Your data (§17.7)

    @Test("Your data: Export and Import are buttons that say what they do")
    func yourData() throws {
        let nodes = Self.nodes(of: List { YourDataSection() })
        dump(nodes)
        let export = try #require(nodes.first { $0.label.contains("Export Backup") })
        #expect(export.isButton)
        #expect(export.hint == "Saves everything Forge keeps on this iPhone as one file")
        let importing = try #require(nodes.first { $0.label.contains("Import Backup") })
        #expect(importing.isButton)
        #expect(importing.hint == "Replaces what is on this iPhone with a backup file, after asking")
    }
}
