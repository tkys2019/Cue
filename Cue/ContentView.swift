import SwiftUI
import EventKit

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
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?
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
    func showToast(_ message: String) {
        toastHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            toastMessage = message
        }
        toastHideTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                toastMessage = nil
            }
        }
    }
    func sendToReminders(_ text: String) async {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToReminders(),
                  let list = store.defaultCalendarForNewReminders() else {
                showToast("Failed")
                return
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = text
            reminder.calendar = list
            try store.save(reminder, commit: true)
            showToast("Added to Reminders")
        } catch {
            showToast("Failed")
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
            
            ScrollView {
                VStack {
                    ForEach(cues.reversed()) { cue in
                        HStack{
                            Text(cue.text)
                                .onTapGesture {
                                    NSPasteboard.general.clearContents()
                                    if NSPasteboard.general.setString(cue.text, forType: .string) {
                                        showToast("Copied")
                                    }
                                }
                                .contextMenu {
                                    Button("Send to Reminders") {
                                        Task {
                                            await sendToReminders(cue.text)
                                        }
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
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
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

