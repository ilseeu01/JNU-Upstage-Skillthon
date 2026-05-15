import SwiftUI

// Firebase가 SPM으로 추가되면 아래 블록이 자동 활성화됩니다
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
import UserNotifications
#endif

@main
struct piudaApp: App {
    @State private var appState = AppState()

    #if canImport(FirebaseCore)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

// MARK: - AppDelegate (Firebase + FCM)

#if canImport(FirebaseCore)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // FCM 토큰 갱신 → Firestore에 저장
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        // UserDefaults에 임시 저장, 로그인 후 Firestore에 업로드
        UserDefaults.standard.set(token, forKey: "fcm_token")
    }

    // 포그라운드 푸시 알림 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .badge, .sound])
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
#endif
