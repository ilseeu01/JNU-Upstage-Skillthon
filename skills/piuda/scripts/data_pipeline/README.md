# 데이터 파이프라인 — 치매 라이프로그 → 피우다 앱

AI-Hub **"치매 고위험군 라이프로그"** 데이터셋(Oura 링 활동/수면 로그 + MMSE
인지검사)을 피우다 iOS 앱이 쓸 수 있는 형태로 변환하고, Upstage Solar API
연동을 검증하는 도구 모음입니다.

## 구성

| 파일 | 역할 |
|------|------|
| `build_demo_data.py` | CSV 3종 → `demo_subjects.json` 변환 |
| `verify_upstage.py` | 변환된 데이터로 Upstage Solar API 호출 검증 |
| `demo_subjects.json` | 변환 결과 (앱 번들로 복사되어 사용됨) |
| `.env` | `UPSTAGE_API_KEY` (git에 커밋되지 않음) |
| `requirements.txt` | `pandas`, `openai` |

## 사용법

```bash
pip install -r requirements.txt

# 1) .env 준비 — .env.example 을 복사해 API 키 입력
#    (https://console.upstage.ai → API Keys, 리퍼럴 코드 UPWAVE-KOH = $70)

# 2) 데이터셋 → JSON 변환
python build_demo_data.py

# 3) 데이터 ↔ Upstage 연동 검증 (실제 API 호출)
python verify_upstage.py --subject MCI
```

`build_demo_data.py` 는 기본적으로 `../../../../../piuda/128.치매 고위험군
라이프로그/01.데이터` 를 찾습니다. 경로가 다르면 `--data-root` 로 지정하세요.

## 데이터 흐름

```
원천 CSV (활동/수면/MMSE, ~70MB)
     │  build_demo_data.py
     │   · email+날짜로 일별 결합
     │   · 진단군(CN/MCI/Dem)별 대표 피험자 선정
     │   · 최근 4주를 HealthSnapshot 형태로 변환
     ▼
demo_subjects.json (~42KB)
     │  Resources/ 로 복사 → 앱 번들에 포함
     ▼
iOS 앱: DemoDataService → AppState → DementiaAgentService
     │  주간 데이터 + 위험 점수
     ▼
UpstageService → Solar LLM (api.upstage.ai/v1/chat/completions)
     ▼
한국어 주간 리포트
```

## 지표 매핑 (데이터셋 → HealthSnapshot)

| 앱 지표 | 데이터셋 출처 |
|---------|--------------|
| `sleepEfficiency` | `sleep_efficiency` / 100 |
| `sleepDuration` | `sleep_total` (초) |
| `nightWakeCount` | `sleep_hypnogram_5min` 의 수면→각성 전환 횟수 |
| `deepSleepRatio` | `sleep_deep` / `sleep_total` |
| `stepCount` | `activity_steps` |
| `heartRateVariability` | `sleep_rmssd` (RMSSD ms) |
| `restingHeartRate` | `sleep_hr_average` |
| `cognitiveScore` | MMSE `TOTAL` / 30 × 100 |
| `walkingSpeed` / `walkingAsymmetry` | **데이터셋에 없음 → 0 (미측정)** |

> Oura 링 기반 데이터에는 보행 속도/비대칭이 없습니다. 앱의 위험 점수 계산과
> 리포트 프롬프트는 `walkingSpeed == 0` 을 '미측정'으로 보고 해당 지표를
> 건너뜁니다 (`DementiaAgentService`, `UpstageService` 참고).

## ⚠️ 보안

`.env` 의 API 키는 절대 커밋하지 마세요(`.gitignore` 포함). 채팅·문서에
키를 노출했다면 console.upstage.ai 에서 키를 폐기(rotate)하세요.
