import Foundation
import WatchConnectivity

// iOS 쪽 WCSession 핸들러 — Watch에서 보내온 건강 데이터 수신
@Observable
final class WatchConnectivityService: NSObject {
    var isWatchReachable = false
    var isPaired = false

    // 최근에 Watch에서 받은 데이터
    private(set) var lastReceivedSnapshot: WatchHealthPayload?

    // Watch 데이터 수신 시 호출되는 콜백
    var onSnapshotReceived: ((WatchHealthPayload) -> Void)?
    var onCognitiveResultReceived: ((Double) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    var watchStatusText: String {
        guard WCSession.isSupported() else { return "Watch 미지원 기기" }
        let s = WCSession.default
        switch s.activationState {
        case .activated:
            return s.isPaired ? (s.isWatchAppInstalled ? "Watch 앱 연결됨" : "Watch 앱 미설치") : "Watch 미페어링"
        case .inactive:  return "비활성"
        case .notActivated: return "미활성화"
        @unknown default: return "알 수 없음"
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.isWatchReachable = state == .activated && session.isReachable
            self.isPaired = session.isPaired
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    // Watch가 sendMessage() 로 보낸 실시간 데이터
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["status": "received"])
    }

    // Watch가 updateApplicationContext() 로 보낸 배경 데이터
    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    // iOS WCSessionDelegate 필수 메서드
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    // MARK: - Private

    private func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "healthUpdate":
                if let payload = WatchHealthPayload(from: message) {
                    self.lastReceivedSnapshot = payload
                    self.onSnapshotReceived?(payload)
                }
            case "cognitiveResult":
                if let score = message["score"] as? Double {
                    self.onCognitiveResultReceived?(score)
                }
            default:
                break
            }
        }
    }
}

// MARK: - Payload Model

struct WatchHealthPayload {
    let date: Date
    let stepCount: Int
    let heartRate: Double
    let cognitiveScore: Double?

    init?(from dict: [String: Any]) {
        guard let stepCount = dict["stepCount"] as? Int,
              let heartRate = dict["heartRate"] as? Double else { return nil }
        let dateInterval = dict["date"] as? Double ?? Date().timeIntervalSince1970
        self.date = Date(timeIntervalSince1970: dateInterval)
        self.stepCount = stepCount
        self.heartRate = heartRate
        self.cognitiveScore = dict["cognitiveScore"] as? Double
    }
}
