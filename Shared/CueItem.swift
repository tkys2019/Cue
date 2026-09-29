import Foundation

// Shared persisted format. Keep these fields and synthesized Codable compatible
// with existing macOS, iOS and Widget data (UserDefaults key "cues").
// createdAt is optional: Cues saved before it existed have no date.
struct CueItem: Identifiable, Codable {
    let id: UUID
    let text: String
    var createdAt: Date?

    init(id: UUID = UUID(), text: String, createdAt: Date? = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

extension CueItem {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    // e.g. "3分前" within an hour, otherwise "昨日 23:14".
    static func timestampText(for date: Date, now: Date) -> String {
        if abs(now.timeIntervalSince(date)) < 3600 {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        return dateFormatter.string(from: date)
    }
}
