import SwiftUI

struct WatchRootView: View {
    @Environment(WatchAppState.self) private var state
    @State private var showTest = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // 연결 상태
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isConnectedToPhone ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(state.isConnectedToPhone ? "iPhone 연결됨" : "연결 대기")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // 걸음 수
                    VStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                            .font(.title3)
                            .foregroundStyle(.green)
                        Text("\(state.stepCount)")
                            .font(.title2.bold())
                        Text("걸음")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 심박수
                    if state.heartRate > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("\(Int(state.heartRate)) bpm")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // 인지 테스트
                    if state.testDoneThisWeek {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("이번 주 테스트 완료")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button {
                            showTest = true
                        } label: {
                            Label("인지 테스트", systemImage: "brain.head.profile")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    // 마지막 동기화
                    if let sync = state.lastSyncAt {
                        Text("동기화: \(sync.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("피우다")
        }
        .sheet(isPresented: $showTest) {
            WatchCognitiveTestView { score in
                state.sendCognitiveResult(score: score)
            }
        }
    }
}
