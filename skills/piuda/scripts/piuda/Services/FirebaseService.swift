// MARK: - Firebase 설정 안내
//
// 아래 코드는 Firebase SPM 추가 후 자동 활성화됩니다.
//
// 설정 순서:
// 1. Xcode → File → Add Package Dependencies
//    URL: https://github.com/firebase/firebase-ios-sdk
//    Products: FirebaseFirestore, FirebaseMessaging 체크
// 2. console.firebase.google.com → 프로젝트 생성 → iOS 앱 추가
//    Bundle ID: 빌드 설정의 Bundle Identifier와 동일하게
// 3. GoogleService-Info.plist 다운로드 후 piuda/piuda/ 에 추가
// 4. Firebase 추가 즉시 이 파일의 모든 코드가 활성화됩니다.

import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseMessaging

@Observable
final class FirebaseService {
    static let shared = FirebaseService()
    private init() {}

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    var fcmToken: String? {
        Messaging.messaging().fcmToken
    }

    // MARK: - User Profile

    func saveProfile(_ profile: UserProfile) async throws {
        try await db.collection("users")
            .document(profile.phoneNumber)
            .setData(profile.asFirestoreData(), merge: true)
    }

    func fetchProfile(phoneNumber: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(phoneNumber).getDocument()
        guard let data = doc.data() else { return nil }
        return try UserProfile.fromFirestore(data)
    }

    func saveFCMToken(_ token: String, phoneNumber: String) async {
        try? await db.collection("users").document(phoneNumber)
            .setData(["fcmToken": token], merge: true)
    }

    // MARK: - Health Snapshots

    func saveSnapshot(_ snapshot: HealthSnapshot, elderPhone: String) async throws {
        let key = DateFormatter.yyyyMMdd.string(from: snapshot.date)
        try await db.collection("healthData")
            .document(elderPhone)
            .collection("snapshots")
            .document(key)
            .setData(snapshot.asFirestoreData())
    }

    func fetchSnapshots(elderPhone: String, weekStart: Date) async throws -> [HealthSnapshot] {
        let startKey = DateFormatter.yyyyMMdd.string(from: weekStart)
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let endKey = DateFormatter.yyyyMMdd.string(from: endDate)

        let snap = try await db.collection("healthData")
            .document(elderPhone)
            .collection("snapshots")
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: startKey)
            .whereField(FieldPath.documentID(), isLessThan: endKey)
            .getDocuments()

        return try snap.documents.compactMap { try HealthSnapshot.fromFirestore($0.data()) }
    }

    // MARK: - Weekly Reports

    func saveReport(_ report: WeeklyReport, elderPhone: String) async throws {
        try await db.collection("reports")
            .document(elderPhone)
            .collection("weekly")
            .document(report.id.uuidString)
            .setData(report.asFirestoreData())
    }

    func fetchReports(elderPhone: String, limit: Int = 8) async throws -> [WeeklyReport] {
        let snap = try await db.collection("reports")
            .document(elderPhone)
            .collection("weekly")
            .order(by: "generatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return try snap.documents.compactMap { try WeeklyReport.fromFirestore($0.data()) }
    }

    // MARK: - Alerts

    func saveAlert(_ alert: DementiaAlert, caregiverPhone: String) async throws {
        try await db.collection("alerts")
            .document(caregiverPhone)
            .collection("items")
            .document(alert.id.uuidString)
            .setData(alert.asFirestoreData())
    }

    func acknowledgeAlert(id: UUID, caregiverPhone: String) async throws {
        try await db.collection("alerts")
            .document(caregiverPhone)
            .collection("items")
            .document(id.uuidString)
            .updateData(["isAcknowledged": true])
    }

    func saveAppointment(_ appt: HospitalAppointment, alertId: UUID, caregiverPhone: String) async throws {
        let apptData = appt.asFirestoreData()
        try await db.collection("alerts")
            .document(caregiverPhone)
            .collection("items")
            .document(alertId.uuidString)
            .updateData([
                "scheduledAppointment": apptData,
                "isAcknowledged": true
            ])
    }

    // MARK: - Realtime Listeners

    func listenForAlerts(caregiverPhone: String,
                          onNew: @escaping (DementiaAlert) -> Void) {
        let reg = db.collection("alerts")
            .document(caregiverPhone)
            .collection("items")
            .whereField("isAcknowledged", isEqualTo: false)
            .addSnapshotListener { snapshot, _ in
                guard let changes = snapshot?.documentChanges else { return }
                for change in changes where change.type == .added {
                    if let alert = try? DementiaAlert.fromFirestore(change.document.data()) {
                        onNew(alert)
                    }
                }
            }
        listeners.append(reg)
    }

    func listenForNewReport(elderPhone: String,
                             onNew: @escaping (WeeklyReport) -> Void) {
        let reg = db.collection("reports")
            .document(elderPhone)
            .collection("weekly")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, _ in
                guard let changes = snapshot?.documentChanges else { return }
                for change in changes where change.type == .added {
                    if let report = try? WeeklyReport.fromFirestore(change.document.data()) {
                        onNew(report)
                    }
                }
            }
        listeners.append(reg)
    }

    func removeListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}

// MARK: - Firestore Codable Helpers (JSON Bridge)

private extension JSONEncoder {
    static let firestore: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let firestore: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension Encodable {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

private extension Decodable {
    static func fromFirestore(_ dict: [String: Any]) throws -> Self {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder.firestore.decode(Self.self, from: data)
    }
}

// Public wrappers so AppState can call these without importing Firebase
extension UserProfile {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func fromFirestore(_ dict: [String: Any]) throws -> UserProfile {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder.firestore.decode(UserProfile.self, from: data)
    }
}

extension HealthSnapshot {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func fromFirestore(_ dict: [String: Any]) throws -> HealthSnapshot {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder.firestore.decode(HealthSnapshot.self, from: data)
    }
}

extension WeeklyReport {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func fromFirestore(_ dict: [String: Any]) throws -> WeeklyReport {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder.firestore.decode(WeeklyReport.self, from: data)
    }
}

extension DementiaAlert {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func fromFirestore(_ dict: [String: Any]) throws -> DementiaAlert {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder.firestore.decode(DementiaAlert.self, from: data)
    }
}

extension HospitalAppointment {
    func asFirestoreData() throws -> [String: Any] {
        let data = try JSONEncoder.firestore.encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

#else
// Firebase 미설치 시 빈 플레이스홀더 — SPM 추가 후 자동 활성화
final class FirebaseService {
    static let shared = FirebaseService()
    private init() {}
}
#endif
