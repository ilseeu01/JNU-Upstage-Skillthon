import SwiftUI

struct ReportsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            Group {
                if state.reports.isEmpty {
                    ContentUnavailableView(
                        "리포트 없음",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("홈에서 AI 분석을 실행하면 리포트가 생성됩니다")
                    )
                } else {
                    List {
                        ForEach(state.reports) { report in
                            NavigationLink {
                                ReportDetailView(report: report)
                            } label: {
                                ReportRowView(report: report)
                            }
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("리포트")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Shared Row View

struct ReportRowView: View {
    let report: WeeklyReport

    var body: some View {
        HStack(spacing: 14) {
            // Risk badge
            VStack(spacing: 4) {
                Image(systemName: report.riskLevel.icon)
                    .font(.title3)
                    .foregroundStyle(report.riskLevel.color)
                Text(report.riskLevel.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(report.riskLevel.color)
            }
            .frame(width: 56, height: 56)
            .background(report.riskLevel.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(weekRangeText(report))
                    .font(.subheadline.bold())

                Text(report.narrative.prefix(60) + (report.narrative.count > 60 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Mini trend tags
                HStack(spacing: 6) {
                    TrendTag(label: "수면", value: report.sleepTrend)
                    TrendTag(label: "보행", value: report.walkingTrend)
                    TrendTag(label: "HRV", value: report.hrvTrend)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func weekRangeText(_ r: WeeklyReport) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일"
        return "\(fmt.string(from: r.weekStart)) – \(fmt.string(from: r.weekEnd))"
    }
}

private struct TrendTag: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tagColor.opacity(0.15))
        .foregroundStyle(tagColor)
        .clipShape(Capsule())
    }

    private var tagColor: Color {
        value >= 0 ? Color(red: 0.18, green: 0.70, blue: 0.42) : Color(red: 0.94, green: 0.42, blue: 0.10)
    }
}

#Preview {
    ReportsView()
        .environment(AppState())
}
