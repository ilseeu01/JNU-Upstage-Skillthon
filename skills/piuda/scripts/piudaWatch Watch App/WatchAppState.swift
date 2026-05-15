import Foundation
import HealthKit
import WatchConnectivity

@Observable
final class WatchAppState: NSObject {
    var stepCount: Int = 0
    var heartRate: Double = 0
    var hrv: Double = 0
    var isConnectedToPhone = false
    var testDoneThisWeek = false
    var lastSyncAt: Date?

    private let store = HKHealthStore()

    override init() {
        super.init()
        setupWCSession()
        testDoneThisWeek = UserDefaults.standard.bool(forKey: weekKey())
        Task { await startHealthMonitoring() }
    }

    // MARK: - WatchConnectivity

    private func setupWCSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func syncToPhone() {
        guard WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [
            "type": "healthUpdate",
            "date": Date().timeIntervalSince1970,
            "stepCount": stepCount,
            "heartRate": heartRate
        ]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
        lastSyncAt = Date()
    }

    func sendCognitiveResult(score: Double) {
        guard WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [
            "type": "cognitiveResult",
            "score": score,
            "date": Date().timeIntervalSince1970
        ]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
        testDoneThisWeek = true
        UserDefaults.standard.set(true, forKey: weekKey())
    }

    // MARK: - HealthKit

    func startHealthMonitoring() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var types = Set<HKObjectType>()
        if let hr    = HKObjectType.quantityType(forIdentifier: .heartRate)   { types.insert(hr) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount)   { types.insert(steps) }
        if let hrv   = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        try? await store.requestAuthorization(toShare: [], read: types)
        fetchTodaySteps()
        fetchLatestHeartRate()
    }

    private func fetchTodaySteps() {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let q = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
            options: .cumulativeSum
        ) { [weak self] _, stats, _ in
            let steps = Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            DispatchQueue.main.async {
                self?.stepCount = steps
                self?.syncToPhone()
            }
        }
        store.execute(q)
    }

    private func fetchLatestHeartRate() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { return }
            let hr = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async { self?.heartRate = hr }
        }
        store.execute(q)
    }

    private func weekKey() -> String {
        let week = Calendar.current.component(.weekOfYear, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        return "cogTestDone_\(year)_\(week)"
    }
}

// MARK: - WCSessionDelegate

extension WatchAppState: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isConnectedToPhone = state == .activated }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isConnectedToPhone = session.isReachable }
    }
}
