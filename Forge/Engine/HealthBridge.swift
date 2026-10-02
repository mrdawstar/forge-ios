import Foundation
import HealthKit

/// Apple Health, read-only, on the device (DIRECTION_1_1 §8).
///
/// # Read-only, forever
///
/// Forge reads four types: steps, workouts, sleep analysis and mindful
/// sessions. It writes none, and there is no `save`, no sample construction
/// and no delete anywhere in the app. `requestAuthorization` is called with an
/// **empty share set**, and that set must stay empty: the purpose string for
/// writing (`NSHealthUpdateUsageDescription`) says Forge writes nothing, and
/// it is only in `Info.plist` because upload validation asks for both strings
/// whenever the entitlement is present (FORGE_CONTEXT §2m).
///
/// # Nothing leaves the phone, nothing is kept
///
/// A reading is used the moment it arrives, to decide whether an activity is
/// done, and dropped. It is never written to disk, never sent to telemetry,
/// never put in an `AIBrief`. What is stored is the completion it caused,
/// banked as `.health` in the day's record like any other completion.
///
/// # When it reads
///
/// When the app becomes active, when the Forge tab appears, on a tap on a
/// Health row, and when HealthKit says something changed (`HKObserverQuery`,
/// with background delivery). Every one of those ends in
/// `ForgeViewModel.sweepHealth`, which is the only thing that completes
/// anything. Nothing here runs before somebody has said Continue on the
/// primer: never at launch for a new install, never in the first run.
final class HealthBridge: HealthReading, @unchecked Sendable {

    static let shared = HealthBridge()

    private let store = HKHealthStore()

    /// Called on the main actor when HealthKit reports new samples of a type
    /// Forge reads. Set by `ContentView` to the day's sweep. Nil when the app
    /// was woken in the background without a window, in which case the next
    /// open sweeps instead.
    @MainActor var onUpdate: (@MainActor () async -> Void)?

    private var isObserving = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - The four types

    /// Exactly what the primer lists and the purpose string names. Adding a
    /// type here means adding it to both.
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKObjectType.workoutType(),
        HKCategoryType(.sleepAnalysis),
        HKCategoryType(.mindfulSession),
    ]

    private static func sampleType(for metric: ActivityMetric) -> HKSampleType {
        switch metric {
        case .steps: HKQuantityType(.stepCount)
        case .workoutMinutes: HKObjectType.workoutType()
        case .sleepMinutes: HKCategoryType(.sleepAnalysis)
        case .mindfulMinutes: HKCategoryType(.mindfulSession)
        }
    }

    // MARK: - Permission

    func requestReadAccess() async {
        guard isAvailable else { return }
        // Read-only. This share set MUST stay empty: Forge never writes to
        // Health, and the update purpose string says so (FORGE_CONTEXT §2m).
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Reading

    /// HealthKit does not say whether reading was allowed: a refusal looks
    /// exactly like an empty Health app. So the question asked is the one that
    /// can be answered, whether there is anything at all of each type Forge
    /// can see. A phone counts steps by itself, so for almost everybody an
    /// allowed Health shows steps on the first read.
    func visibleMetrics() async -> Set<ActivityMetric> {
        guard isAvailable else { return [] }
        var visible: Set<ActivityMetric> = []
        for metric in ActivityMetric.allCases where await hasAnySample(of: Self.sampleType(for: metric)) {
            visible.insert(metric)
        }
        return visible
    }

    func value(
        of measure: ActivityMeasure, on day: ForgeDay, dayStartHour: Int
    ) async -> Int? {
        guard isAvailable else { return nil }
        let window = HealthWindow.window(
            for: measure.metric, on: day, dayStartHour: dayStartHour
        )
        switch measure.metric {
        case .steps:
            return await steps(in: window)
        case .workoutMinutes:
            let intervals = await workouts(in: window, kind: measure.workout)
            return HealthMath.minutes(of: intervals, within: window)
        case .sleepMinutes:
            let intervals = await categoryIntervals(
                HKCategoryType(.sleepAnalysis), in: window,
                only: HKCategoryValueSleepAnalysis.predicateForSamples(
                    equalTo: HKCategoryValueSleepAnalysis.allAsleepValues
                )
            )
            return HealthMath.minutes(of: intervals, within: window)
        case .mindfulMinutes:
            let intervals = await categoryIntervals(HKCategoryType(.mindfulSession), in: window)
            return HealthMath.minutes(of: intervals, within: window)
        }
    }

    /// Steps over the window, through a statistics query rather than a sum of
    /// samples: Health removes the overlap between a phone and a watch
    /// counting the same walk, and a hand-made sum would count it twice.
    private func steps(in window: DateInterval) async -> Int? {
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start, end: window.end, options: []
        )
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let sum = statistics?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: sum.map { Int($0.rounded(.down)) })
            }
            store.execute(query)
        }
    }

    /// Each workout's span, clipped later to the window by `HealthMath`.
    /// `kind` narrows to running for a run and to strength training for a
    /// lift; nil counts every workout.
    private func workouts(in window: DateInterval, kind: WorkoutKind?) async -> [DateInterval] {
        var predicates = [
            HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: []),
        ]
        if let kind {
            let types = Self.activityTypes(for: kind).map {
                HKQuery.predicateForWorkouts(with: $0)
            }
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: types))
        }
        let samples = await samples(
            of: .workoutType(),
            matching: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        )
        return samples.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
    }

    private static func activityTypes(for kind: WorkoutKind) -> [HKWorkoutActivityType] {
        switch kind {
        case .running: [.running]
        case .strength: [.traditionalStrengthTraining, .functionalStrengthTraining]
        }
    }

    private func categoryIntervals(
        _ type: HKCategoryType, in window: DateInterval, only extra: NSPredicate? = nil
    ) async -> [DateInterval] {
        var predicates = [
            HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: []),
        ]
        if let extra { predicates.append(extra) }
        let samples = await samples(
            of: type, matching: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        )
        return samples.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
    }

    private func samples(of type: HKSampleType, matching predicate: NSPredicate) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private func hasAnySample(of type: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    // MARK: - Being told

    /// One observer per type, and background delivery where HealthKit allows
    /// it: hourly for steps (its ceiling), immediately for the rest. Called
    /// at launch **only** once somebody has said Continue on the primer
    /// (`HealthLedger.Decision.asked`), and straight after they do. Starting an
    /// observer asks nothing of anybody: no sheet, no prompt.
    func startObserving() {
        guard isAvailable, !isObserving else { return }
        isObserving = true
        for metric in ActivityMetric.allCases {
            let type = Self.sampleType(for: metric)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, done, error in
                guard error == nil, let self else { done(); return }
                Task { @MainActor in
                    await self.onUpdate?()
                    done()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(
                for: type, frequency: metric == .steps ? .hourly : .immediate
            ) { _, _ in }
        }
    }
}
