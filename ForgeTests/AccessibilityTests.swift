import SwiftUI
import Testing

@testable import Forge

/// The parts of accessibility a test can actually hold.
///
/// VoiceOver labels, Dynamic Type reflow and Reduce Motion are checked by hand
/// on a device — a unit test cannot tell whether a label reads well out loud.
/// **Contrast can be measured**, and it is the one that silently rots: every
/// new archetype adds an accent, an accent is the only colour allowed on a
/// button, and nobody notices a 3:1 ratio by looking at it on a bright desk.
///
/// So this file measures the thing that is measurable and leaves the rest to
/// the device pass recorded in `FORGE_CONTEXT.md` §12.