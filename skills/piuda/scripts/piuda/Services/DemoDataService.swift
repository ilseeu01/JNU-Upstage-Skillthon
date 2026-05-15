import Foundation

// 앱 번들에 포함된 demo_subjects.json 을 읽어 HealthSnapshot 으로 변환한다.
//
// demo_subjects.json 은 AI-Hub "치매 고위험군 라이프로그" 데이터셋
// (Oura 활동/수면 로그 + MMSE 인지검사)을 data_pipeline/build_demo_data.py 가
// 변환한 것이다. CN/MCI/Dem 진단 라벨이 붙은 실제 피험자 3명의 주간 데이터를 담는다.
@Observable
final class DemoDataService {

    private(set) var subjects: [DemoSubject] = []
    private(set) var loadError: String?

    var isLoaded: Bool { !subjects.isEmpty }

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "demo_subjects", withExtension: "json") else {
            loadError = "demo_subjects.json 을 앱 번들에서 찾을 수 없습니다. " +
                        "Resources/demo_subjects.json 이 piuda 타겟에 포함됐는지 확인하세요."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            subjects = try JSONDecoder().decode(DemoFile.self, from: data).subjects
        } catch {
            loadError = "demo_subjects.json 디코딩 실패: \(error.localizedDescription)"
        }
    }

    // weekIndex 0 = 가장 최근 주. 해당 주의 일별 스냅샷을 반환한다.
    func snapshots(for subject: DemoSubject, weekIndex: Int) -> [HealthSnapshot] {
        guard let week = subject.weeks.first(where: { $0.weekIndex == weekIndex }) else { return [] }
        return week.snapshots.map { $0.asHealthSnapshot }
    }

    func subject(id: String) -> DemoSubject? {
        subjects.first { $0.subjectId == id }
    }
}

// MARK: - JSON 디코딩 모델 (demo_subjects.json 스키마)

struct DemoFile: Decodable {
    let schemaVersion: Int
    let generatedAt: String
    let source: String
    let note: String?
    let subjects: [DemoSubject]
}

struct DemoSubject: Decodable, Identifiable {
    let subjectId: String
    let displayName: String      // "어르신 A" 등
    let diagnosis: String        // "CN" / "MCI" / "Dem" (실제 진단 라벨)
    let diagnosisLabel: String   // "정상" / "경도인지장애" / "치매"
    let mmseTotal: Int           // MMSE 원점수 0–30
    let cognitiveScore: Double   // MMSE 를 0–100 으로 환산한 값
    let weeks: [DemoWeek]

    var id: String { subjectId }

    // 가장 최근 주 / 그 전 주 — runWeeklyAnalysis 에 그대로 넣을 수 있다.
    var thisWeekSnapshots: [HealthSnapshot] {
        (weeks.first { $0.weekIndex == 0 }?.snapshots ?? []).map(\.asHealthSnapshot)
    }
    var previousWeekSnapshots: [HealthSnapshot]? {
        guard let week = weeks.first(where: { $0.weekIndex == 1 }) else { return nil }
        return week.snapshots.map(\.asHealthSnapshot)
    }
}

struct DemoWeek: Decodable {
    let weekIndex: Int
    let weekStart: String
    let weekEnd: String
    let snapshots: [DemoSnapshot]
}

struct DemoSnapshot: Decodable {
    let date: String             // ISO8601, 예: "2021-02-03T12:00:00Z"
    let sleepEfficiency: Double
    let sleepDuration: Double
    let nightWakeCount: Int
    let deepSleepRatio: Double
    let walkingSpeed: Double      // 0 = 미측정 (Oura 데이터에 보행 속도 없음)
    let stepCount: Int
    let walkingAsymmetry: Double  // 0 = 미측정
    let heartRateVariability: Double
    let restingHeartRate: Double
    let cognitiveScore: Double?

    private static let isoFormatter = ISO8601DateFormatter()

    var asHealthSnapshot: HealthSnapshot {
        HealthSnapshot(
            date: DemoSnapshot.isoFormatter.date(from: date) ?? Date(),
            sleepEfficiency: sleepEfficiency,
            sleepDuration: sleepDuration,
            nightWakeCount: nightWakeCount,
            deepSleepRatio: deepSleepRatio,
            walkingSpeed: walkingSpeed,
            stepCount: stepCount,
            walkingAsymmetry: walkingAsymmetry,
            heartRateVariability: heartRateVariability,
            restingHeartRate: restingHeartRate,
            cognitiveScore: cognitiveScore
        )
    }
}
