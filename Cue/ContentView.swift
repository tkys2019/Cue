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
    @State private var isShowingCopied = false
    @State private var copiedHideTask: Task<Void, Never>?
    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return
        }

        cues.append(CueItem(text: text))
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
    func showCopiedToast() {
        copiedHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            isShowingCopied = true
        }
        copiedHideTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                isShowingCopied = false
            }
        }
    }

    var body: some View {
        VStack {
            TextField("", text: $inputText)
                .focused($isInputFocused)
                .padding()
                .onSubmit {
                    addCue()
                }
            
            ForEach(cues) { cue in
                HStack{
                    Text(cue.text)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setString(cue.text, forType: .string) {
                                showCopiedToast()
                            }
                        }
                    Button("×"){
                        cues.removeAll { item in
                            item.id == cue.id
                        }
                        saveCues()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if isShowingCopied {
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
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

