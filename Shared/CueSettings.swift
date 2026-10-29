import Foundation

// Values stored in UserDefaults.standard by the Settings screen.
enum CueBackground: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

// macOS only: how a Cue looks while the pointer is over it.
enum CueHoverStyle: String, CaseIterable {
    case glow, highlight

    var title: String {
        switch self {
        case .glow: "Glow"
        case .highlight: "Highlight"
        }
    }
}
