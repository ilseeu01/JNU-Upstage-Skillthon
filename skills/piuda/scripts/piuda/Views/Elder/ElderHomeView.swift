import SwiftUI

struct ElderHomeView: View {
    @Environment(AppState.self) private var state
    @State private var showCognitiveTest = false
    @State private var todayTestDone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 상태 카드
                    connectionStatusCard

                    // 오늘의 활동 요약
                    todayActivityCard

                    // 주간 인지 테스트 버튼
                    cognitiveTestButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("피우다")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showCognitiveTest) {
            CognitiveTestView(onComplete: { score in
                todayTestDone = true
            })
        }
    }

    // MARK: - Subviews

    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "applewatch.side.right")
                        .font(.title)
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Apple Watch 연결됨")
                            .font(.subheadline.bold())
                    }
                    Text("건강 데이터가 자동으로 수집되고 있어요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let profile = state.userProfile, let paired = profile.pairedPhoneNumber {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("보호자(\(masked(paired)))와 연결됨")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                HStack {
                    Image(systemName: "person.2.slash")
                        .foregroundStyle(.orange)
                    Text("보호자가 아직 연결되지 않았어요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var todayActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("오늘 건강 요약")
                .font(.headline)

            let snap = HealthSnapshot.mock(for: Date())

            HStack(spacing: 0) {
                ElderMetricItem(
                    icon: "figure.walk",
                    value: "\(snap.stepCount)보",
                    label: "걸음 수",
                    color: .green
                )
                Divider().frame(height: 50)
                ElderMetricItem(
                    icon: "bed.double.fill",
                    value: "\(Int(snap.sleepEfficiency * 100))%",
                    label: "수면 효율",
                    color: .blue
                )
                Divider().frame(height: 50)
                ElderMetricItem(
                    icon: "heart.fill",
                    value: "\(Int(snap.restingHeartRate))bpm",
                    label: "심박수",
                    color: .red
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cognitiveTestButton: some View {
        VStack(spacing: 12) {
            if todayTestDone {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("이번 주 인지 테스트 완료!")
                            .font(.subheadline.bold())
                        Text("수고하셨어요. 다음 주에 또 진행해요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button {
                    showCognitiveTest = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: "brain.head.profile")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("이번 주 인지 테스트")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("약 2분 소요 • 5문항")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func masked(_ phone: String) -> String {
        guard phone.count >= 4 else { return phone }
        return String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }
}

private struct ElderMetricItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cognitive Test View

struct CognitiveTestView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Double) -> Void

    @State private var currentQ = 0
    @State private var selectedIndex: Int? = nil
    @State private var correctCount = 0
    @State private var showResult = false
    @State private var startTime = Date()

    private let questions: [CognitiveQuestion] = [
        CognitiveQuestion(
            question: "오늘은 무슨 요일인가요?",
            options: ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"],
            correctIndex: Calendar.current.component(.weekday, from: Date()) - 2,
            type: .orientation
        ),
        CognitiveQuestion(
            question: "다음 중 계절이 다른 달은?",
            options: ["12월", "1월", "2월", "6월"],
            correctIndex: 3,
            type: .orientation
        ),
        CognitiveQuestion(
            question: "100에서 7을 빼면?",
            options: ["91", "93", "95", "97"],
            correctIndex: 1,
            type: .calculation
        ),
        CognitiveQuestion(
            question: "사과, 기차, 책상 — 방금 읽은 단어 중 탈것은?",
            options: ["사과", "기차", "책상", "없음"],
            correctIndex: 1,
            type: .wordRecall
        ),
        CognitiveQuestion(
            question: "○ △ □ ○ △ — 다음에 올 모양은?",
            options: ["○", "△", "□", "☆"],
            correctIndex: 2,
            type: .patternTap
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress
                ProgressView(value: Double(currentQ) / Double(questions.count))
                    .tint(Color.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if showResult {
                    resultView
                } else {
                    questionView
                }
            }
            .navigationTitle("인지 테스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("나중에") { dismiss() }
                }
            }
        }
    }

    private var questionView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("\(currentQ + 1) / \(questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(questions[currentQ].question)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                ForEach(Array(questions[currentQ].options.enumerated()), id: \.offset) { idx, option in
                    let isSelected = selectedIndex == idx
                    Button {
                        guard selectedIndex == nil else { return }
                        selectedIndex = idx
                        if idx == questions[currentQ].correctIndex { correctCount += 1 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if currentQ < questions.count - 1 {
                                currentQ += 1
                                selectedIndex = nil
                            } else {
                                showResult = true
                            }
                        }
                    } label: {
                        Text(option)
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()

            let score = Double(correctCount) / Double(questions.count) * 100

            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("\(Int(score))")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(scoreColor(score))
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 8) {
                Text(scoreLabel(score))
                    .font(.title2.bold())
                Text("\(questions.count)문제 중 \(correctCount)개 정답")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("결과가 보호자에게 전달됩니다.\n이 검사는 의학적 진단이 아닙니다.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onComplete(score)
                dismiss()
            } label: {
                Text("완료")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func scoreLabel(_ score: Double) -> String {
        if score >= 80 { return "훌륭해요!" }
        if score >= 60 { return "양호해요" }
        return "조금 더 관심이 필요해요"
    }
}

#Preview {
    ElderHomeView()
        .environment(AppState())
}
