import Foundation
import EventKit

@Observable
final class CalendarService {
    private let store = EKEventStore()
    var isAuthorized = false

    func requestPermission() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    // 병원 예약 일정을 캘린더에 추가하고 eventId 반환
    func addAppointment(hospital: Hospital, date: Date, notes: String = "") async throws -> String {
        if !isAuthorized {
            let ok = await requestPermission()
            guard ok else { throw CalendarError.permissionDenied }
        }

        let event = EKEvent(eventStore: store)
        event.title    = "🏥 병원 예약 — \(hospital.name)"
        event.location = hospital.address
        event.startDate = date
        event.endDate   = Calendar.current.date(byAdding: .hour, value: 1, to: date)!
        event.notes = """
            병원: \(hospital.name)
            주소: \(hospital.address)
            전화: \(hospital.phone)
            진료과: \(hospital.specialty)
            \(notes.isEmpty ? "" : "\n메모: \(notes)")
            """
        event.calendar = store.defaultCalendarForNewEvents

        // 하루 전 알림 추가
        event.addAlarm(EKAlarm(relativeOffset: -86400))
        // 2시간 전 알림
        event.addAlarm(EKAlarm(relativeOffset: -7200))

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier ?? UUID().uuidString
    }

    func removeEvent(id: String) {
        guard let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent)
    }
}

enum CalendarError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "캘린더 접근 권한이 필요합니다. 설정 > 피우다 > 캘린더를 허용해주세요."
    }
}
