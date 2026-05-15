import SwiftUI

struct AlertCenterView: View {
    @Environment(AppState.self) private var state
    @State private var selectedAlert: DementiaAlert?

    var body: some View {
        NavigationStack {
            Group {
                if state.alerts.isEmpty {
                    ContentUnavailableView(
                        "알림 없음",
                        systemImage: "bell.slash",
                        description: Text("위험 신호가 감지되면 여기에 알림이 표시됩니다")
                    )
                } else {
                    List {
                        ForEach(state.alerts) { alert in
                            AlertRow(alert: alert)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                                .listRowSeparator(.hidden)
                                .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture { selectedAlert = alert }
                        }
                    }
                    .listStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("알림 센터")
            .background(Color(.systemGroupedBackground))
            .sheet(item: $selectedAlert) { alert in
                AlertDetailSheet(alert: alert)
            }
        }
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    let alert: DementiaAlert

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(alert.riskLevel.backgroundColor)
                    .frame(width: 48, height: 48)
                Image(systemName: alert.riskLevel.icon)
                    .font(.title3)
                    .foregroundStyle(alert.riskLevel.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.subheadline.bold())
                    Spacer()
                    if !alert.isAcknowledged {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    RiskBadge(level: alert.riskLevel)

                    if alert.scheduledAppointment != nil {
                        Label("예약됨", systemImage: "calendar.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Text(alert.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(alert.isAcknowledged ? 0.65 : 1.0)
    }
}

// MARK: - Alert Detail Sheet

private struct AlertDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let alert: DementiaAlert

    @State private var showScheduler = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 위험도 헤더
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            RiskBadge(level: alert.riskLevel)
                            Text(alert.title)
                                .font(.title3.bold())
                            Text(alert.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: alert.riskLevel.icon)
                            .font(.system(size: 44))
                            .foregroundStyle(alert.riskLevel.color)
                    }
                    .padding(18)
                    .background(alert.riskLevel.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 트리거 요인
                    if !alert.triggerFactors.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("감지된 변화", systemImage: "waveform.path.ecg")
                                .font(.headline)
                            ForEach(alert.triggerFactors, id: \.self) { factor in
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(alert.riskLevel.color)
                                    Text(factor)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .cardStyle()
                    }

                    // 기존 예약 표시
                    if let appt = alert.scheduledAppointment {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("예약 완료", systemImage: "calendar.badge.checkmark")
                                .font(.headline)
                                .foregroundStyle(.green)
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appt.hospital.name).font(.subheadline.bold())
                                    Text(appt.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)
                            }
                        }
                        .cardStyle()
                    }

                    // 추천 병원 목록
                    if !alert.recommendedHospitals.isEmpty && alert.scheduledAppointment == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("추천 병원", systemImage: "cross.case.fill")
                                .font(.headline)

                            ForEach(alert.recommendedHospitals) { hospital in
                                HospitalCard(hospital: hospital)
                            }
                        }
                        .cardStyle()

                        // 캘린더 예약 버튼
                        Button {
                            showScheduler = true
                            state.acknowledgeAlert(id: alert.id)
                        } label: {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                Text("병원 일정 바로 잡기")
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
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("알림 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showScheduler) {
                HospitalSchedulerSheet(riskLevel: alert.riskLevel)
            }
        }
    }
}

// MARK: - Hospital Card

private struct HospitalCard: View {
    let hospital: Hospital

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cross.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(hospital.name)
                    .font(.subheadline.bold())
                HStack(spacing: 6) {
                    Text(hospital.specialty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dist = hospital.distanceKm {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fkm", dist))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            // 전화 버튼
            if let url = URL(string: "tel:\(hospital.phone.replacingOccurrences(of: "-", with: ""))") {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                        .padding(8)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Shared Risk Badge

struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Text(level.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(level.backgroundColor)
            .foregroundStyle(level.color)
            .clipShape(Capsule())
    }
}

#Preview {
    AlertCenterView()
        .environment(AppState())
}
