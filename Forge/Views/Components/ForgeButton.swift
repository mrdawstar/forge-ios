import SwiftUI

enum ForgeButtonStyle {
    case primary, secondary, destructive
}

/// Thin wrapper over the native Liquid Glass button styles.
///
/// The old implementation drew its own capsule fill, stroke and drop shadow.
/// iOS 26 ships `.glassProminent` and `.glass`, which give the same visual
/// weight plus the correct press, focus and accessibility behaviour, so this
/// view now only picks a style and a tint.
struct ForgeButton: View {
    let title: String
    var style: ForgeButtonStyle = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The width has to be on the label: the glass button styles size
            // their capsule to the label, not to the button's frame.
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
            .controlSize(.extraLarge)
            .buttonBorderShape(.capsule)
            .modifier(ForgeButtonStyleModifier(style: style))
    }
}

/// The one primary action on a screen, with room for it to be busy.
///
/// `ForgeButton` in its primary style, plus a spinner that replaces the title
/// while something the button started is still running — a purchase, above
/// all, where a second tap must be impossible and the first must visibly have
/// landed. Disabled while busy.
struct ForgePrimaryButton: View {
    let title: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .tint(Color(red: 0.063, green: 0.063, blue: 0.078))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.extraLarge)
        .buttonBorderShape(.capsule)
        .modifier(ForgeButtonStyleModifier(style: .primary))
        .disabled(isBusy)
        .accessibilityLabel(Text(title))
    }
}

private struct ForgeButtonStyleModifier: ViewModifier {
    let style: ForgeButtonStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content
                .buttonStyle(.glassProminent)
                .tint(ForgeTheme.cream)
                .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
        case .secondary:
            content
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
        case .destructive:
            content
                .buttonStyle(.glass)
                .tint(ForgeTheme.destructive)
                .foregroundStyle(ForgeTheme.destructive)
        }
    }
}
