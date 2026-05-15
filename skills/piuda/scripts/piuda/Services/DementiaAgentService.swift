import Foundation

// AI Agent: 위험도 분석 → 리포트 생성 → 알림 판단 → 병원 추천
@Observable
final class DementiaAgentService {
    var isProcessing = false
    var lastRunAt: Date?

    private let upstage = UpstageService.shared

    // MARK: - 위험도 점수 계산

    func calculateRisk(
        snapshots: [HealthSnapshot],
        baseline: HealthSnapshot? = nil
    ) -> (score: Int, level: RiskLevel, factors: [String]) {
        guard !snapshots.isEmpty else { return (0, .low, []) }

        let avg  = average(snapshots)
        let base = baseline ?? typicalBaseline()
        var score = 0
        var factors: [String] = []

        // 수면 효율
        let sleepDrop = (base.sleepEfficiency - avg.sleepEfficiency) / base.sleepEfficiency
        if sleepDrop > 0.20 {
            score += 3
            factors.append("수면 효율 \(Int(sleepDrop * 100))% 감소")
        } else if sleepDrop > 0.10 {
            score += 1
            factors.append("수면 효율 소폭 감소")
        }

        // 야간 각성
        if avg.nightWakeCount >= 4 {
            score += 2
            factors.append("야간 각성 평균 \(avg.nightWakeCount)회/일")
        } else if avg.nightWakeCount >= 2 {
            score += 1
            factors.append("야간 각성 횟수 증가")
        }

        // 보행 속도
        let walkDrop = (base.walkingSpeed - avg.walkingSpeed) / base.walkingSpeed
        if walkDrop > 0.15 {
            score += 3
            factors.append("보행 속도 \(Int(walkDrop * 100))% 감소")
        } else if walkDrop > 0.08 {
            score += 1
            factors.append("보행 속도 소폭 저하")
        }

        // HRV
        let hrvDrop = (base.heartRateVariability - avg.heartRateVariability) / base.heartRateVariability
        if hrvDrop > 0.30 {
            score += 2
            factors.append("심박 변이도(HRV) 큰 폭 감소")
        } else if hrvDrop > 0.15 {
            score += 1
            factors.append("심박 변이도 변화 감지")
        }

        // 걸음 수
        if avg.stepCount < 2000 {
            score += 2
            factors.append("하루 평균 \(avg.stepCount)보 — 활동량 매우 적음")
        } else if avg.stepCount < 4000 {
            score += 1
            factors.append("활동량 감소")
        }

        // 인지 테스트
        if let cog = avg.cognitiveScore {
            if cog < 50 {
                score += 5
                factors.append("인지 테스트 \(Int(cog))점 — 주의 필요")
            } else if cog < 65 {
                score += 3
                factors.append("인지 테스트 점수 저하 (\(Int(cog))점)")
            } else if cog < 75 {
                score += 1
                factors.append("인지 테스트 점수 평균 이하")
            }
        }

        let level: RiskLevel
        switch score {
        case 0...2:  level = .low
        case 3...5:  level = .moderate
        case 6...9:  level = .high
        default:     level = .critical
        }

        return (score, level, factors)
    }

    // MARK: - 주간 분석 실행 (AI Agent 메인 루틴)

    func runWeeklyAnalysis(
        elderName: String,
        snapshots: [HealthSnapshot],
        previousSnapshots: [HealthSnapshot]?
    ) async throws -> WeeklyReport {
        isProcessing = true
        defer { isProcessing = false }

        let prevAvg = previousSnapshots.map { average($0) }
        let (score, level, factors) = calculateRisk(snapshots: snapshots, baseline: prevAvg)

        let weekStart = snapshots.map(\.date).min() ?? Date()
        let weekEnd   = snapshots.map(\.date).max() ?? Date()

        // Upstage Solar LLM으로 자연어 리포트 생성
        let (narrative, keyFindings, recommendations) = try await upstage.generateWeeklyReport(
            snapshots: snapshots,
            previousAvg: prevAvg,
            elderName: elderName
        )

        // 트렌드 계산
        let avg = average(snapshots)
        var sleepTrend  = 0.0
        var walkTrend   = 0.0
        var hrvTrend    = 0.0
        if let prev = prevAvg {
            sleepTrend = (avg.sleepEfficiency - prev.sleepEfficiency) / prev.sleepEfficiency * 100
            walkTrend  = (avg.walkingSpeed - prev.walkingSpeed) / prev.walkingSpeed * 100
            hrvTrend   = (avg.heartRateVariability - prev.heartRateVariability) / prev.heartRateVariability * 100
        }

        lastRunAt = Date()

        return WeeklyReport(
            weekStart: weekStart,
            weekEnd: weekEnd,
            riskLevel: level,
            riskScore: score,
            narrative: narrative.isEmpty ? level.description : narrative,
            keyFindings: keyFindings.isEmpty ? factors : keyFindings,
            recommendations: recommendations,
            snapshots: snapshots,
            generatedAt: Date(),
            sleepTrend: sleepTrend,
            walkingTrend: walkTrend,
            hrvTrend: hrvTrend
        )
    }

    // MARK: - 알림 생성

    func buildAlert(from report: WeeklyReport, elderName: String) async throws -> DementiaAlert {
        let (title, message) = try await upstage.generateAlertMessage(
            riskLevel: report.riskLevel,
            factors: report.keyFindings,
            elderName: elderName
        )
        return DementiaAlert(
            riskLevel: report.riskLevel,
            title: title,
            message: message,
            triggerFactors: report.keyFindings,
            recommendedHospitals: recommendedHospitals(for: report.riskLevel),
            relatedReportId: report.id
        )
    }

    func shouldAlert(_ report: WeeklyReport) -> Bool {
        report.riskLevel >= .moderate
    }

    // MARK: - 병원 추천

    func recommendedHospitals(for level: RiskLevel) -> [Hospital] {
        switch level {
        case .low:              return []
        case .moderate:         return Hospital.recommendations.filter { $0.specialty == "치매 상담·검사" }
        case .high, .critical:  return Array(Hospital.recommendations.prefix(4))
        }
    }

    // MARK: - Helpers

    func average(_ snapshots: [HealthSnapshot]) -> HealthSnapshot {
        guard !snapshots.isEmpty else { return .mock(for: Date()) }
        let n = Double(snapshots.count)
        return HealthSnapshot(
            date: snapshots[0].date,
            sleepEfficiency:      snapshots.map(\.sleepEfficiency).reduce(0, +) / n,
            sleepDuration:        snapshots.map(\.sleepDuration).reduce(0, +) / n,
            nightWakeCount:       Int(snapshots.map { Double($0.nightWakeCount) }.reduce(0, +) / n),
            deepSleepRatio:       snapshots.map(\.deepSleepRatio).reduce(0, +) / n,
            walkingSpeed:         snapshots.map(\.walkingSpeed).reduce(0, +) / n,
            stepCount:            Int(snapshots.map { Double($0.stepCount) }.reduce(0, +) / n),
            walkingAsymmetry:     snapshots.map(\.walkingAsymmetry).reduce(0, +) / n,
            heartRateVariability: snapshots.map(\.heartRateVariability).reduce(0, +) / n,
            restingHeartRate:     snapshots.map(\.restingHeartRate).reduce(0, +) / n,
            cognitiveScore: {
                let s = snapshots.compactMap(\.cognitiveScore)
                return s.isEmpty ? nil : s.reduce(0, +) / Double(s.count)
            }()
        )
    }

    private func typicalBaseline() -> HealthSnapshot {
        HealthSnapshot(
            date: Date(),
            sleepEfficiency: 0.82, sleepDuration: 7 * 3600,
            nightWakeCount: 1, deepSleepRatio: 0.22,
            walkingSpeed: 1.20, stepCount: 6000, walkingAsymmetry: 0.05,
            heartRateVariability: 36, restingHeartRate: 65
        )
    }
}
