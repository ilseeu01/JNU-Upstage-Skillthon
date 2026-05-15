import Foundation
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@Observable
final class AppState {

    // MARK: - User state
    var userProfile: UserProfile?
    var isOnboarded: Bool = false

    /// 현재 모니터링 중인 데이터셋 피험자(어르신) ID. nil 이면 기본값 사용.
    var selectedSubjectID: String?

    // MARK: - Data
    var reports: [WeeklyReport] = []
    var alerts: [DementiaAlert] = []

    // MARK: - Services
    let healthKit       = HealthKitService()
    let agent           = DementiaAgentService()
    let notifications   = NotificationService.shared
    let calendar        = CalendarService()
    let watchService    = WatchConnectivityService()
    let firebase        = FirebaseService.shared
    let demoData        = DemoDataService()   // 치매 고위험군 라이프로그 데이터셋 로더

    // MARK: - UI
    var isLoading       = false
    var errorMessage: String?
    var showError       = false

    var unreadAlertCount: Int { alerts.filter { !$0.isAcknowledged }.count }
    var latestReport: WeeklyReport? { reports.first }
    var elderName: String { userProfile?.name ?? selectedSubject?.displayName ?? "어르신" }

    // MARK: - Demo dataset (치매 고위험군 라이프로그)

    /// 데이터셋에서 불러온 피험자 목록 (CN/MCI/Dem 진단 라벨 포함).
    var availableSubjects: [DemoSubject] { demoData.subjects }

    /// 현재 선택된 피험자. 미선택 시 MCI(경계선) 사례를 기본 — 데모에 가장 적합.
    var selectedSubject: DemoSubject? {
        if let id = selectedSubjectID, let s = demoData.subject(id: id) { return s }
        return demoData.subjects.first { $0.diagnosis == "MCI" } ?? demoData.subjects.first
    }

    /// 모니터링 대상 어르신을 바꾸고 데이터를 다시 불러온다.
    func selectDemoSubject(_ id: String) {
        selectedSubjectID = id
        loadDemoData()
    }

    // MARK: - Init

    init() {
        loadProfile()
        if isOnboarded {
            setupWatchConnectivity()
            Task { await loadInitialData() }
        }
    }

    // MARK: - Onboarding

    func completeOnboarding(profile: UserProfile) {
        saveProfile(profile)
        setupWatchConnectivity()
        Task {
            _ = await notifications.requestPermission()
            await healthKit.requestAuthorization()
            notifications.scheduleWeeklyReport()

            // Firebase에 프로필 저장
            #if canImport(FirebaseFirestore)
            try? await firebase.saveProfile(profile)
            await startFirebaseListeners(for: profile)
            #endif

            await loadInitialData()
        }
    }

    func logout() {
        #if canImport(FirebaseFirestore)
        firebase.removeListeners()
        #endif
        UserDefaults.standard.removeObject(forKey: "userProfile")
        userProfile = nil
        isOnboarded = false
        reports = []
        alerts  = []
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        #if canImport(FirebaseFirestore)
        await loadFromFirebase()
        #else
        loadDemoData()
        #endif
    }

    // MARK: - Analysis (AI Agent 메인 루틴)

    func runAnalysis() async {
        guard let profile = userProfile else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // HealthKit 데이터 수집
            let thisWeek = await healthKit.fetchWeeklySnapshots()
            let lastWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
            let lastWeek = await healthKit.fetchWeeklySnapshots(for: lastWeekDate)

            // 데이터 우선순위: 실제 HealthKit → 데이터셋 피험자 → 최후의 mock
            let snaps: [HealthSnapshot]
            let prevSnaps: [HealthSnapshot]?
            if !thisWeek.isEmpty {
                snaps = thisWeek
                prevSnaps = lastWeek.isEmpty ? nil : lastWeek
            } else if let subject = selectedSubject, !subject.thisWeekSnapshots.isEmpty {
                snaps = subject.thisWeekSnapshots
                prevSnaps = subject.previousWeekSnapshots
            } else {
                snaps = mockSnapshots(degraded: false)
                prevSnaps = nil
            }

            // Watch 데이터 병합 (오늘 수신된 데이터가 있으면)
            let mergedSnaps = mergeWatchData(into: snaps)

            let name = elderName
            let report = try await agent.runWeeklyAnalysis(
                elderName: name,
                snapshots: mergedSnaps,
                previousSnapshots: prevSnaps
            )

            await MainActor.run { reports.insert(report, at: 0) }

            // Firebase 저장
            #if canImport(FirebaseFirestore)
            let elderPhone = profile.role == .elder
                ? profile.phoneNumber
                : (profile.pairedPhoneNumber ?? "")
            if !elderPhone.isEmpty {
                try? await firebase.saveReport(report, elderPhone: elderPhone)
                for snap in mergedSnaps {
                    try? await firebase.saveSnapshot(snap, elderPhone: elderPhone)
                }
            }
            #endif

            // 위험 감지 → 알림 + Firebase 저장
            if agent.shouldAlert(report) {
                let alertObj = try await agent.buildAlert(from: report, elderName: name)
                await MainActor.run { alerts.insert(alertObj, at: 0) }
                await notifications.sendRiskAlert(alertObj)

                #if canImport(FirebaseFirestore)
                let caregiverPhone = profile.role == .caregiver
                    ? profile.phoneNumber
                    : (profile.pairedPhoneNumber ?? "")
                if !caregiverPhone.isEmpty {
                    try? await firebase.saveAlert(alertObj, caregiverPhone: caregiverPhone)
                }
                #endif
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func acknowledgeAlert(id: UUID) {
        if let i = alerts.firstIndex(where: { $0.id == id }) {
            alerts[i].isAcknowledged = true
        }
        #if canImport(FirebaseFirestore)
        if let phone = userProfile?.phoneNumber {
            Task { try? await firebase.acknowledgeAlert(id: id, caregiverPhone: phone) }
        }
        #endif
    }

    func scheduleAppointment(
        hospital: Hospital,
        date: Date,
        alertId: UUID
    ) async throws -> HospitalAppointment {
        let eventId = try await calendar.addAppointment(hospital: hospital, date: date)
        let appt = HospitalAppointment(
            hospital: hospital,
            scheduledDate: date,
            calendarEventId: eventId,
            notes: "피우다 앱에서 예약됨"
        )
        notifications.scheduleAppointmentReminder(for: appt)

        if let i = alerts.firstIndex(where: { $0.id == alertId }) {
            alerts[i].scheduledAppointment = appt
            alerts[i].isAcknowledged = true
        }

        #if canImport(FirebaseFirestore)
        if let phone = userProfile?.phoneNumber {
            try? await firebase.saveAppointment(appt, alertId: alertId, caregiverPhone: phone)
        }
        #endif

        return appt
    }

    // MARK: - WatchConnectivity

    private func setupWatchConnectivity() {
        watchService.onSnapshotReceived = { [weak self] payload in
            self?.handleWatchPayload(payload)
        }
        watchService.onCognitiveResultReceived = { [weak self] score in
            self?.handleCognitiveResult(score)
        }
    }

    private func handleWatchPayload(_ payload: WatchHealthPayload) {
        // 오늘 날짜 스냅샷에 Watch 데이터 반영
        let cal = Calendar.current
        if let i = reports.first?.snapshots.firstIndex(where: { cal.isDate($0.date, inSameDayAs: payload.date) }) {
            reports[0].snapshots[i].stepCount = max(reports[0].snapshots[i].stepCount, payload.stepCount)
            if payload.heartRate > 0 {
                reports[0].snapshots[i].restingHeartRate = payload.heartRate
            }
        }
    }

    private func handleCognitiveResult(_ score: Double) {
        // 가장 최근 스냅샷에 인지 점수 업데이트
        if !reports.isEmpty, !reports[0].snapshots.isEmpty {
            let last = reports[0].snapshots.count - 1
            reports[0].snapshots[last].cognitiveScore = score
        }
    }

    private func mergeWatchData(into snapshots: [HealthSnapshot]) -> [HealthSnapshot] {
        guard let payload = watchService.lastReceivedSnapshot else { return snapshots }
        let cal = Calendar.current
        return snapshots.map { snap in
            guard cal.isDate(snap.date, inSameDayAs: payload.date) else { return snap }
            var merged = snap
            merged.stepCount = max(snap.stepCount, payload.stepCount)
            if payload.heartRate > 0 { merged.restingHeartRate = payload.heartRate }
            if let cog = payload.cognitiveScore { merged.cognitiveScore = cog }
            return merged
        }
    }

    // MARK: - Firebase Sync

    #if canImport(FirebaseFirestore)
    private func loadFromFirebase() async {
        guard let profile = userProfile else { loadMockData(); return }

        let elderPhone = profile.role == .elder
            ? profile.phoneNumber
            : (profile.pairedPhoneNumber ?? "")

        guard !elderPhone.isEmpty else { loadMockData(); return }

        do {
            let fetchedReports = try await firebase.fetchReports(elderPhone: elderPhone)
            await MainActor.run {
                if fetchedReports.isEmpty { loadMockData() }
                else { reports = fetchedReports }
            }
            await startFirebaseListeners(for: profile)
        } catch {
            loadMockData()
        }
    }

    func startFirebaseListeners(for profile: UserProfile) async {
        firebase.removeListeners()

        let caregiverPhone = profile.role == .caregiver
            ? profile.phoneNumber
            : (profile.pairedPhoneNumber ?? "")

        let elderPhone = profile.role == .elder
            ? profile.phoneNumber
            : (profile.pairedPhoneNumber ?? "")

        // 보호자: 새 알림 실시간 수신
        if !caregiverPhone.isEmpty {
            firebase.listenForAlerts(caregiverPhone: caregiverPhone) { [weak self] alert in
                guard let self else { return }
                if !self.alerts.contains(where: { $0.id == alert.id }) {
                    self.alerts.insert(alert, at: 0)
                    Task { await self.notifications.sendRiskAlert(alert) }
                }
            }
        }

        // 새 리포트 실시간 수신
        if !elderPhone.isEmpty {
            firebase.listenForNewReport(elderPhone: elderPhone) { [weak self] report in
                guard let self else { return }
                if !self.reports.contains(where: { $0.id == report.id }) {
                    self.reports.insert(report, at: 0)
                }
            }
        }
    }
    #endif

    // MARK: - Persistence (Local)

    private func saveProfile(_ profile: UserProfile) {
        userProfile = profile
        isOnboarded = true
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "userProfile")
        }
    }

    private func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: "userProfile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = profile
            isOnboarded = true
        }
    }

    // MARK: - Demo Dataset Loading (치매 라이프로그 → WeeklyReport)

    /// 선택된 피험자의 주간 데이터를 WeeklyReport 목록으로 변환해 채운다.
    /// 데이터셋을 못 읽으면 mock 데이터로 폴백한다.
    func loadDemoData() {
        guard demoData.isLoaded, let subject = selectedSubject else {
            if let err = demoData.loadError { errorMessage = err }
            loadMockData()
            return
        }
        selectedSubjectID = subject.subjectId
        reports = []
        alerts = []

        // weekIndex 오름차순(0=최근) 순회 → reports[0] 이 최신 주가 되도록
        let weeks = subject.weeks.sorted { $0.weekIndex < $1.weekIndex }
        for week in weeks {
            let snaps = week.snapshots.map(\.asHealthSnapshot)
            guard !snaps.isEmpty else { continue }
            let prev = weeks.first { $0.weekIndex == week.weekIndex + 1 }?
                .snapshots.map(\.asHealthSnapshot)
            reports.append(buildLocalReport(snapshots: snaps, previous: prev))
        }

        // 최신 주가 '주의' 이상이면 보호자 알림 1건 생성
        if let latest = reports.first, agent.shouldAlert(latest) {
            alerts.append(DementiaAlert(
                riskLevel: latest.riskLevel,
                title: "\(subject.displayName) 건강 변화 감지",
                message: latest.narrative,
                triggerFactors: latest.keyFindings,
                recommendedHospitals: agent.recommendedHospitals(for: latest.riskLevel),
                relatedReportId: latest.id
            ))
        }
    }

    /// LLM 호출 없이 위험 점수 계산만으로 WeeklyReport 를 만든다.
    /// 앱 실행 시 4주치를 한꺼번에 API 호출하지 않기 위함 — 최신 주는
    /// 사용자가 "AI 분석"을 실행하면 runAnalysis() 가 Upstage 리포트로 갱신한다.
    private func buildLocalReport(snapshots: [HealthSnapshot],
                                  previous: [HealthSnapshot]?) -> WeeklyReport {
        let prevAvg = previous.map { agent.average($0) }
        let (score, level, factors) = agent.calculateRisk(snapshots: snapshots, baseline: prevAvg)
        let avg = agent.average(snapshots)
        let weekStart = snapshots.map(\.date).min() ?? Date()
        let weekEnd   = snapshots.map(\.date).max() ?? Date()

        var sleepTrend = 0.0, walkTrend = 0.0, hrvTrend = 0.0
        if let p = prevAvg {
            sleepTrend = percentChange(avg.sleepEfficiency, p.sleepEfficiency)
            walkTrend  = percentChange(avg.walkingSpeed, p.walkingSpeed)
            hrvTrend   = percentChange(avg.heartRateVariability, p.heartRateVariability)
        }

        return WeeklyReport(
            weekStart: weekStart, weekEnd: weekEnd,
            riskLevel: level, riskScore: score,
            narrative: level.description,
            keyFindings: factors.isEmpty ? ["뚜렷한 이상 신호 없음"] : factors,
            recommendations: AppState.recommendations(for: level),
            snapshots: snapshots, generatedAt: Date(),
            sleepTrend: sleepTrend, walkingTrend: walkTrend, hrvTrend: hrvTrend
        )
    }

    private func percentChange(_ current: Double, _ previous: Double) -> Double {
        guard previous != 0 else { return 0 }
        return (current - previous) / previous * 100
    }

    private static func recommendations(for level: RiskLevel) -> [String] {
        switch level {
        case .low:
            return ["현재 생활 패턴 유지", "주간 인지 테스트 꾸준히 진행"]
        case .moderate:
            return ["규칙적인 취침·기상 시간 유지", "낮 시간 가벼운 산책 권장"]
        case .high:
            return ["신경과 또는 치매안심센터 상담 권장", "수면 환경 점검"]
        case .critical:
            return ["가까운 신경과 진료를 빠른 시일 내 권장", "보호자 동행 필요"]
        }
    }

    // MARK: - Mock Data

    func loadMockData() {
        let cal = Calendar.current
        reports = []
        alerts  = []

        let configs: [(weekOffset: Int, degraded: Bool, level: RiskLevel, score: Int)] = [
            (0, true,  .high,     8),
            (1, false, .moderate, 4),
            (2, false, .low,      1),
            (3, false, .low,      2)
        ]

        for config in configs {
            let ref       = cal.date(byAdding: .weekOfYear, value: -config.weekOffset, to: Date())!
            let weekStart = cal.startOfWeek(for: ref)
            let weekEnd   = cal.date(byAdding: .day, value: 6, to: weekStart)!

            let snaps = (0..<7).compactMap { offset -> HealthSnapshot? in
                guard let day = cal.date(byAdding: .day, value: offset, to: weekStart),
                      day <= Date() else { return nil }
                return .mock(for: day, degraded: config.degraded && offset > 3)
            }

            let narratives = [
                "이번 주 어르신의 수면 패턴에 주목할 만한 변화가 감지되었습니다. 수면 효율이 전주 대비 18% 감소하였고, 야간 각성 횟수도 증가하였습니다. 보행 속도 또한 다소 느려진 것이 관찰됩니다. 빠른 시일 내에 전문 의료기관 방문을 검토해 주세요.",
                "전주에 비해 전반적인 활동 지표가 소폭 감소하였습니다. 특히 수면의 질에 변화가 있었습니다. 지속적인 관찰이 필요합니다.",
                "이번 주 어르신의 전반적인 건강 지표는 양호합니다. 수면·보행·심박 모두 정상 범위에서 유지되고 있습니다.",
                "전반적으로 안정적인 한 주였습니다. 걸음 수와 수면의 질이 모두 양호합니다."
            ]
            let findings: [[String]] = [
                ["수면 효율 18% 감소", "야간 각성 평균 4.2회", "보행 속도 12% 저하"],
                ["수면 효율 소폭 감소", "보행 속도 정상 범위"],
                ["전반 지표 정상", "활동량 양호"],
                ["수면 정상", "활동량 정상"]
            ]
            let recs: [[String]] = [
                ["신경과·치매안심센터 방문 권장", "규칙적인 취침 시간 유지", "낮 시간 가벼운 산책"],
                ["규칙적인 생활 패턴 유지", "충분한 수분 섭취"],
                ["현재 생활 패턴 유지", "주간 인지 테스트 계속하기"],
                ["현재 생활 패턴 유지"]
            ]
            let trends: [(Double, Double, Double)] = [(-18, -12, -15), (-5, 2, -3), (3, 1, 2), (1, 0, 1)]

            reports.append(WeeklyReport(
                weekStart: weekStart, weekEnd: weekEnd,
                riskLevel: config.level, riskScore: config.score,
                narrative: narratives[config.weekOffset],
                keyFindings: findings[config.weekOffset],
                recommendations: recs[config.weekOffset],
                snapshots: snaps, generatedAt: Date(),
                sleepTrend: trends[config.weekOffset].0,
                walkingTrend: trends[config.weekOffset].1,
                hrvTrend: trends[config.weekOffset].2
            ))
        }

        if let latest = reports.first, latest.riskLevel >= .high {
            alerts.append(DementiaAlert(
                riskLevel: .high,
                title: "어르신 건강 변화 감지",
                message: "이번 주 수면과 보행 지표에 유의미한 변화가 감지되었습니다. 전문의 상담을 권장합니다.",
                triggerFactors: latest.keyFindings,
                recommendedHospitals: Hospital.recommendations,
                relatedReportId: latest.id
            ))
        }
    }

    private func mockSnapshots(degraded: Bool) -> [HealthSnapshot] {
        let cal = Calendar.current
        let start = cal.startOfWeek(for: Date())
        return (0..<7).compactMap { offset -> HealthSnapshot? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  day <= Date() else { return nil }
            return .mock(for: day, degraded: degraded)
        }
    }
}
