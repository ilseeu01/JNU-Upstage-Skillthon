#!/usr/bin/env python3
"""치매 고위험군 라이프로그 데이터셋 → 피우다 앱 demo_subjects.json 변환.

AI-Hub "치매 고위험군 라이프로그" 데이터셋(Oura 링 활동/수면 로그 + MMSE 인지검사)을
읽어, 피우다 iOS 앱의 HealthSnapshot 모델 형태로 변환한다.

처리 흐름:
    1) activity / sleep / mmse CSV 로드 (필요 컬럼만)
    2) 피험자(email) + 날짜 기준으로 일별 데이터 결합
    3) 진단 그룹(CN/MCI/Dem)별 대표 피험자 선정 (데이터가 가장 많은 사람)
    4) 최근 4주를 주(week) 단위로 잘라 HealthSnapshot 으로 변환
    5) demo_subjects.json 출력 → iOS 앱이 번들로 읽어 사용

사용법:
    python build_demo_data.py [--data-root <경로>] [--out demo_subjects.json]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    sys.exit("pandas 가 필요합니다.  실행: pip install -r requirements.txt")

SCRIPT_DIR = Path(__file__).resolve().parent
# data_pipeline → scripts → piuda → skills → JNU-Upstage-Skillthon → ICTinnovation
DEFAULT_DATA_ROOT = (
    SCRIPT_DIR.parents[4] / "piuda" / "128.치매 고위험군 라이프로그" / "01.데이터"
)

# Oura 수면 단계 코드 (hypnogram_5min): 1=깊은수면 2=얕은수면 3=REM 4=각성
SLEEP_STAGE_AWAKE = "4"
SLEEP_STAGE_SLEEP = {"1", "2", "3"}

DIAGNOSIS_LABEL = {"CN": "정상", "MCI": "경도인지장애", "Dem": "치매"}


def night_wake_count(hypnogram: object) -> int | None:
    """수면 단계열에서 '수면 → 각성' 전환 횟수를 센다 (입면 전 각성은 제외)."""
    if not isinstance(hypnogram, str) or not hypnogram.strip():
        return None
    stages = [s for s in hypnogram.split("/") if s != ""]
    count, prev = 0, None
    for s in stages:
        if s == SLEEP_STAGE_AWAKE and prev in SLEEP_STAGE_SLEEP:
            count += 1
        prev = s
    return count


def load_activity(path: Path) -> pd.DataFrame:
    cols = [
        "EMAIL", "activity_steps", "activity_score",
        "activity_average_met", "activity_daily_movement",
        "activity_cal_total", "activity_day_start",
    ]
    df = pd.read_csv(path, usecols=cols)
    df["email"] = df["EMAIL"].astype(str).str.strip()
    df["date"] = df["activity_day_start"].astype(str).str[:10]
    df = df[df["date"].str.match(r"\d{4}-\d{2}-\d{2}")]
    # 하루 1행이 정상 — 혹시 중복 시 걸음 수가 큰 쪽 유지
    df = df.sort_values("activity_steps", ascending=False)
    return df.drop_duplicates(["email", "date"], keep="first")


def load_sleep(path: Path) -> pd.DataFrame:
    hypno_col = "CONVERT(sleep_hypnogram_5min USING utf8)"
    cols = [
        "EMAIL", "sleep_efficiency", "sleep_total", "sleep_duration",
        "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake",
        "sleep_rmssd", "sleep_hr_average", "sleep_hr_lowest",
        "sleep_score", "sleep_bedtime_end", hypno_col,
    ]
    df = pd.read_csv(path, usecols=cols)
    df["email"] = df["EMAIL"].astype(str).str.strip()
    df["date"] = df["sleep_bedtime_end"].astype(str).str[:10]
    df = df[df["date"].str.match(r"\d{4}-\d{2}-\d{2}")]
    df["wake_count"] = df[hypno_col].apply(night_wake_count)
    # 하루에 여러 수면 기록(낮잠 등)이 있으면 가장 긴 수면만 사용
    df = df.sort_values("sleep_total", ascending=False)
    return df.drop_duplicates(["email", "date"], keep="first")


def load_mmse(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, usecols=["SAMPLE_EMAIL", "DIAG_NM", "TOTAL"])
    df["email"] = df["SAMPLE_EMAIL"].astype(str).str.strip()
    return df.drop_duplicates("email", keep="first")


def safe_float(value: object, default: float | None = None) -> float | None:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return default
    if f != f:  # NaN
        return default
    return f


def to_snapshot(row: dict, cognitive: float | None) -> dict:
    """일별 결합 데이터 1행 → HealthSnapshot JSON.

    보행 속도/비대칭은 Oura 데이터에 존재하지 않으므로 0(미측정)으로 둔다.
    앱의 위험 점수 계산은 walkingSpeed <= 0 을 '데이터 없음'으로 건너뛴다.
    """
    sleep_total = safe_float(row.get("sleep_total"), 0.0) or 0.0
    sleep_eff_raw = safe_float(row.get("sleep_efficiency"))
    deep = safe_float(row.get("sleep_deep"), 0.0) or 0.0
    awake_sec = safe_float(row.get("sleep_awake"), 0.0) or 0.0

    wake = row.get("wake_count")
    if wake is None or (isinstance(wake, float) and wake != wake):
        wake = round(min(awake_sec / 900.0, 8))  # 폴백: 각성 시간 기반 추정

    return {
        "date": f"{row['date']}T12:00:00Z",
        "sleepEfficiency": round((sleep_eff_raw or 0.0) / 100.0, 4),
        "sleepDuration": round(sleep_total, 1),
        "nightWakeCount": int(wake),
        "deepSleepRatio": round(deep / sleep_total, 4) if sleep_total > 0 else 0.0,
        "walkingSpeed": 0.0,        # Oura 데이터에 없음 → 미측정
        "stepCount": int(safe_float(row.get("activity_steps"), 0.0) or 0.0),
        "walkingAsymmetry": 0.0,    # Oura 데이터에 없음 → 미측정
        "heartRateVariability": round(safe_float(row.get("sleep_rmssd"), 0.0) or 0.0, 1),
        "restingHeartRate": round(safe_float(row.get("sleep_hr_average"), 0.0) or 0.0, 1),
        "cognitiveScore": cognitive,
    }


def build_weeks(daily: pd.DataFrame, cognitive: float | None) -> list[dict]:
    """피험자 일별 데이터를 최근 4주 단위로 쪼갠다 (weekIndex 0 = 최근)."""
    rows = daily.sort_values("date").to_dict("records")
    recent = rows[-28:]
    weeks: list[dict] = []
    end = len(recent)
    week_index = 0
    while end > 0 and week_index < 4:
        chunk = recent[max(0, end - 7):end]
        snaps = [to_snapshot(r, None) for r in chunk]
        if snaps:
            snaps[-1]["cognitiveScore"] = cognitive  # 주 1회 인지검사 = 마지막 날
            weeks.append({
                "weekIndex": week_index,
                "weekStart": chunk[0]["date"][:10],
                "weekEnd": chunk[-1]["date"][:10],
                "snapshots": snaps,
            })
        end -= 7
        week_index += 1
    return weeks


def pick_subjects(daily: pd.DataFrame, mmse: pd.DataFrame) -> list[dict]:
    """진단 그룹별로 데이터가 가장 많은 대표 피험자 1명씩 선정."""
    day_counts = daily.groupby("email").size().rename("day_count")
    merged = mmse.join(day_counts, on="email").dropna(subset=["day_count"])
    merged = merged[merged["day_count"] >= 14]  # 최소 2주치 보유

    chosen: list[dict] = []
    labels = [("CN", "어르신 A"), ("MCI", "어르신 B"), ("Dem", "어르신 C")]
    for diag, display in labels:
        group = merged[merged["DIAG_NM"] == diag].sort_values("day_count", ascending=False)
        if group.empty:
            print(f"  ⚠ {diag} 그룹에 적격 피험자가 없습니다 — 건너뜀")
            continue
        top = group.iloc[0]
        chosen.append({
            "email": top["email"],
            "display": display,
            "diagnosis": diag,
            "mmse_total": int(top["TOTAL"]),
        })
    return chosen


def main() -> None:
    parser = argparse.ArgumentParser(description="라이프로그 → demo_subjects.json")
    parser.add_argument("--data-root", default=str(DEFAULT_DATA_ROOT),
                        help="데이터셋 01.데이터 폴더 경로")
    parser.add_argument("--split", default="1.Training", choices=["1.Training", "2.Validation"])
    parser.add_argument("--out", default=str(SCRIPT_DIR / "demo_subjects.json"))
    args = parser.parse_args()

    root = Path(args.data_root) / args.split / "원천데이터"
    act_path = root / "1.걸음걸이" / ("train_activity.csv" if "Training" in args.split else "val_activity.csv")
    slp_path = root / "2.수면" / ("train_sleep.csv" if "Training" in args.split else "val_sleep.csv")
    mmse_path = root / "3.인지기능" / ("train_mmse.csv" if "Training" in args.split else "val_mmse.csv")

    for p in (act_path, slp_path, mmse_path):
        if not p.exists():
            sys.exit(f"파일을 찾을 수 없습니다: {p}\n--data-root 경로를 확인하세요.")

    print(f"데이터셋: {root}")
    print("CSV 로딩 중...")
    activity = load_activity(act_path)
    sleep = load_sleep(slp_path)
    mmse = load_mmse(mmse_path)
    print(f"  activity {len(activity)}일분 / sleep {len(sleep)}일분 / mmse {len(mmse)}명")

    # 일별 결합 — 수면 기록이 있는 날을 기준으로 활동 데이터를 붙임
    daily = pd.merge(
        sleep[["email", "date", "sleep_efficiency", "sleep_total", "sleep_duration",
               "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake", "sleep_rmssd",
               "sleep_hr_average", "sleep_hr_lowest", "sleep_score", "wake_count"]],
        activity[["email", "date", "activity_steps", "activity_score",
                  "activity_average_met", "activity_daily_movement"]],
        on=["email", "date"], how="left",
    )
    print(f"  결합된 일별 레코드: {len(daily)}건")

    subjects_meta = pick_subjects(daily, mmse)
    if not subjects_meta:
        sys.exit("선정된 피험자가 없습니다.")

    subjects_json = []
    for meta in subjects_meta:
        sub_daily = daily[daily["email"] == meta["email"]]
        cognitive = round(meta["mmse_total"] / 30.0 * 100.0, 1)
        weeks = build_weeks(sub_daily, cognitive)
        subjects_json.append({
            "subjectId": meta["email"],
            "displayName": meta["display"],
            "diagnosis": meta["diagnosis"],
            "diagnosisLabel": DIAGNOSIS_LABEL.get(meta["diagnosis"], meta["diagnosis"]),
            "mmseTotal": meta["mmse_total"],
            "cognitiveScore": cognitive,
            "weeks": weeks,
        })
        print(f"  ✓ {meta['display']} [{meta['diagnosis']}] "
              f"MMSE {meta['mmse_total']}/30 → 인지점수 {cognitive} / {len(weeks)}주")

    output = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": f"AI-Hub 치매 고위험군 라이프로그 ({args.split})",
        "note": ("Oura 링 기반 데이터로 보행 속도/보행 비대칭은 존재하지 않아 "
                 "0(미측정)으로 표기됨. 앱은 이를 위험 계산에서 제외함."),
        "subjects": subjects_json,
    }

    out_path = Path(args.out)
    out_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n출력 완료: {out_path}  ({out_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
