import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var step: Step = .roleSelection
    @State private var selectedRole: UserRole = .caregiver
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var pairedPhone: String = ""
    @State private var isSubmitting = false

    enum Step { case roleSelection, profileInput, pairing }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    ProgressView(value: progressValue)
                        .tint(Color.accentColor)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Group {
                        switch step {
                        case .roleSelection: roleSelectionStep
                        case .profileInput:  profileInputStep
                        case .pairing:       pairingStep
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Steps

    private var roleSelectionStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("피우다")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.primary)
                Text("부모님의 뇌 건강을\n매일 곁에서 지킵니다")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                RoleCard(
                    role: .caregiver,
                    selected: selectedRole == .caregiver,
                    icon: "person.2.fill",
                    title: "보호자",
                    subtitle: "부모님의 건강을 모니터링합니다"
                ) { selectedRole = .caregiver }

                RoleCard(
                    role: .elder,
                    selected: selectedRole == .elder,
                    icon: "applewatch",
                    title: "어르신 (착용자)",
                    subtitle: "Apple Watch로 건강 데이터를 수집합니다"
                ) { selectedRole = .elder }
            }
            .padding(.horizontal)

            Spacer()

            nextButton("시작하기") { step = .profileInput }
                .padding(.horizontal)
                .padding(.bottom, 40)
        }
    }

    private var profileInputStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text(selectedRole == .caregiver ? "보호자 정보 입력" : "어르신 정보 입력")
                    .font(.title2.bold())
                Text("입력하신 정보는 기기에만 저장됩니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                InputField(icon: "person.fill", placeholder: "이름", text: $name)
                InputField(icon: "phone.fill", placeholder: "전화번호 (예: 01012345678)",
                           text: $phone, keyboardType: .phonePad)
            }
            .padding(.horizontal)

            Spacer()

            nextButton("다음") {
                withAnimation { step = .pairing }
            }
            .disabled(name.isEmpty || phone.count < 10)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private var pairingStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: selectedRole == .caregiver ? "link.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)

                Text(selectedRole == .caregiver ? "어르신 연결" : "보호자 연결")
                    .font(.title2.bold())

                Text(selectedRole == .caregiver
                     ? "어르신의 전화번호를 입력하면\n건강 데이터를 받아볼 수 있습니다"
                     : "보호자의 전화번호를 입력하면\n건강 리포트를 전송할 수 있습니다"
                )
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }

            InputField(
                icon: "phone.circle.fill",
                placeholder: selectedRole == .caregiver ? "어르신 전화번호" : "보호자 전화번호",
                text: $pairedPhone,
                keyboardType: .phonePad
            )
            .padding(.horizontal)

            Button(action: { pairedPhone = "" }) {
                Text("나중에 연결하기")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            nextButton(isSubmitting ? "설정 중..." : "완료") {
                guard !isSubmitting else { return }
                isSubmitting = true
                let profile = UserProfile(
                    role: selectedRole,
                    name: name,
                    phoneNumber: phone,
                    pairedPhoneNumber: pairedPhone.isEmpty ? nil : pairedPhone
                )
                state.completeOnboarding(profile: profile)
            }
            .disabled(isSubmitting)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helpers

    private var progressValue: Double {
        switch step {
        case .roleSelection: return 0.33
        case .profileInput:  return 0.66
        case .pairing:       return 1.0
        }
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .fontWeight(.semibold)
                if title != "완료" && !title.contains("중") {
                    Image(systemName: "chevron.right")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subviews

private struct RoleCard: View {
    let role: UserRole
    let selected: Bool
    let icon: String
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(selected ? Color.accentColor : Color(.systemFill))
                    .foregroundStyle(selected ? .white : .secondary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
