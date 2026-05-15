import Foundation
import HealthKit

@Observable
final class HealthKitService {
    private let store = HKHealthStore()
    var isAuthorized = false
    var lastError: String?

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .walkingSpeed,
            .stepCount,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .heartRateVariabilitySDNN,
            .restingHeartRate
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "이 기기에서는 HealthKit을 사용할 수 없습니다."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    // 특정 주의 일별 스냅샷 7개 반환
    func fetchWeeklySnapshots(for referenceDate: Date = Date()) async -> [HealthSnapshot] {
        let cal = Calendar.current
        let weekStart = cal.startOfWeek(for: referenceDate)
        var snapshots: [HealthSnapshot] = []

        for offset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: weekStart),
                  dayStart <= referenceDate else { continue }
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

            async let sleep = fetchSleep(from: dayStart, to: dayEnd)
            async let gait  = fetchGait(from: dayStart, to: dayEnd)
            async let heart = fetchHeart(from: dayStart, to: dayEnd)
            let (s, g, h) = await (sleep, gait, heart)

            snapshots.append(HealthSnapshot(
                date: dayStart,
                sleepEfficiency: s.efficiency,
                sleepDuration: s.duration,
                nightWakeCount: s.wakeCount,
                deepSleepRatio: s.deepRatio,
                walkingSpeed: g.speed,
                stepCount: g.steps,
                walkingAsymmetry: g.asymmetry,
                heartRateVariability: h.hrv,
                restingHeartRate: h.rhr
            ))
        }
        return snapshots
    }

    // MARK: - Private helpers

    private struct SleepResult {
        var efficiency: Double; var duration: TimeInterval; var wakeCount: Int; var deepRatio: Double
    }
    private struct GaitResult {
        var speed: Double; var steps: Int; var asymmetry: Double
    }
    private struct HeartResult {
        var hrv: Double; var rhr: Double
    }

    private func fetchSleep(from start: Date, to end: Date) async -> SleepResult {
        let fallback = SleepResult(efficiency: 0.78, duration: 6.5 * 3600, wakeCount: 1, deepRatio: 0.20)
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return fallback }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                   limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: fallback); return
                }
                var inBed: TimeInterval = 0, asleep: TimeInterval = 0
                var deep: TimeInterval = 0, wakes = 0
                for s in samples {
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                    case .inBed: inBed += dur
                    case .asleepCore, .asleepREM: asleep += dur
                    case .asleepDeep: asleep += dur; deep += dur
                    case .awake: wakes += 1
                    default: break
                    }
                }
                let eff = inBed > 0 ? min(1.0, asleep / inBed) : fallback.efficiency
                cont.resume(returning: SleepResult(
                    efficiency: eff, duration: asleep,
                    wakeCount: wakes, deepRatio: asleep > 0 ? deep / asleep : fallback.deepRatio
                ))
            }
            store.execute(q)
        }
    }

    private func fetchGait(from start: Date, to end: Date) async -> GaitResult {
        async let speed = avg(.walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()),
                               from: start, to: end, fallback: 1.2)
        async let steps = sum(.stepCount, unit: .count(), from: start, to: end, fallback: 5000)
        async let asym  = avg(.walkingAsymmetryPercentage, unit: .percent(),
                               from: start, to: end, fallback: 0.05)
        return await GaitResult(speed: speed, steps: Int(steps), asymmetry: asym)
    }

    private func fetchHeart(from start: Date, to end: Date) async -> HeartResult {
        async let hrv = avg(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli),
                             from: start, to: end, fallback: 35)
        async let rhr = avg(.restingHeartRate,
                             unit: HKUnit.count().unitDivided(by: .minute()),
                             from: start, to: end, fallback: 68)
        return await HeartResult(hrv: hrv, rhr: rhr)
    }

    private func avg(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                      from start: Date, to end: Date, fallback: Double) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return fallback }
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .discreteAverage
            ) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit) ?? fallback)
            }
            store.execute(q)
        }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                      from start: Date, to end: Date, fallback: Double) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return fallback }
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? fallback)
            }
            store.execute(q)
        }
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        var comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return self.date(from: comps) ?? date
    }
}
