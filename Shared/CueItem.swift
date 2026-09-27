import Foundation

// Shared persisted format. Keep these fields and synthesized Codable compatible
// with existing macOS, iOS and Widget data (UserDefaults key "cues").
struct CueItem: Identifiable, Codable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
