import EventKit

@MainActor
final class ReminderService {
    private let eventStore = EKEventStore()

    func save(_ text: String, completion: @escaping @MainActor (Bool) -> Void) {
        eventStore.requestFullAccessToReminders { [self] granted, _ in
            DispatchQueue.main.async { [self] in
                guard granted else {
                    completion(false)
                    return
                }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = text
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                do {
                    try eventStore.save(reminder, commit: true)
                    completion(true)
                } catch {
                    completion(false)
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
