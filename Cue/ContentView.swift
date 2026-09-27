import SwiftUI

struct ContentView: View {
    @State private var inputText = ""
    @StateObject private var store = CueStore()
    private let reminderService = ReminderService()
    @FocusState private var isInputFocused: Bool
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?
    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return
        }

        store.add(text)
        inputText = ""
        isInputFocused = true
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
        let saved = await reminderService.save(text)
        showToast(saved ? "Added to Reminders" : "Failed")
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
                    ForEach(store.cues.reversed()) { cue in
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
                                store.delete(cue)
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
            store.load()

            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

#Preview {
    ContentView()
}

