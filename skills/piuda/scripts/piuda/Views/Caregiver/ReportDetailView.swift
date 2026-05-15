import SwiftUI
import Charts

struct ReportDetailView: View {
    let report: WeeklyReport
    @State private var showScheduler = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 위험도 헤더
                riskHeader

                // AI 리포트 텍스트
                narrativeSection

                // 주요 발견
                if !report.keyFindings.isEmpty {
                    findingsSection
                }

                // 건강 차트
                sleepChartSection
                walkingChartSection

                // 인지 테스트
                if let cog = report.latestCognitiveScore {
                    cognitiveSection(score: cog)
                }

                // 권고사항
                if !report.recommendations.isEmpty {
                    recommendationsSection
                }

                // 병원 예약 버튼 (위험도 moderate 이상)
                if report.riskLevel >= .moderate {
                    scheduleButton
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(weekRangeText)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScheduler) {
            HospitalSchedulerSheet(riskLevel: report.riskLevel)
        }
    }

    // MARK: - Sections

    private var riskHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("종합 위험도")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.riskLevel.displayName)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(report.riskLevel.color)
                    Text("점수 \(report.riskScore)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(report.riskLevel.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: report.riskLevel.icon)
                .font(.system(size: 52))
                .foregroundStyle(report.riskLevel.color)
        }
        .padding(20)
        .background(report.riskLevel.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI 분석 리포트", systemImage: "sparkles")
                .font(.headline)
            Text(report.narrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .cardStyle()
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("주요 발견")
                .font(.headline)
            ForEach(report.keyFindings, id: \.self) { finding in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(report.riskLevel.color)
                        .font(.subheadline)
                    Text(finding)
                        .font(.subheadline)
                }
            }
        }
        .cardStyle()
    }

    private var sleepChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("수면 효율", systemImage: "bed.double.fill")
                    .font(.headline)
                Spacer()
                trendBadge(report.sleepTrend)
            }
            Chart(report.snapshots) { snap in
                BarMark(
                    x: .value("날짜", snap.date, unit: .day),
                    y: .value("효율", snap.sleepEfficiency * 100)
                )
                .foregroundStyle(barColor(snap.sleepEfficiency))
                .cornerRadius(4)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 80, 100]) { val in
                    AxisValueLabel { Text("\(val.as(Int.self) ?? 0)%").font(.caption) }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { val in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption)
                    AxisGridLine(stroke: .init(lineWidth: 0))
                }
            }
            .frame(height: 140)

            // 참고 기준선 레전드
            HStack(spacing: 16) {
                legendDot(color: .green, label: "정상 (≥80%)")
                legendDot(color: .orange, label: "주의 (65-80%)")
                legendDot(color: .red, label: "위험 (<65%)")
            }
            .font(.caption)
        }
        .cardStyle()
    }

    private var walkingChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("보행 속도", systemImage: "figure.walk")
                    .font(.headline)
                Spacer()
                trendBadge(report.walkingTrend)
            }
            Chart(report.snapshots) { snap in
                LineMark(
                    x: .value("날짜", snap.date, unit: .day),
                    y: .value("속도", snap.walkingSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.green)

                AreaMark(
                    x: .value("날짜", snap.date, unit: .day),
                    y: .value("속도", snap.walkingSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [.green.opacity(0.25), .clear],
                    startPoint: .top, endPoint: .bottom
                ))

                RuleMark(y: .value("정상 기준", 1.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.orange.opacity(0.7))
            }
            .chartYScale(domain: 0.6...1.6)
            .chartYAxis {
                AxisMarks(values: [0.6, 1.0, 1.2, 1.6]) { val in
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text(String(format: "%.1f", v)).font(.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(.caption)
                    AxisGridLine(stroke: .init(lineWidth: 0))
                }
            }
            .frame(height: 140)
        }
        .cardStyle()
    }

    private func cognitiveSection(score: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("인지 테스트", systemImage: "brain.head.profile")
                .font(.headline)
            HStack(spacing: 20) {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: score / 100)
                        .stroke(cogColor(score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(score))")
                            .font(.title.bold())
                            .foregroundStyle(cogColor(score))
                        Text("/ 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 6) {
                    Text(cogLabel(score))
                        .font(.subheadline.bold())
                        .foregroundStyle(cogColor(score))
                    Text("Apple Watch 마이크로 인지 테스트 결과입니다. 의학적 진단이 아닙니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("권고사항", systemImage: "lightbulb.fill")
                .font(.headline)
            ForEach(report.recommendations, id: \.self) { rec in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline)
                    Text(rec)
                        .font(.subheadline)
                }
            }
        }
        .cardStyle()
    }

    private var scheduleButton: some View {
        Button {
            showScheduler = true
        } label: {
            HStack {
                Image(systemName: "calendar.badge.plus")
                Text("병원 예약 잡기")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var weekRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: report.weekStart)) — \(fmt.string(from: report.weekEnd))"
    }

    private func barColor(_ efficiency: Double) -> Color {
        if efficiency >= 0.80 { return .green }
        if efficiency >= 0.65 { return .orange }
        return .red
    }

    private func cogColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 65 { return .orange }
        return .red
    }

    private func cogLabel(_ score: Double) -> String {
        if score >= 80 { return "양호" }
        if score >= 65 { return "경계" }
        return "주의 필요"
    }

    private func trendBadge(_ value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
            Text(String(format: "%.0f%%", abs(value)))
        }
        .font(.caption.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((value >= 0 ? Color.green : Color.orange).opacity(0.15))
        .foregroundStyle(value >= 0 ? .green : .orange)
        .clipShape(Capsule())
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Card Style

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Hospital Scheduler Sheet

struct HospitalSchedulerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let riskLevel: RiskLevel

    @State private var selectedHospital: Hospital?
    @State private var appointmentDate = Date().addingTimeInterval(3 * 86400)
    @State private var isScheduling = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var hospitals: [Hospital] {
        riskLevel >= .high ? Array(Hospital.recommendations.prefix(4)) : Hospital.recommendations.filter { $0.specialty == "치매 상담·검사" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("추천 병원") {
                    ForEach(hospitals) { hospital in
                        HospitalRow(hospital: hospital, isSelected: selectedHospital?.id == hospital.id) {
                            selectedHospital = hospital
                        }
                    }
                }

                Section("예약 날짜") {
                    DatePicker("날짜 선택", selection: $appointmentDate,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                }

                if let hospital = selectedHospital, let url = hospital.naverReservationURL {
                    Section("온라인 예약") {
                        Link(destination: URL(string: url)!) {
                            HStack {
                                Image(systemName: "safari.fill")
                                Text("네이버 예약 바로가기")
                            }
                        }
                    }
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("병원 예약")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isScheduling ? "저장 중..." : "캘린더에 추가") {
                        guard let hospital = selectedHospital, let alert = state.alerts.first else { return }
                        isScheduling = true
                        Task {
                            do {
                                _ = try await state.scheduleAppointment(
                                    hospital: hospital,
                                    date: appointmentDate,
                                    alertId: alert.id
                                )
                                showSuccess = true
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            isScheduling = false
                        }
                    }
                    .disabled(selectedHospital == nil || isScheduling)
                }
            }
            .alert("예약 완료", isPresented: $showSuccess) {
                Button("확인") { dismiss() }
            } message: {
                Text("캘린더에 병원 예약이 추가되었습니다. 하루 전 알림을 보내드립니다.")
            }
        }
    }
}

private struct HospitalRow: View {
    let hospital: Hospital
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hospital.name).font(.subheadline.bold())
                    Text(hospital.specialty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dist = hospital.distanceKm {
                        Text(String(format: "%.1fkm", dist))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let state = AppState()
    return NavigationStack {
        ReportDetailView(report: state.reports[0])
            .environment(state)
    }
}
