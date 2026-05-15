import Foundation
import SwiftUI

// MARK: - User

enum UserRole: String, Codable, Hashable {
    case elder
    case caregiver
}

struct UserProfile: Codable {
    var id: UUID = UUID()
    var role: UserRole
    var name: String
    var phoneNumber: String
    var pairedPhoneNumber: String?
    var createdAt: Date = Date()
}

// MARK: - Health Data

struct HealthSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    // Sleep
    var sleepEfficiency: Double       // 0.0-1.0
    var sleepDuration: TimeInterval   // seconds
    var nightWakeCount: Int
    var deepSleepRatio: Double        // 0.0-1.0
    // Gait
    var walkingSpeed: Double          // m/s
    var stepCount: Int
    var walkingAsymmetry: Double      // 0.0-1.0 (낮을수록 좋음)
    // Heart
    var heartRateVariability: Double  // RMSSD ms
    var restingHeartRate: Double      // bpm
    // Cognitive (weekly Watch test)
    var cognitiveScore: Double?       // 0-100

    static func mock(for date: Date, degraded: Bool = false) -> HealthSnapshot {
        let f: Double = degraded ? 0.72 : 1.0
        return HealthSnapshot(
            date: date,
            sleepEfficiency: 0.80 * f,
            sleepDuration: 6.8 * 3600 * f,
            nightWakeCount: degraded ? 4 : 1,
            deepSleepRatio: 0.22 * f,
            walkingSpeed: 1.18 * f,
            stepCount: degraded ? 3100 : 6900,
            walkingAsymmetry: degraded ? 0.14 : 0.05,
            heartRateVariability: 34.0 * f,
            restingHeartRate: 68.0,
            cognitiveScore: degraded ? 63.0 : 85.0
        )
    }
}

// MARK: - Risk Level

enum RiskLevel: String, Codable, CaseIterable, Comparable {
    case low, moderate, high, critical

    private var order: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        case .critical: return 3
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.order < rhs.order
    }

    var displayName: String {
        switch self {
        case .low: return "정상"
        case .moderate: return "주의"
        case .high: return "위험"
        case .critical: return "긴급"
        }
    }

    var color: Color {
        switch self {
        case .low: return Color(red: 0.18, green: 0.70, blue: 0.42)
        case .moderate: return Color(red: 0.95, green: 0.68, blue: 0.10)
        case .high: return Color(red: 0.94, green: 0.42, blue: 0.10)
        case .critical: return Color(red: 0.84, green: 0.18, blue: 0.18)
        }
    }

    var backgroundColor: Color { color.opacity(0.12) }

    var icon: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var description: String {
        switch self {
        case .low:
            return "이번 주 건강 지표가 정상 범위입니다."
        case .moderate:
            return "일부 지표에서 변화가 감지됩니다. 지속적인 관찰이 필요합니다."
        case .high:
            return "여러 지표에서 유의미한 변화가 나타났습니다. 전문가 상담을 권장합니다."
        case .critical:
            return "즉각적인 의료 전문가 상담이 필요한 수준입니다."
        }
    }
}

// MARK: - Weekly Report

struct WeeklyReport: Codable, Identifiable {
    var id: UUID = UUID()
    var weekStart: Date
    var weekEnd: Date
    var riskLevel: RiskLevel
    var riskScore: Int              // 0-20
    var narrative: String           // Upstage Solar LLM 생성
    var keyFindings: [String]
    var recommendations: [String]
    var snapshots: [HealthSnapshot]
    var generatedAt: Date = Date()
    var sleepTrend: Double          // 전주 대비 변화율 (%)
    var walkingTrend: Double
    var hrvTrend: Double

    var averageSleepEfficiency: Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.sleepEfficiency).reduce(0, +) / Double(snapshots.count)
    }

    var averageWalkingSpeed: Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.walkingSpeed).reduce(0, +) / Double(snapshots.count)
    }

    var averageHRV: Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.heartRateVariability).reduce(0, +) / Double(snapshots.count)
    }

    var latestCognitiveScore: Double? {
        snapshots.compactMap(\.cognitiveScore).last
    }
}

// MARK: - Alert

struct DementiaAlert: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var riskLevel: RiskLevel
    var title: String
    var message: String
    var triggerFactors: [String]
    var recommendedHospitals: [Hospital]
    var isAcknowledged: Bool = false
    var scheduledAppointment: HospitalAppointment?
    var relatedReportId: UUID?
}

// MARK: - Hospital

struct Hospital: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var phone: String
    var specialty: String
    var naverReservationURL: String?
    var distanceKm: Double?

    static let recommendations: [Hospital] = [
        Hospital(
            name: "서울아산병원 신경과",
            address: "서울 송파구 올림픽로 43길 88",
            phone: "02-3010-3440",
            specialty: "신경과",
            naverReservationURL: "https://booking.naver.com/booking/13/bizes/42817",
            distanceKm: 2.3
        ),
        Hospital(
            name: "삼성서울병원 기억장애클리닉",
            address: "서울 강남구 일원로 81",
            phone: "02-3410-3592",
            specialty: "신경과",
            naverReservationURL: nil,
            distanceKm: 3.1
        ),
        Hospital(
            name: "분당서울대병원 치매예방센터",
            address: "경기 성남시 분당구 구미로 173번길 82",
            phone: "031-787-7462",
            specialty: "신경과",
            naverReservationURL: "https://booking.naver.com/booking/13/bizes/51234",
            distanceKm: 5.8
        ),
        Hospital(
            name: "치매안심센터 (서초구)",
            address: "서울 서초구 남부순환로 2584",
            phone: "02-2155-8500",
            specialty: "치매 상담·검사",
            naverReservationURL: nil,
            distanceKm: 1.5
        )
    ]
}

struct HospitalAppointment: Codable {
    var hospital: Hospital
    var scheduledDate: Date
    var calendarEventId: String?
    var notes: String
}

// MARK: - Cognitive Test

struct CognitiveTestResult: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var score: Double           // 0-100
    var responseTimeAvg: Double // seconds
    var correctAnswers: Int
    var totalQuestions: Int
}

struct CognitiveQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
    let correctIndex: Int
    let type: CognitiveTestType
}

enum CognitiveTestType: String {
    case wordRecall = "단어 회상"
    case orientation = "지남력"
    case calculation = "계산"
    case patternTap = "패턴 기억"
}
