#!/usr/bin/env python3
"""데이터 ↔ Upstage Solar API 연동 검증.

demo_subjects.json 의 한 피험자를 골라, 피우다 앱의 UpstageService 와
'동일한 방식'(엔드포인트/모델/프롬프트)으로 Upstage Solar LLM 을 호출해
주간 리포트가 정상 생성되는지 확인한다.

즉 이 스크립트는 iOS 앱을 빌드하기 전에 API 키 + 데이터 연동을
미리 검증하는 도구이자, Swift UpstageService 의 레퍼런스 구현이다.

사용법:
    python verify_upstage.py [--subject CN|MCI|Dem]
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
    sys.exit("openai 패키지가 필요합니다.  실행: pip install -r requirements.txt")

SCRIPT_DIR = Path(__file__).resolve().parent

# ── Upstage 설정 (Swift UpstageService 와 동일하게 유지할 것) ───────────────
UPSTAGE_BASE_URL = "https://api.upstage.ai/v1"          # /solar/ 없음에 주의
UPSTAGE_MODEL = "solar-pro3"                            # 현행 모델 별칭

SYSTEM_PROMPT = (
    "당신은 노인 인지 건강 모니터링 AI입니다. 워치 생체 데이터를 분석해 "
    "멀리 사는 보호자에게 주간 리포트를 작성합니다. "
    "규칙: 의학적 '진단'이 아닌 '관찰 보고'입니다. 일상 언어를 쓰고, 수치 변화를 "
    "구체적으로 언급하되 과도한 불안은 피합니다. 긍정적 변화도 함께 언급합니다. "
    "반드시 한국어로, 지정된 JSON 형식으로만 응답하세요."
)

REPORT_SCHEMA = {
    "type": "json_schema",
    "json_schema": {
        "name": "weekly_report",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "riskLevel": {"type": "string", "enum": ["낮음", "보통", "높음", "위험"]},
                "narrative": {"type": "string"},
                "keyFindings": {"type": "array", "items": {"type": "string"}},
                "recommendations": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["riskLevel", "narrative", "keyFindings", "recommendations"],
            "additionalProperties": False,
        },
    },
}


def load_api_key() -> str:
    key = os.environ.get("UPSTAGE_API_KEY", "").strip()
    if not key:
        env = SCRIPT_DIR / ".env"
        if env.exists():
            for line in env.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                name, _, value = line.partition("=")
                if name.strip() == "UPSTAGE_API_KEY":
                    key = value.strip().strip('"').strip("'")
                    break
    if not key or "xxxx" in key:
        sys.exit("UPSTAGE_API_KEY 가 없습니다. .env 파일을 확인하세요 (.env.example 참고).")
    return key


def week_average(snapshots: list[dict]) -> dict:
    """한 주 스냅샷들의 평균. walkingSpeed 0(미측정)은 평균에서 제외."""
    n = len(snapshots)
    if n == 0:
        return {}
    cog = [s["cognitiveScore"] for s in snapshots if s.get("cognitiveScore") is not None]
    return {
        "sleepEfficiency": sum(s["sleepEfficiency"] for s in snapshots) / n,
        "nightWakeCount": sum(s["nightWakeCount"] for s in snapshots) / n,
        "deepSleepRatio": sum(s["deepSleepRatio"] for s in snapshots) / n,
        "stepCount": sum(s["stepCount"] for s in snapshots) / n,
        "heartRateVariability": sum(s["heartRateVariability"] for s in snapshots) / n,
        "cognitiveScore": (sum(cog) / len(cog)) if cog else None,
    }


def build_user_prompt(name: str, this_week: dict, prev_week: dict | None) -> str:
    p = f"{name}의 1주간 Apple Watch 데이터 분석 리포트를 작성해주세요.\n\n"
    p += "【이번 주 평균】\n"
    p += f"• 수면 효율: {this_week['sleepEfficiency'] * 100:.0f}%\n"
    p += f"• 야간 각성: 평균 {this_week['nightWakeCount']:.1f}회\n"
    p += f"• 깊은 수면 비율: {this_week['deepSleepRatio'] * 100:.0f}%\n"
    p += f"• 하루 걸음 수: {this_week['stepCount']:.0f}보\n"
    p += f"• 심박변이도(HRV): {this_week['heartRateVariability']:.0f} ms\n"
    if this_week["cognitiveScore"] is not None:
        p += f"• 주간 인지검사: {this_week['cognitiveScore']:.0f}/100\n"

    if prev_week:
        def delta(key: str) -> str:
            cur, prev = this_week[key], prev_week[key]
            if not prev:
                return "—"
            pct = (cur - prev) / prev * 100
            return f"{'+' if pct >= 0 else ''}{pct:.0f}%"
        p += "\n【전주 대비】\n"
        p += f"• 수면 효율: {delta('sleepEfficiency')}\n"
        p += f"• 걸음 수: {delta('stepCount')}\n"
        p += f"• HRV: {delta('heartRateVariability')}\n"

    p += (
        "\n참고: 이 데이터는 Oura/워치 기반이라 보행 속도는 측정되지 않았습니다.\n\n"
        "다음 JSON 형식으로만 응답하세요:\n"
        '{"riskLevel": "낮음|보통|높음|위험", '
        '"narrative": "전체 리포트 (200자 이내)", '
        '"keyFindings": ["주요 발견 2~3개"], '
        '"recommendations": ["권고사항 1~2개"]}'
    )
    return p


def main() -> None:
    parser = argparse.ArgumentParser(description="데이터 ↔ Upstage 연동 검증")
    parser.add_argument("--subject", default="Dem", choices=["CN", "MCI", "Dem"],
                        help="검증에 사용할 진단 그룹 (기본: Dem)")
    parser.add_argument("--data", default=str(SCRIPT_DIR / "demo_subjects.json"))
    args = parser.parse_args()

    data_path = Path(args.data)
    if not data_path.exists():
        sys.exit(f"{data_path} 없음 — 먼저 build_demo_data.py 를 실행하세요.")
    data = json.loads(data_path.read_text(encoding="utf-8"))

    subject = next((s for s in data["subjects"] if s["diagnosis"] == args.subject), None)
    if subject is None:
        sys.exit(f"{args.subject} 그룹 피험자가 demo_subjects.json 에 없습니다.")

    weeks = subject["weeks"]
    if not weeks:
        sys.exit("해당 피험자에 주간 데이터가 없습니다.")
    this_week = week_average(weeks[0]["snapshots"])
    prev_week = week_average(weeks[1]["snapshots"]) if len(weeks) > 1 else None

    prompt = build_user_prompt(subject["displayName"], this_week, prev_week)

    print("=" * 64)
    print(f"  검증 대상: {subject['displayName']}  "
          f"[실제 진단: {subject['diagnosisLabel']} / MMSE {subject['mmseTotal']}/30]")
    print("=" * 64)
    print("\n[ Upstage 로 보낼 프롬프트 ]")
    print(prompt)
    print("\n" + "-" * 64)
    print(f"[ 호출 ] {UPSTAGE_BASE_URL}/chat/completions  model={UPSTAGE_MODEL}")

    client = OpenAI(api_key=load_api_key(), base_url=UPSTAGE_BASE_URL)
    try:
        resp = client.chat.completions.create(
            model=UPSTAGE_MODEL,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            response_format=REPORT_SCHEMA,
            temperature=0.3,
            max_tokens=900,
        )
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"\n❌ API 호출 실패: {exc}")

    report = json.loads(resp.choices[0].message.content)

    print("\n✅ API 응답 수신 — 리포트 생성 성공\n")
    print(f"[ 위험 수준 ]  {report['riskLevel']}")
    print(f"\n[ 리포트 ]\n{report['narrative']}")
    print("\n[ 주요 발견 ]")
    for f in report["keyFindings"]:
        print(f"  • {f}")
    print("\n[ 권고사항 ]")
    for r in report["recommendations"]:
        print(f"  • {r}")

    usage = resp.usage
    if usage is not None:
        print(f"\n(토큰: 총 {usage.total_tokens} / 입력 {usage.prompt_tokens} "
              f"/ 출력 {usage.completion_tokens})")
    print("\n데이터 → Upstage Solar 연동 검증 완료.")


if __name__ == "__main__":
    main()
