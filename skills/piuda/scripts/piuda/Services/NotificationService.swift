import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // 즉시 위험 알림 발송
    func sendRiskAlert(_ alert: DementiaAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body  = alert.message
        content.sound = .defaultCritical
        content.badge = 1
        content.userInfo = ["alertId": alert.id.uuidString, "riskLevel": alert.riskLevel.rawValue]

        let req = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // 매주 월요일 오전 9시 리포트 알림 예약
    func scheduleWeeklyReport() {
        let content = UNMutableNotificationContent()
        content.title = "주간 건강 리포트 준비됨"
        content.body  = "어르신의 이번 주 건강 리포트가 생성되었습니다."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 2  // 월요일
        comps.hour    = 9
        comps.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "weekly_report", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    // 병원 예약 하루 전 알림
    func scheduleAppointmentReminder(for appointment: HospitalAppointment) {
        guard let remindDate = Calendar.current.date(byAdding: .day, value: -1, to: appointment.scheduledDate) else { return }
        let content = UNMutableNotificationContent()
        content.title = "내일 병원 예약이 있습니다"
        content.body  = "\(appointment.hospital.name) — \(appointment.scheduledDate.formatted(date: .abbreviated, time: .shortened))"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: remindDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(
            identifier: "appointment_\(appointment.hospital.id.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
