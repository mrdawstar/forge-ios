import SwiftUI

/// Seven-day toggle strip.
///
/// There is no native weekday multi-picker, so the control stays custom — but
/// the fills, strokes and highlights are now native glass instead of stacked
/// translucent rectangles, and the whole row lives in a `GlassEffectContainer`
/// so the segments blend into each other the way system controls do.
struct DayPicker: View {
    @Binding var days: [Bool]
    var activeTint: Color = ForgeTheme.cream
    /// Spoken value for a day that is on / off, so the same control can read
    /// correctly as both a rest-day picker and a schedule-day picker.
    var onDescription: String = "On"
    var offDescription: String = "Off"

    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        GlassEffectContainer(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            days[i].toggle()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(labels[i])
                                .font(.system(size: 13, weight: days[i] ? .semibold : .medium))
                            Circle()
                                .fill(days[i] ? Color.black.opacity(0.45) : Color.secondary)
                                .frame(width: 4, height: 4)
                                .scaleEffect(days[i] ? 1 : 0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(days[i] ? Color(red: 0.063, green: 0.063, blue: 0.078) : .secondary)
                    .glassEffect(
                        days[i]
                            ? .regular.tint(activeTint).interactive()
                            : .regular.interactive(),
                        in: .rect(cornerRadius: ForgeTheme.Radius.chip)
                    )
                    .accessibilityLabel(Text(fullDayName(i)))
                    .accessibilityValue(Text(days[i] ? onDescription : offDescription))
                }
            }
        }
    }

    private func fullDayName(_ index: Int) -> String {
        Calendar.current.weekdaySymbols[index]
    }
}
