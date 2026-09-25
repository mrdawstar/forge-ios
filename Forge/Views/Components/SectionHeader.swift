import SwiftUI

struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.9)
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// A section heading in sentence case, for screens that read as prose.
///
/// The counterpart to `SectionHeader` above, and the two are deliberately
/// different rather than one component with a style flag. `SectionHeader` is a
/// tracked, uppercase label — it marks a *region of data*, and it is what the
/// Blade tab and the analytics sheet use. This one is a plain sentence at
/// reading size, and it marks a *part of an argument*: the screens that use it
/// are read top to bottom, and an uppercase tracked label in the middle of that
/// reads as a form heading rather than as the next thing being said.
///
/// It moved here when the archetypes were removed. It had been living in the
/// shelf's file, which meant deleting a feature took a component two unrelated
/// screens depended on down with it — the reason a shared control belongs in
/// `Components` even when only one screen uses it on the day it is written.
struct SectionHeading: View {
    let title: String
    var detail: String? = nil

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
