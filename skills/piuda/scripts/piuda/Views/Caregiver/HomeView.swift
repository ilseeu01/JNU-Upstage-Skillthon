import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingAnalysis = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 최신 위험도 카드
                    if let report = state.latestReport {
                        RiskSummaryCard(report: report)
                    } else {
                        EmptyStateCard()
                    }

                    // 미확인 알림 배너
                    if state.unreadAlertCount > 0 {
                        AlertBannerButton()
                    }

                    // 주요 지표 요약
                    if let report = state.latestReport {
                        MetricsSummarySection(report: report)
                    }

                    // AI 분석 실행 버튼
                    AgentRunButton(isLoading: state.isLoading) {
                        Task { await state.runAnalysis() }
                    }

                    // 최근 리포트 목록 (3개)
                    if !state.reports.isEmpty {
                        RecentReportsList()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("피우다")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let profile = state.userProfile {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(profile.name)
                                .font(.caption.bold())
                            Text("보호자")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .alert("오류", isPresented: Binding(
                get: { state.showError },
                set: { state.showError = $0 }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(state.errorMessage ?? "")
            }
            .refreshable {
                await state.runAnalysis()
            }
        }
    }
}

// MARK: - Risk Summary Card

private struct RiskSummaryCard: View {
    let report: WeeklyReport

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이번 주 건강 상태")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.riskLevel.displayName)
                        .font(.title.bold())
                        .foregroundStyle(report.riskLevel.color)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(report.riskLevel.backgroundColor)
                        .frame(width: 64, height: 64)
                    Image(systemName: report.riskLevel.icon)
                        .font(.title)
                        .foregroundStyle(report.riskLevel.color)
                }
            }
            .padding(20)
            .background(report.riskLevel.backgroundColor)

            // Narrative
            Text(report.narrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Key findings
            if !report.keyFindings.isEmpty {
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Text("주요 변화")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    ForEach(report.keyFindings.prefix(3), id: \.self) { finding in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(report.riskLevel.color)
                                .frame(width: 6, height: 6)
                            Text(finding)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
            }

            // Footer
            HStack {
                Text(report.generatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    ReportDetailView(report: report)
                } label: {
                    Text("자세히 보기")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Metrics Summary

private struct MetricsSummarySection: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("주간 지표")
                .font(.headline)

            HStack(spacing: 12) {
                MetricTile(
                    icon: "bed.double.fill",
                    title: "수면 효율",
                    value: "\(Int(report.averageSleepEfficiency * 100))%",
                    trend: report.sleepTrend,
                    color: .blue
                )
                MetricTile(
                    icon: "figure.walk",
                    title: "보행 속도",
                    value: String(format: "%.2f m/s", report.averageWalkingSpeed),
                    trend: report.walkingTrend,
                    color: .green
                )
                MetricTile(
                    icon: "waveform.path.ecg",
                    title: "HRV",
                    value: "\(Int(report.averageHRV)) ms",
                    trend: report.hrvTrend,
                    color: .red
                )
            }
        }
    }
}

private struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    let trend: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                Text(String(format: "%.0f%%", abs(trend)))
            }
            .font(.caption2)
            .foregroundStyle(trendColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trendColor: Color {
        // 수면·보행·HRV 모두 증가가 좋음
        trend >= 0 ? Color(red: 0.18, green: 0.70, blue: 0.42) : Color(red: 0.94, green: 0.42, blue: 0.10)
    }
}

// MARK: - Alert Banner

private struct AlertBannerButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationLink {
            AlertCenterView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.red)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("미확인 알림 \(state.unreadAlertCount)건")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("확인이 필요한 건강 경보가 있습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Agent Run Button

private struct AgentRunButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isLoading ? "AI 분석 중..." : "지금 AI 분석 실행")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isLoading ? Color.accentColor.opacity(0.6) : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Recent Reports List

private struct RecentReportsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("최근 리포트")
                .font(.headline)

            ForEach(state.reports.prefix(3)) { report in
                NavigationLink {
                    ReportDetailView(report: report)
                } label: {
                    ReportRowView(report: report)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Empty State

private struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.circle")
                .font(.system(size: 50))
                .foregroundStyle(Color.accentColor.opacity(0.5))
            Text("첫 번째 분석을 시작하세요")
                .font(.headline)
            Text("아래 버튼을 눌러 AI 분석을 실행하거나\n다음 주 월요일에 자동으로 생성됩니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    let state = AppState()
    return NavigationStack {
        HomeView()
            .environment(state)
    }
}
