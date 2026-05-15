---
name: brain-health-weekly-report
description: Generate a caregiver-friendly Korean weekly brain-health report from an older adult's wearable/health data (sleep efficiency, night awakenings, gait speed, daily steps, HRV, weekly cognitive-test score) using the Upstage Solar LLM. The report includes a plain-language trend analysis, a risk level (안정 / 관찰 권장 / 주의 필요), and a concrete recommended action for a family caregiver. Use this skill whenever the user has weekly health or activity data for an elderly person and wants a summary, trend interpretation, or risk assessment for a remote family member — e.g. "엄마 주간 건강 리포트 만들어줘", "이 수면·걸음 데이터 분석해줘", "할아버지 데이터에 걱정할 만한 변화 있어?". Trigger it even when the user just hands over a health-data file and asks what it means, without saying the word "report".
---

# 주간 뇌 건강 리포트 생성 (Brain Health Weekly Report)

멀리 사는 가족 보호자를 위해, 노인의 한 주치 건강 데이터를 **한국어 자연어 리포트**로
바꿔주는 스킬입니다. 보호자는 전문 수치를 몰라도 부모님의 변화를 한눈에 이해하고,
이번 주에 무엇을 하면 좋을지 알 수 있습니다.

이 스킬은 진단 도구가 아닙니다. wellness(생활 건강) 정보를 제공할 뿐이며,
치매를 포함한 어떤 질병도 진단·단정하지 않습니다.

## 동작 개요

1. 노인의 주간 건강 데이터(JSON)를 입력받습니다.
2. 이번 주 지표를 지난주와 비교해 변화량을 계산합니다.
3. Upstage Solar LLM(`solar-pro3`)이 보호자용 한국어 리포트를 생성합니다.
4. 결과: **위험 수준 + 한 줄 요약 + 리포트 본문 + 권장 행동**.

## 사전 준비 — Upstage API 키

모든 호출에 `UPSTAGE_API_KEY`가 필요합니다.

1. https://console.upstage.ai → **API Keys** 에서 키를 발급합니다.
2. Billing → Credit → Redeem code 에 `UPWAVE-KOH` 를 입력하면 $70 크레딧이 적립됩니다.
3. `assets/.env.example` 을 복사해 `assets/.env` 를 만들고 키를 채웁니다:
   ```
   UPSTAGE_API_KEY=up_xxxxxxxxxxxxxxxx
   ```
   `.env` 는 절대 커밋하지 마세요(이미 `.gitignore`에 포함).

키가 없으면 스크립트가 안내 메시지와 함께 즉시 멈춥니다.

## 실행 방법

```bash
pip install -r scripts/requirements.txt
python scripts/generate_report.py assets/sample_week.json
```

데이터 파일 인자를 생략하면 `assets/sample_week.json` 을 사용합니다.

## 입력 데이터 형식

JSON 객체 하나. `current_week` 는 필수, `previous_week` 는 선택(있으면 추세 비교).

```json
{
  "elder_name": "김영자",
  "week_of": "2026-05-08 ~ 2026-05-14",
  "current_week": {
    "sleep_efficiency_pct": 65,
    "night_awakenings_avg": 3.3,
    "gait_speed_mps": 0.92,
    "daily_steps_avg": 3100,
    "resting_hr_bpm": 73,
    "hrv_rmssd_ms": 18,
    "cognitive_test_score": 7
  },
  "previous_week": { "...": "동일한 지표 키" }
}
```

지원 지표 (모두 선택 — 있는 것만 분석):

| 키 | 의미 | 단위 | 좋은 방향 |
|---|---|---|---|
| `sleep_efficiency_pct` | 수면 효율 | % | 높을수록 |
| `night_awakenings_avg` | 새벽 각성 횟수 | 회 | 낮을수록 |
| `gait_speed_mps` | 보행 속도 | m/s | 높을수록 |
| `daily_steps_avg` | 하루 평균 걸음 | 보 | 높을수록 |
| `resting_hr_bpm` | 안정시 심박 | bpm | 중립 |
| `hrv_rmssd_ms` | 심박변이도(RMSSD) | ms | 높을수록 |
| `cognitive_test_score` | 주간 인지테스트 점수 | 점 | 높을수록 |

> 실제 제품에서는 Apple Watch HealthKit / Oura 등에서 이 지표들을 수집하지만,
> 이 스킬은 형식만 맞으면 어떤 출처의 데이터든 처리합니다.

## 출력 형식

스크립트는 다음 4가지를 출력합니다:

- **위험 수준**: `안정` / `관찰 권장` / `주의 필요` 중 하나
- **한 줄 요약**: 보호자가 알림으로 받을 법한 한 문장
- **리포트**: 전문 수치를 풀어 쓴 한국어 본문
- **이번 주 권장 행동**: 보호자가 실제로 할 수 있는 부담 없는 행동 1~2가지

마지막 줄에 토큰 사용량을 표시해 호출당 비용을 가늠할 수 있게 합니다.

## 어조 원칙 (중요)

데이터가 나빠 보여도 보호자가 부모님에게 화를 내거나 과도하게 불안해하지 않도록,
리포트는 **침착하고 비난 없는 어조**를 유지합니다. 작은 변화는 "안정"으로 처리하고,
여러 지표가 함께 뚜렷이 나빠졌을 때만 "주의 필요"로 올립니다. 한 번의 잘못된 경보가
가족 관계를 해치지 않도록 하는 것이 이 스킬의 핵심 설계 의도입니다.

## 테스트

`assets/sample_week.json` 은 수면 효율 78→65, 새벽 각성 1.1→3.3회 등
여러 지표가 동시에 악화된 데이터입니다. 정상 동작 시 위험 수준이
`관찰 권장` 또는 `주의 필요` 로 나와야 합니다.
