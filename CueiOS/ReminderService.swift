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

    // Saves all reminders in one commit. On any failure, uncommitted reminders are discarded.
    func saveAll(_ texts: [String], completion: @escaping @MainActor (Bool) -> Void) {
        eventStore.requestFullAccessToReminders { [self] granted, _ in
            DispatchQueue.main.async { [self] in
                guard granted, let list = eventStore.defaultCalendarForNewReminders() else {
                    completion(false)
                    return
                }
                do {
                    for text in texts {
                        let reminder = EKReminder(eventStore: eventStore)
                        reminder.title = text
                        reminder.calendar = list
                        try eventStore.save(reminder, commit: false)
                    }
                    try eventStore.commit()
                    completion(true)
                } catch {
                    eventStore.reset()
                    completion(false)
                }
            }
        }
    }
}
