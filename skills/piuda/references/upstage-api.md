# Upstage Solar LLM API — 피우다 연동 가이드

## 엔드포인트

```
POST https://api.upstage.ai/v1/chat/completions
Authorization: Bearer {UPSTAGE_API_KEY}
Content-Type: application/json
```

> ⚠️ 엔드포인트 경로에 `/solar/` 가 들어가지 않습니다. `/v1/chat/completions` 입니다.

## 모델

| 모델 | 용도 |
|------|------|
| `solar-pro3` | 주간 리포트 생성, 인지 테스트 평가 (현행 모델 별칭) |

## 주간 리포트 요청 예시

```json
{
  "model": "solar-pro3",
  "messages": [
    {
      "role": "system",
      "content": "당신은 노인 건강 전문 AI 의사입니다. 제공된 건강 데이터를 분석하여 보호자가 이해하기 쉬운 한국어로 주간 건강 리포트를 작성하세요."
    },
    {
      "role": "user",
      "content": "이번 주 건강 데이터:\n수면 효율: 78%, 보행 속도: 0.9 m/s, HRV: 25ms\n\nJSON 형식으로 응답하세요: {\"narrative\": \"...\", \"keyFindings\": [...], \"recommendations\": [...]}"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 1000
}
```

## 응답 파싱

```swift
// UpstageService.swift에서 JSON 파싱
struct ReportResponse: Codable {
    let narrative: String
    let keyFindings: [String]
    let recommendations: [String]
}
```

## API 키 설정

```swift
// 앱 설정에서 저장
UserDefaults.standard.set(apiKey, forKey: "upstage_api_key")

// 싱글톤 접근
UpstageService.shared.apiKey = "up_..."
```
