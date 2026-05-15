# HealthKit 수집 지표 — 피우다

## 수면 분석

| 지표 | HealthKit 타입 | 설명 |
|------|---------------|------|
| 수면 효율 | `HKCategoryTypeIdentifierSleepAnalysis` | 총 침대 시간 대비 실제 수면 시간 (%) |
| 수면 시간 | 동일 | 총 수면 시간 (시간) |
| 야간 각성 횟수 | 동일 | 수면 중 깨어난 횟수 |
| 깊은 수면 비율 | 동일 | 전체 수면 중 깊은 수면 비율 (%) |

## 보행 분석

| 지표 | HealthKit 타입 | 정상 범위 |
|------|---------------|-----------|
| 보행 속도 | `HKQuantityTypeIdentifierWalkingSpeed` | ≥ 1.0 m/s |
| 일일 걸음 수 | `HKQuantityTypeIdentifierStepCount` | ≥ 5,000보 |
| 보행 비대칭 | `HKQuantityTypeIdentifierWalkingAsymmetryPercentage` | ≤ 5% |

## 심혈관 지표

| 지표 | HealthKit 타입 | 정상 범위 |
|------|---------------|-----------|
| HRV (SDNN) | `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | ≥ 30 ms |
| 안정 심박수 | `HKQuantityTypeIdentifierRestingHeartRate` | 60–100 bpm |

## 권한 요청

```swift
// HealthKitService.swift
let readTypes: Set<HKObjectType> = [
    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    HKObjectType.quantityType(forIdentifier: .walkingSpeed)!,
    HKObjectType.quantityType(forIdentifier: .stepCount)!,
    HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
    HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage)!
]
```

## watchOS 수집 항목

Watch에서는 `stepCount`와 `heartRate`만 직접 수집하고 iPhone으로 WatchConnectivity로 전송합니다.
나머지 지표는 iPhone HealthKit에서 통합 조회합니다.
