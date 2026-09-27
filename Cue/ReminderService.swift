import EventKit

@MainActor
struct ReminderService {
    func save(_ text: String) async -> Bool {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToReminders(),
                  let list = store.defaultCalendarForNewReminders() else {
                return false
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = text
            reminder.calendar = list
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }
}
