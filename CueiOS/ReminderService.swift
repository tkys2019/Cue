import EventKit

@MainActor
final class ReminderService {
    private let eventStore = EKEventStore()

    // Denial and save failures remain silent. Only a committed save calls back.
    func save(_ text: String, onSaved: @escaping @MainActor () -> Void) {
        eventStore.requestFullAccessToReminders { [self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { [self] in
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = text
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                do {
                    try eventStore.save(reminder, commit: true)
                    onSaved()
                } catch {
                }
            }
        }
    }
}
