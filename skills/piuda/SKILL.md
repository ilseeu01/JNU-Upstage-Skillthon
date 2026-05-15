---
name: piuda
description: 초기 치매 조기 감지 iOS + Apple Watch 앱 스킬. Apple Watch로 수면 효율, 보행 속도, 심박수 변이도(HRV), 인지 기능 테스트를 수집하고 Upstage Solar LLM으로 주간 리포트를 생성하여 보호자에게 위험 알림과 병원 예약을 자동화합니다. 노인의 치매 위험 평가, 보호자 리포트 생성, 병원 예약 자동화가 필요할 때 이 스킬을 사용하세요.
---

# 피우다 (Piuda) — 치매 조기 감지 AI Agent 스킬

> "꽃이 피어나듯, 건강하게" — Apple Watch + iPhone + Upstage Solar LLM 기반 치매 조기 감지 플랫폼

## 개요

피우다는 두 가지 역할을 지원합니다:

- **노인 (Elder)**: Apple Watch에서 수동으로 건강 데이터를 수집하고 매주 인지 기능 테스트 수행
- **보호자 (Caregiver)**: AI가 생성한 주간 리포트 수신, 위험 알림, 자동 병원 예약

## AI Agent 흐름

```
Apple Watch 건강 데이터
    ↓ (WatchConnectivity)
iPhone HealthKit + 인지 테스트 점수
    ↓
위험 점수 계산 (0–20점)
    ↓
Upstage Solar LLM → 한국어 주간 리포트 생성
    ↓
위험 수준 판정 (low / moderate / high / critical)
    ↓ (moderate 이상)
보호자 푸시 알림 + 병원 예약 추천
```

## 위험 점수 알고리즘

| 지표 | 정상 기준 | 배점 |
|------|-----------|------|
| 수면 효율 | ≥ 85% | 0–4점 |
| 야간 각성 횟수 | ≤ 2회 | 0–3점 |
| 보행 속도 | ≥ 1.0 m/s | 0–4점 |
| HRV (SDNN) | ≥ 30 ms | 0–3점 |
| 일일 걸음 수 | ≥ 5,000보 | 0–3점 |
| 인지 테스트 점수 | ≥ 80점 | 0–3점 |

- **0–5점**: 낮음 (low) — 정기 모니터링
- **6–10점**: 보통 (moderate) — 보호자 알림 발송
- **11–15점**: 높음 (high) — 병원 방문 권고
- **16–20점**: 위험 (critical) — 즉시 병원 예약

## Upstage Solar LLM 연동

### 주간 리포트 생성 (`generateWeeklyReport`)

Solar LLM을 사용해 한국어 주간 건강 리포트를 생성합니다.

```
POST https://api.upstage.ai/v1/chat/completions
Model: solar-pro3
```

**프롬프트 구조:**
```
당신은 노인 건강 전문 AI 의사입니다.
[이번 주 평균 데이터] + [지난 주 대비 변화]를 분석하여
JSON 형식으로 응답하세요: {"narrative": "...", "keyFindings": [...], "recommendations": [...]}
```

### 인지 테스트 평가 (`evaluateCognitiveAnswer`)

음성/텍스트 답변을 Solar LLM이 채점합니다 (요일 인지, 계산, 단어 분류, 식사 시간).

### 보호자 알림 메시지 생성 (`generateAlertMessage`)

위험 수준과 건강 지표를 기반으로 보호자에게 보낼 한국어 알림 메시지를 생성합니다.

## 앱 구조

```
scripts/
├── piuda/                          # iOS 앱 소스
│   ├── AppState.swift              # 앱 전역 상태 관리 (@Observable)
│   ├── Models/AppModels.swift      # 데이터 모델 (UserProfile, HealthSnapshot, RiskLevel 등)
│   ├── Services/
│   │   ├── HealthKitService.swift      # HealthKit 데이터 수집
│   │   ├── UpstageService.swift        # Solar LLM API 연동
│   │   ├── DementiaAgentService.swift  # 위험 점수 계산 + AI Agent
│   │   ├── FirebaseService.swift       # Firestore + FCM (조건부 컴파일)
│   │   ├── WatchConnectivityService.swift  # Watch↔iPhone 통신
│   │   ├── CalendarService.swift       # 병원 예약 (EventKit)
│   │   └── NotificationService.swift  # 로컬 푸시 알림
│   └── Views/
│       ├── Onboarding/             # 사용자 등록 (역할 선택, 전화번호 페어링)
│       ├── Elder/                  # 노인 홈화면
│       └── Caregiver/             # 보호자 탭뷰 (홈, 리포트, 알림, 설정)
├── piudaWatch Watch App/          # watchOS 앱 소스
│   ├── WatchAppState.swift         # Watch 상태 관리
│   ├── WatchRootView.swift         # 메인 Watch 화면
│   └── WatchCognitiveTestView.swift # 인지 기능 테스트 (4문항)
└── data_pipeline/                 # 데모 데이터 파이프라인 (Python)
    ├── build_demo_data.py         # AI-Hub 치매 라이프로그 CSV → demo_subjects.json
    ├── verify_upstage.py          # 변환 데이터로 Upstage Solar API 연동 검증
    └── demo_subjects.json         # 진단군별(CN/MCI/Dem) 대표 피험자 4주 데이터
```

> `data_pipeline/` 는 실제 의료 데이터(AI-Hub "치매 고위험군 라이프로그")를
> 앱이 쓰는 `demo_subjects.json` 으로 변환하는 도구로, Firebase·실기기 없이도
> 정상군/경도인지장애/치매군 데모를 재현할 수 있게 합니다.

## 시작하는 방법

### 1. Upstage API 키 설정

앱 최초 실행 후 설정 탭에서 API 키를 입력하거나, `UpstageService.swift`에서 직접 설정:

```swift
UpstageService.shared.apiKey = "your_upstage_api_key"
```

### 2. Firebase 설정 (선택)

Firebase 없이도 Mock 데이터로 동작합니다. Firebase를 추가하려면:
- SPM에 `https://github.com/firebase/firebase-ios-sdk` 추가
- `FirebaseFirestore` + `FirebaseMessaging` 선택
- `GoogleService-Info.plist` 추가

Firebase가 설치되면 `#if canImport(FirebaseFirestore)` 블록이 자동으로 활성화됩니다.

### 3. Xcode 설정

```
1. Xcode → piuda 타겟 → Signing & Capabilities → Team 선택
2. HealthKit capability 추가 (iOS + watchOS 타겟 모두)
3. Build & Run
```

## 기술 스택

| 레이어 | 기술 |
|--------|------|
| AI 분석 | Upstage Solar LLM (solar-pro3) |
| 건강 데이터 | Apple HealthKit |
| Watch 통신 | WatchConnectivity |
| 백엔드 | Firebase Firestore + FCM |
| 병원 예약 | EventKit |
| 차트 | Swift Charts |
| 상태 관리 | @Observable (iOS 17+) |

## 참조 문서

- `./references/upstage-api.md` — Upstage Solar LLM API 사용 가이드
- `./references/healthkit-metrics.md` — 수집 건강 지표 상세 설명

## ⚖️ 면책 (중요)

피우다는 **의료기기가 아닌 wellness(생활 건강) 도구**입니다. 치매를 포함한 어떤
질병도 진단·단정하지 않으며, 일상 데이터의 변화를 가족에게 전달할 뿐입니다.
모든 리포트와 알림은 "의학적 진단이 아닙니다"를 명시하고, 한 번의 잘못된 경보가
가족 관계를 해치지 않도록 **침착하고 비난 없는 어조**를 설계 원칙으로 삼습니다.
