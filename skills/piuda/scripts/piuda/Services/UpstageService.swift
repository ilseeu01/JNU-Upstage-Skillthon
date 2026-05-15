import Foundation

// Upstage Solar LLM API 클라이언트
final class UpstageService {
    static let shared = UpstageService()
    private init() {}

    private let baseURL = "https://api.upstage.ai/v1"
    private let model   = "solar-pro"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "upstage_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "upstage_api_key") }
    }

    // MARK: - 주간 리포트 생성

    func generateWeeklyReport(
        snapshots: [HealthSnapshot],
        previousAvg: HealthSnapshot?,
        elderName: String
    ) async throws -> (narrative: String, keyFindings: [String], recommendations: [String]) {
        let prompt = reportPrompt(snapshots: snapshots, previous: previousAvg, name: elderName)
        let raw = try await chat(
            system: systemPromptReport,
            user: prompt
        )
        return parseReport(raw)
    }

    // MARK: - 알림 메시지 생성

    func generateAlertMessage(
        riskLevel: RiskLevel,
        factors: [String],
        elderName: String
    ) async throws -> (title: String, message: String) {
        let prompt = """
        노인 치매 조기감지 앱에서 위험 신호가 감지되었습니다.

        대상: \(elderName) 어르신
        위험 수준: \(riskLevel.displayName)
        감지된 변화:
        \(factors.prefix(4).map { "• \($0)" }.joined(separator: "\n"))

        보호자에게 보낼 알림 제목(20자 이내)과 내용(80자 이내)을 JSON으로 작성하세요.
        의학적 진단이 아닌 '관찰된 변화'임을 명확히 하고 불안을 조성하지 마세요.
        반드시 다음 JSON만 반환: {"title": "...", "message": "..."}
        """
        let raw = try await chat(
            system: "보호자에게 차분하고 친절하게 전달하는 건강 알림을 작성합니다. JSON만 반환하세요.",
            user: prompt
        )
        return parseAlert(raw, elderName: elderName)
    }

    // MARK: - 인지 평가

    func evaluateCognitiveAnswer(question: String, answer: String) async throws -> Double {
        let prompt = """
        다음은 노인 인지 기능 평가의 질문과 응답입니다.
        질문: \(question)
        응답: \(answer)

        응답의 인지 기능 점수(0-100)를 JSON으로만 반환하세요.
        {"score": 숫자}
        """
        let raw = try await chat(
            system: "노인 인지 기능 평가 전문가입니다. JSON만 반환하세요.",
            user: prompt
        )
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let score = json["score"] as? Double {
            return min(100, max(0, score))
        }
        return 70
    }

    // MARK: - Private

    private var systemPromptReport: String {
        """
        당신은 노인 인지 건강 모니터링 AI입니다. Apple Watch 생체 데이터를 분석해 보호자에게 주간 리포트를 작성합니다.
        규칙: 의학적 진단이 아닌 '관찰 보고'입니다. 일상 언어를 사용하세요. 수치 변화를 구체적으로 언급하되 과도한 불안은 피하세요.
        긍정적 변화도 함께 언급하세요. 반드시 한국어로, 지정된 JSON 형식으로만 응답하세요.
        """
    }

    private func reportPrompt(snapshots: [HealthSnapshot], previous: HealthSnapshot?, name: String) -> String {
        let avg = average(snapshots)
        var p = "\(name) 어르신의 1주간 Apple Watch 데이터 분석 리포트를 작성해주세요.\n\n"
        p += "【이번 주 평균】\n"
        p += "• 수면 효율: \(Int(avg.sleepEfficiency * 100))%\n"
        p += "• 야간 각성: 평균 \(avg.nightWakeCount)회\n"
        p += "• 보행 속도: \(String(format: "%.2f", avg.walkingSpeed)) m/s\n"
        p += "• 하루 걸음 수: \(avg.stepCount)보\n"
        p += "• HRV: \(Int(avg.heartRateVariability)) ms\n"
        if let cog = avg.cognitiveScore { p += "• 인지 테스트: \(Int(cog))/100\n" }

        if let prev = previous {
            p += "\n【전주 대비】\n"
            let d = { (a: Double, b: Double) -> String in
                let pct = (a - b) / b * 100
                return "\(pct >= 0 ? "+" : "")\(Int(pct))%"
            }
            p += "• 수면 효율: \(d(avg.sleepEfficiency, prev.sleepEfficiency))\n"
            p += "• 보행 속도: \(d(avg.walkingSpeed, prev.walkingSpeed))\n"
            p += "• HRV: \(d(avg.heartRateVariability, prev.heartRateVariability))\n"
        }

        p += """

        다음 JSON 형식으로만 응답하세요:
        {
          "narrative": "전체 리포트 (200자 이내, 자연스러운 문장)",
          "keyFindings": ["주요 발견 1", "주요 발견 2", "주요 발견 3"],
          "recommendations": ["권고사항 1", "권고사항 2"]
        }
        """
        return p
    }

    private func parseReport(_ raw: String) -> (String, [String], [String]) {
        let jsonStr: String
        if let s = raw.range(of: "{"), let e = raw.range(of: "}", options: .backwards) {
            jsonStr = String(raw[s.lowerBound...e.upperBound])
        } else { jsonStr = raw }

        if let data = jsonStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let narrative = json["narrative"] as? String ?? raw
            let findings  = json["keyFindings"] as? [String] ?? []
            let recs      = json["recommendations"] as? [String] ?? []
            return (narrative, findings, recs)
        }
        return (raw, [], [])
    }

    private func parseAlert(_ raw: String, elderName: String) -> (String, String) {
        let jsonStr: String
        if let s = raw.range(of: "{"), let e = raw.range(of: "}", options: .backwards) {
            jsonStr = String(raw[s.lowerBound...e.upperBound])
        } else { jsonStr = raw }

        if let data = jsonStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = json["title"] as? String,
           let msg   = json["message"] as? String {
            return (title, msg)
        }
        return ("\(elderName) 어르신 건강 변화 감지", "이번 주 일부 건강 지표에 변화가 있었습니다. 리포트를 확인해주세요.")
    }

    private func average(_ snapshots: [HealthSnapshot]) -> HealthSnapshot {
        guard !snapshots.isEmpty else { return .mock(for: Date()) }
        let n = Double(snapshots.count)
        return HealthSnapshot(
            date: snapshots[0].date,
            sleepEfficiency: snapshots.map(\.sleepEfficiency).reduce(0, +) / n,
            sleepDuration:   snapshots.map(\.sleepDuration).reduce(0, +) / n,
            nightWakeCount:  Int(snapshots.map { Double($0.nightWakeCount) }.reduce(0, +) / n),
            deepSleepRatio:  snapshots.map(\.deepSleepRatio).reduce(0, +) / n,
            walkingSpeed:    snapshots.map(\.walkingSpeed).reduce(0, +) / n,
            stepCount:       Int(snapshots.map { Double($0.stepCount) }.reduce(0, +) / n),
            walkingAsymmetry: snapshots.map(\.walkingAsymmetry).reduce(0, +) / n,
            heartRateVariability: snapshots.map(\.heartRateVariability).reduce(0, +) / n,
            restingHeartRate: snapshots.map(\.restingHeartRate).reduce(0, +) / n,
            cognitiveScore: {
                let scores = snapshots.compactMap(\.cognitiveScore)
                return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            }()
        )
    }

    // MARK: - HTTP

    private func chat(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw UpstageError.missingAPIKey }
        guard let url = URL(string: "\(baseURL)/solar/chat/completions") else {
            throw UpstageError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ],
            "temperature": 0.3,
            "max_tokens": 800
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpstageError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(SolarResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}

// MARK: - Response / Error

private struct SolarResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
    }
    struct Message: Decodable {
        let role: String
        let content: String
    }
}

enum UpstageError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Upstage API 키가 설정되지 않았습니다. 설정에서 입력해주세요."
        case .invalidURL:    return "API URL이 올바르지 않습니다."
        case .http(let c):   return "API 오류 (HTTP \(c))"
        }
    }
}
