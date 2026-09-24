import SwiftUI

struct CueItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ContentView: View {
    @State private var inputText = ""
    @State private var cues: [CueItem] = []
    func addCue() {
        if inputText.isEmpty {
            return
        }

        cues.append(CueItem(text: inputText))
        inputText = ""
    }
    var body: some View {
        Text("Cue")
        TextField("", text: $inputText)
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
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

