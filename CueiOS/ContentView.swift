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
    @State private var cues: [CueItem] = []
    @FocusState private var isInputFocused: Bool

    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isInputFocused = true
            return
        }

        var saved = loadCues()
        saved.append(CueItem(text: text))
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "cues")
        }
        cues = saved
        inputText = ""
        isInputFocused = true
    }

    func deleteCue(_ cue: CueItem) {
        var saved = loadCues()
        saved.removeAll { $0.id == cue.id }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "cues")
        }
        cues = saved
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
