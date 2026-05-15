#!/usr/bin/env python3
"""주간 뇌 건강 리포트 생성 — Upstage Solar LLM.

노인의 워치/헬스 데이터(JSON)를 입력받아, 멀리 사는 보호자가 바로 이해할 수
있는 한국어 리포트와 위험 수준을 생성한다.

사용법:
    python scripts/generate_report.py [데이터파일.json]
    (인자 생략 시 assets/sample_week.json 사용)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    sys.exit("openai 패키지가 필요합니다.  실행: pip install -r scripts/requirements.txt")

SKILL_ROOT = Path(__file__).resolve().parents[1]

MODEL = "solar-pro3"
BASE_URL = "https://api.upstage.ai/v1"

# 지표 키 → (한글 라벨, 단위, 좋은 방향)  방향: "up"=클수록 좋음, "down"=작을수록 좋음
METRICS = {
    "sleep_efficiency_pct": ("수면 효율", "%", "up"),
    "night_awakenings_avg": ("새벽 각성 횟수", "회", "down"),
    "gait_speed_mps":       ("보행 속도", "m/s", "up"),
    "daily_steps_avg":      ("하루 평균 걸음", "보", "up"),
    "resting_hr_bpm":       ("안정시 심박", "bpm", "flat"),
    "hrv_rmssd_ms":         ("심박변이도(RMSSD)", "ms", "up"),
    "cognitive_test_score": ("주간 인지테스트", "점", "up"),
}

# Solar 구조화 출력 스키마 (strict + additionalProperties:false 필수)
REPORT_SCHEMA = {
    "type": "json_schema",
    "json_schema": {
        "name": "brain_health_report",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "risk_level": {
                    "type": "string",
                    "enum": ["안정", "관찰 권장", "주의 필요"],
                },
                "headline": {"type": "string"},
                "report": {"type": "string"},
                "recommended_action": {"type": "string"},
            },
            "required": ["risk_level", "headline", "report", "recommended_action"],
            "additionalProperties": False,
        },
    },
}

SYSTEM_PROMPT = """당신은 멀리 사는 가족 보호자를 위해 노인의 주간 건강 데이터를 해석해주는, 따뜻하고 신중한 건강 도우미입니다.

규칙:
- 반드시 한국어로, 35~55세 보호자가 한 번에 이해할 수 있는 일상 언어로 작성합니다. "RMSSD 18ms" 같은 전문 수치는 쉬운 말로 풀어서 설명합니다.
- 의학적 '진단'을 하지 않습니다. 이 리포트는 wellness(생활 건강) 정보이며, 치매 등 어떤 질병도 진단하거나 단정하지 않습니다.
- 데이터가 나빠 보여도 보호자가 부모에게 화를 내거나 과도하게 불안해하지 않도록, 침착하고 비난 없는 어조를 유지합니다.
- 위험 수준 판정: 변화가 작거나 없으면 "안정", 추적할 만한 변화가 보이면 "관찰 권장", 여러 지표가 함께 뚜렷이 나빠졌으면 "주의 필요".
- headline은 보호자가 휴대폰 알림으로 받을 법한 차분한 한 문장.
- report는 무엇이 어떻게 변했는지, 그것이 일상에서 무슨 의미인지 2~4문단으로.
- recommended_action은 보호자가 이번 주에 실제로 할 수 있는, 부담 없고 구체적인 행동 1~2가지."""


def resolve_api_key() -> str:
    """환경변수 또는 assets/.env 에서 UPSTAGE_API_KEY를 읽는다."""
    key = os.environ.get("UPSTAGE_API_KEY", "").strip()
    if not key:
        env_file = SKILL_ROOT / "assets" / ".env"
        if env_file.exists():
            for raw in env_file.read_text(encoding="utf-8").splitlines():
                raw = raw.strip()
                if raw.startswith("#") or "=" not in raw:
                    continue
                name, _, value = raw.partition("=")
                if name.strip() == "UPSTAGE_API_KEY":
                    key = value.strip().strip('"').strip("'")
                    break
    if not key or key == "your-upstage-api-key-here":
        env_path = SKILL_ROOT / "assets" / ".env"
        sys.exit(
            "UPSTAGE_API_KEY가 설정되지 않았습니다.\n"
            "  1) https://console.upstage.ai 에서 API 키 발급\n"
            "     (Billing→Credit→Redeem code 에 UPWAVE-KOH 입력 시 $70 크레딧)\n"
            f"  2) {env_path} 파일을 만들고 'UPSTAGE_API_KEY=발급키' 추가\n"
            "     (assets/.env.example 참고)"
        )
    return key


def format_delta(current: float, previous: float | None, direction: str) -> str:
    """지난주 대비 변화를 사람이 읽을 수 있는 문자열로."""
    if previous is None:
        return ""
    diff = current - previous
    if abs(diff) < 1e-9:
        return " (지난주와 동일)"
    arrow = "▲" if diff > 0 else "▼"
    if direction == "up":
        mood = "개선" if diff > 0 else "악화"
    elif direction == "down":
        mood = "개선" if diff < 0 else "악화"
    else:
        mood = "변화"
    return f" ({arrow}{abs(diff):g}, 지난주 대비 {mood})"


def build_metrics_block(data: dict) -> str:
    """입력 데이터를 LLM 프롬프트용 지표 목록 텍스트로 변환."""
    current = data.get("current_week", {})
    previous = data.get("previous_week")
    lines = []
    for key, (label, unit, direction) in METRICS.items():
        if key not in current:
            continue
        cur = current[key]
        prev = previous.get(key) if previous else None
        lines.append(f"- {label}: {cur}{unit}{format_delta(cur, prev, direction)}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="주간 뇌 건강 리포트 생성 (Upstage Solar)")
    parser.add_argument("data", nargs="?", help="건강 데이터 JSON 파일 경로")
    args = parser.parse_args()

    data_path = Path(args.data) if args.data else SKILL_ROOT / "assets" / "sample_week.json"
    if not data_path.exists():
        sys.exit(f"데이터 파일을 찾을 수 없습니다: {data_path}")

    try:
        data = json.loads(data_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        sys.exit(f"JSON 파싱 실패: {exc}")

    if "current_week" not in data:
        sys.exit('입력 JSON에 "current_week" 키가 필요합니다. assets/sample_week.json 형식 참고.')

    metrics_block = build_metrics_block(data)
    if not metrics_block:
        sys.exit("인식 가능한 지표가 없습니다. 지원 지표: " + ", ".join(METRICS))

    elder = data.get("elder_name", "어르신")
    week = data.get("week_of", "이번 주")
    has_prev = "previous_week" in data

    user_prompt = (
        f"대상: {elder}\n"
        f"기간: {week}\n"
        f"{'지난주와 비교한 ' if has_prev else ''}주간 지표:\n"
        f"{metrics_block}\n\n"
        "위 데이터를 바탕으로 보호자용 주간 리포트를 작성해주세요."
    )

    client = OpenAI(api_key=resolve_api_key(), base_url=BASE_URL)
    try:
        resp = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            response_format=REPORT_SCHEMA,
            max_tokens=1500,
            temperature=0.4,
        )
    except Exception as exc:  # noqa: BLE001 - 사용자에게 원인 그대로 전달
        sys.exit(f"Upstage API 호출 실패: {exc}")

    result = json.loads(resp.choices[0].message.content)

    print()
    print("=" * 64)
    print(f"  주간 뇌 건강 리포트 — {elder}  ({week})")
    print("=" * 64)
    print(f"\n[ 위험 수준 ]   {result['risk_level']}")
    print(f"\n[ 한 줄 요약 ]\n  {result['headline']}")
    print(f"\n[ 리포트 ]\n{result['report']}")
    print(f"\n[ 이번 주 권장 행동 ]\n  {result['recommended_action']}")
    print()

    usage = resp.usage
    if usage is not None:
        print(
            f"(토큰 사용: 총 {usage.total_tokens}"
            f" — 입력 {usage.prompt_tokens} / 출력 {usage.completion_tokens})"
        )
    print()


if __name__ == "__main__":
    main()
