import SwiftUI

struct CueItem: Identifiable, Codable {
    let id : UUID
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
        if inputText.isEmpty {
            return
        }

        cues.append(CueItem(text: inputText))
        inputText = ""
        saveCues()
        isInputFocused = true
    }
    func saveCues() {
        if let data = try? JSONEncoder().encode(cues) {
            UserDefaults.standard.set(data, forKey: "cues")
        }
    }
    func loadCues() {
        if let data = UserDefaults.standard.data(forKey: "cues"),
           let savedCues = try? JSONDecoder().decode([CueItem].self, from: data) {
            cues = savedCues
        }
    }
    
    var body: some View {
        VStack {
            Text("Cue")
            TextField("", text: $inputText)
                .focused($isInputFocused)
                .padding()
                .onSubmit {
                    addCue()
                }
            Button("Add") {
                addCue()
            }
            ForEach(cues) { cue in
                HStack{
                    Text(cue.text)
                    Button("×"){
                        cues.removeAll { item in
                            item.id == cue.id
                        }
                        saveCues()
                    }
                }
            }
        }
        .onAppear {
            loadCues()

            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

#Preview {
    ContentView()
}

