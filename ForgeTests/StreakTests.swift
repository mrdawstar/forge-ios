import Foundation
import Testing
@testable import Forge

/// Streaks read out of history rather than being kept, so these check the
/// reading — including the two cases that make users angriest when they are
/// wrong: a day that has not happened yet reading as a miss, and a rest day
/// reading as one.