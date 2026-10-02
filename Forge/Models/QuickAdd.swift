import Foundation

/// What QuickAdd offers, taken once when the sheet opens.
///
/// # Why the lists are taken once
///
/// Adding something changes the week, and every section here is a reading of
/// the week: a library activity added to Thursday is no longer "not in the
/// week", one added to the week is no longer "yours, unused". Read live, the
/// row somebody just tapped would leave its section under their finger and the
/// list would close up beneath it — and the next tap would land on whatever
/// slid into its place. So the sections are what the week was when the sheet
/// opened, a tapped row stays where it is with a check on it, and the next time
/// the sheet opens it reads the week again.
///
/// # The four sections, and what each one's tap does
///
/// - **Suggested for you** — first, anything the running Arc asks for that the
///   week does not hold (`ArcStore.gaps`), then three small things for the
///   weakest dimension (`ForgeViewModel.weakestDimension`,
///   `ForgeShape.suggestions`). All library activities, all appended.
/// - **Already in your week** — on other days and not this one. A tap adds the
///   day; it never mints a copy (`ForgeViewModel.quickAdd`).
/// - **Yours** — what somebody made and took out of the week.
/// - **Library** — everything else, by the dimension chips.
///
/// An activity is in one section at most. The dimension chips narrow what is
/// *offered* — Suggested and the library — and never what is already
/// somebody's: "Already in your week" and "Yours" are a handful of things they
/// chose, and hiding one of those behind a filter is the sheet losing
/// something the person knows is there (the rule `ActivityLibraryView` set).
struct QuickAddCatalog: Equatable {

    enum Section: String, CaseIterable, Identifiable, Sendable {
        case suggested, inWeek, yours, library
        var id: String { rawValue }

        var title: String {
            switch self {
            case .suggested: "Suggested for you"
            case .inWeek: "Already in your week"
            case .yours: "Yours"
            case .library: "Library"
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let ritual: Ritual
        let section: Section
        /// Why a suggestion is there, or the days a row in the week runs on.
        let detail: String?
        var id: String { ritual.id }
    }

    /// The weekday being filled.
    let weekday: Int
    let rows: [Row]

    /// How many the weakest dimension contributes.
    static let suggestionLimit = 3

    static func make(
        week: [Ritual],
        library: [Ritual],
        unusedCustom: [Ritual],
        weekday: Int,
        weakest: RitualCategory?,
        arcGaps: [String],
        arcName: String? = nil,
        find: (String) -> Ritual?
    ) -> QuickAddCatalog {
        let held = Set(week.map(\.id))
        var placed: Set<String> = []
        var rows: [Row] = []

        func place(_ ritual: Ritual, in section: Section, detail: String? = nil) {
            guard placed.insert(ritual.id).inserted else { return }
            rows.append(Row(ritual: ritual, section: section, detail: detail))
        }

        // Suggested: the Arc's gaps, then the weakest dimension's smallest
        // three. Library activities only, and never one already in the week.
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in arcGaps where !held.contains(id) {
            if let ritual = byID[id] ?? find(id) {
                place(ritual, in: .suggested, detail: arcName.map { "Part of \($0)" })
            }
        }
        if let weakest {
            for suggestion in ForgeShape.suggestions(for: weakest, avoiding: held, limit: suggestionLimit) {
                place(byID[suggestion.id] ?? suggestion, in: .suggested,
                      detail: "Builds \(weakest.label.lowercased())")
            }
        }

        for ritual in week where !ritual.happens(on: weekday) {
            place(ritual, in: .inWeek, detail: ritual.repeats.label)
        }
        for ritual in unusedCustom where !held.contains(ritual.id) {
            place(ritual, in: .yours)
        }
        for ritual in library where !held.contains(ritual.id) {
            place(ritual, in: .library)
        }
        return QuickAddCatalog(weekday: weekday, rows: rows)
    }

    // MARK: - Reading it

    /// One section's rows, narrowed by the search and — in what is offered
    /// only — by the dimension chip.
    func rows(in section: Section, matching query: String, category: RitualCategory = .all) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isOffer = section == .suggested || section == .library
        return rows.filter { row in
            guard row.section == section else { return false }
            if isOffer, category != .all, row.ritual.category != category { return false }
            return query.isEmpty || row.ritual.label.localizedCaseInsensitiveContains(query)
        }
    }

    /// Whether a search found nothing anywhere — when the sheet offers to make
    /// it instead.
    func isEmpty(matching query: String, category: RitualCategory = .all) -> Bool {
        Section.allCases.allSatisfy { rows(in: $0, matching: query, category: category).isEmpty }
    }
}
