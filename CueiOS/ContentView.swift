import SwiftUI
import WidgetKit

// Same shape and UserDefaults key ("cues") as the Mac app's saved data.
// Stored in the App Group so the lock screen widget can read it.
struct CueItem: Identifiable, Codable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct ContentView: View {
    @State private var inputText = ""
    @State private var cues: [CueItem] = []
    @FocusState private var isInputFocused: Bool

    private let defaults = UserDefaults(suiteName: "group.com.takayashou.cue") ?? .standard

    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isInputFocused = true
            return
        }

        var saved = loadCues()
        saved.append(CueItem(text: text))
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "cues")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
        cues = saved
        inputText = ""
        isInputFocused = true
    }

    func deleteCue(_ cue: CueItem) {
        var saved = loadCues()
        saved.removeAll { $0.id == cue.id }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "cues")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
        cues = saved
        isInputFocused = true
    }

    // Copies cues saved before the App Group existed. The old data is left in place.
    func migrateFromStandardDefaults() {
        guard defaults.data(forKey: "cues") == nil,
              let oldData = UserDefaults.standard.data(forKey: "cues") else {
            return
        }
        defaults.set(oldData, forKey: "cues")
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
    }

    func loadCues() -> [CueItem] {
        guard let data = defaults.data(forKey: "cues"),
              let cues = try? JSONDecoder().decode([CueItem].self, from: data) else {
            return []
        }
        return cues
    }

    var body: some View {
        VStack {
            TextField("", text: $inputText)
                .focused($isInputFocused)
                .submitLabel(.done)
                .padding()
                .onSubmit {
                    addCue()
                }

            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(cues.reversed()) { cue in
                        Text(cue.text)
                            .contextMenu {
                                Button("削除", role: .destructive) {
                                    deleteCue(cue)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            migrateFromStandardDefaults()
            cues = loadCues()

            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

#Preview {
    ContentView()
}
