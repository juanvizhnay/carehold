import Core
import Foundation
import UserNotifications

/// Local notifications for the patient: one per scheduled time of the plan, plus visit reminders.
/// Privacy: lock-screen text never names a medicine or condition, only "your medicine" or
/// "your exercises", and the visit time.
enum CareReminders {
    private static let prefix = "carehold-"
    /// iOS keeps at most 64 pending requests per app.
    private static let maxScheduled = 60

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asked only when the patient taps "Turn on reminders", never on launch.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(items: [PlanItem], appointments: [Appointment], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        await removeAll()
        guard await status() == .authorized else { return }

        var requests: [UNNotificationRequest] = []
        let today = Format.calendarDate(from: now)

        // Group items sharing a time (and weekday) into one gentle nudge.
        var slots: [String: (time: LocalTime, weekday: Int?, kinds: Set<PlanItem.Kind>)] = [:]
        for item in items where item.isActive(on: today) || item.startDate > today {
            for time in item.times {
                let weekdays: [Int?] = item.weekdays.isEmpty ? [nil] : item.weekdays.sorted().map(Optional.some)
                for weekday in weekdays {
                    let key = "\(time.string)-\(weekday.map(String.init) ?? "all")"
                    slots[key, default: (time, weekday, [])].kinds.insert(item.kind)
                }
            }
        }
        for (key, slot) in slots.sorted(by: { $0.value.time < $1.value.time }) {
            var components = DateComponents(hour: slot.time.hour, minute: slot.time.minute)
            // Calendar weekday: 1 is Sunday. ISO: 7 is Sunday.
            if let weekday = slot.weekday { components.weekday = weekday % 7 + 1 }
            let content = UNMutableNotificationContent()
            content.title = "CareHold"
            content.body = body(for: slot.kinds)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            requests.append(UNNotificationRequest(identifier: prefix + "plan-" + key, content: content, trigger: trigger))
        }

        // Visits: the evening before and one hour before.
        let calendar = Calendar.current
        for visit in appointments where visit.status == .scheduled && visit.startsAt > now {
            let time = Format.time(visit.startsAt)
            if let eve = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: visit.startsAt))
                .flatMap({ calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }), eve > now {
                requests.append(visitRequest(id: visit.id, suffix: "eve", at: eve, body: "Tomorrow you have a visit at \(time)."))
            }
            let hourBefore = visit.startsAt.addingTimeInterval(-3600)
            if hourBefore > now {
                requests.append(visitRequest(id: visit.id, suffix: "hour", at: hourBefore, body: "Your visit starts at \(time)."))
            }
        }

        for request in requests.prefix(maxScheduled) {
            try? await center.add(request)
        }
    }

    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func body(for kinds: Set<PlanItem.Kind>) -> String {
        let hasMedicine = kinds.contains(.medication)
        let hasExercise = kinds.contains(.exercise)
        switch (hasMedicine, hasExercise) {
        case (true, true): return "It's time for your medicine and exercises."
        case (true, false): return "It's time for your medicine."
        case (false, true): return "It's time for your exercises."
        default: return "It's time for your care plan."
        }
    }

    private static func visitRequest(id: UUID, suffix: String, at date: Date, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "CareHold"
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: prefix + "visit-\(id.uuidString)-\(suffix)", content: content, trigger: trigger)
    }
}
