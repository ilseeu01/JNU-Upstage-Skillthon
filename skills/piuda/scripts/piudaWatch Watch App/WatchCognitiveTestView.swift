import SwiftUI

struct WatchCognitiveTestView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Double) -> Void

    @State private var currentQ = 0
    @State private var correct = 0
    @State private var selected: Int? = nil
    @State private var done = false

    private let questions: [(q: String, opts: [String], ans: Int)] = [
        (
            "오늘 무슨 요일?",
            ["월", "화", "수", "목", "금", "토", "일"],
            max(0, Calendar.current.component(.weekday, from: Date()) - 2)
        ),
        (
            "100 - 7 = ?",
            ["91", "93", "95", "97"],
            1
        ),
        (
            "사과는?",
            ["채소", "과일", "곡식", "육류"],
            1
        ),
        (
            "아침 식사는?",
            ["점심", "저녁", "아침", "야식"],
            2
        )
    ]

    var body: some View {
        Group {
            if done {
                resultView
            } else {
                questionView
            }
        }
    }

    private var questionView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\(currentQ + 1)/\(questions.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(questions[currentQ].q)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                ForEach(Array(questions[currentQ].opts.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        guard selected == nil else { return }
                        selected = idx
                        if idx == questions[currentQ].ans { correct += 1 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            if currentQ < questions.count - 1 {
                                currentQ += 1
                                selected = nil
                            } else {
                                done = true
                            }
                        }
                    } label: {
                        Text(opt)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected == idx ? Color.blue : Color.gray.opacity(0.25))
                            .foregroundStyle(selected == idx ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var resultView: some View {
        VStack(spacing: 10) {
            let score = Double(correct) / Double(questions.count) * 100

            Image(systemName: correct >= 3 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title)
                .foregroundStyle(correct >= 3 ? .green : .orange)

            Text("\(correct)/\(questions.count) 정답")
                .font(.headline)

            Text(correct >= 3 ? "잘 하셨어요!" : "수고하셨어요")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("완료") {
                onComplete(score)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
