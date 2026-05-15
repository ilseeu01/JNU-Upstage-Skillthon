import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var apiKey: String = UpstageService.shared.apiKey
    @State private var showApiKey = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // 프로필
                if let profile = state.userProfile {
                    Section("내 프로필") {
                        LabeledContent("이름", value: profile.name)
                        LabeledContent("역할", value: profile.role == .caregiver ? "보호자" : "어르신")
                        LabeledContent("전화번호", value: masked(profile.phoneNumber))
                        if let paired = profile.pairedPhoneNumber {
                            LabeledContent(
                                profile.role == .caregiver ? "어르신 번호" : "보호자 번호",
                                value: masked(paired)
                            )
                        }
                    }
                }

                // Upstage API
                Section {
                    HStack {
                        if showApiKey {
                            TextField("sk-...", text: $apiKey)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            Text(apiKey.isEmpty ? "미설정" : String(repeating: "•", count: min(apiKey.count, 20)))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(apiKey.isEmpty ? .red : .secondary)
                        }
                        Spacer()
                        Button(showApiKey ? "숨기기" : "보기") {
                            showApiKey.toggle()
                        }
                        .font(.caption)
                    }

                    if showApiKey {
                        Button("저장") {
                            UpstageService.shared.apiKey = apiKey
                            showApiKey = false
                        }
                        .disabled(apiKey.isEmpty)
                    }
                } header: {
                    Text("Upstage Solar API")
                } footer: {
                    Text("api.upstage.ai에서 발급받은 API 키를 입력하세요. 키는 기기에만 저장됩니다.")
                }

                // 알림
                Section("알림 설정") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("알림 권한 확인", systemImage: "bell.badge")
                    }
                }

                // 모니터링 대상 (치매 고위험군 라이프로그 데이터셋)
                if !state.availableSubjects.isEmpty {
                    Section {
                        ForEach(state.availableSubjects) { subject in
                            Button {
                                state.selectDemoSubject(subject.subjectId)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subject.displayName)
                                            .foregroundStyle(.primary)
                                        Text("\(subject.diagnosisLabel) · MMSE \(subject.mmseTotal)/30")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if state.selectedSubject?.subjectId == subject.subjectId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("모니터링 대상 어르신")
                    } footer: {
                        Text("AI-Hub 치매 고위험군 라이프로그 데이터셋의 실제 피험자입니다. "
                             + "괄호 안 진단명은 데이터셋의 정답 라벨입니다.")
                    }
                }

                // 데이터
                Section("데이터") {
                    Button {
                        state.loadDemoData()
                    } label: {
                        Label("데이터셋 다시 불러오기", systemImage: "arrow.counterclockwise")
                    }
                }

                // 앱 정보
                Section("앱 정보") {
                    LabeledContent("버전", value: "1.0.0 (Beta)")
                    LabeledContent("개발", value: "piuda")
                    Link("개인정보 처리방침", destination: URL(string: "https://piuda.app/privacy")!)
                }

                // 로그아웃
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("설정")
            .alert("로그아웃", isPresented: $showLogoutConfirm) {
                Button("로그아웃", role: .destructive) { state.logout() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("로그아웃하면 모든 데이터가 초기화됩니다.")
            }
        }
    }

    private func masked(_ s: String) -> String {
        guard s.count >= 4 else { return s }
        return String(s.prefix(3)) + "****" + String(s.suffix(4))
    }
}

// MARK: - Notification Settings

private struct NotificationSettingsView: View {
    @State private var permissionGranted: Bool? = nil

    var body: some View {
        Form {
            Section {
                if let granted = permissionGranted {
                    HStack {
                        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(granted ? .green : .red)
                        Text(granted ? "알림 권한 허용됨" : "알림 권한 거부됨")
                    }
                    if !granted {
                        Link("설정에서 허용하기", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            } header: {
                Text("알림 권한 상태")
            }

            Section("예약 알림") {
                Label("매주 월요일 오전 9시 리포트 알림", systemImage: "calendar")
                    .font(.subheadline)
                Label("병원 예약 하루 전 알림", systemImage: "bell.badge")
                    .font(.subheadline)
            }
        }
        .navigationTitle("알림 설정")
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            permissionGranted = settings.authorizationStatus == .authorized
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
