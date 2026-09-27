import SwiftUI

// Same shape and UserDefaults key ("cues") as the Mac app's saved data.
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
    @FocusState private var isInputFocused: Bool

    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isInputFocused = true
            return
        }

        var cues = loadCues()
        cues.append(CueItem(text: text))
        if let data = try? JSONEncoder().encode(cues) {
            UserDefaults.standard.set(data, forKey: "cues")
        }
        inputText = ""
        isInputFocused = true
    }

    func loadCues() -> [CueItem] {
        guard let data = UserDefaults.standard.data(forKey: "cues"),
              let cues = try? JSONDecoder().decode([CueItem].self, from: data) else {
            return []
        }
        return cues
    }

    var body: some View {
        TextField("", text: $inputText)
            .focused($isInputFocused)
            .submitLabel(.done)
            .padding()
            .onSubmit {
                addCue()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                DispatchQueue.main.async {
                    isInputFocused = true
                }
            }
    }
}

#Preview {
    ContentView()
}
