import SwiftUI

struct ContentView: View {
    @State private var inputText = ""
    @StateObject private var store = CueStore()
    private let reminderService = ReminderService()
    @FocusState private var isInputFocused: Bool
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSendingReminders = false

    var selectedCues: [CueItem] {
        store.cues.reversed().filter { selectedIDs.contains($0.id) }
    }
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
    func sendToReminders(_ cue: CueItem) async {
        let saved = await reminderService.save(cue.text)
        if saved {
            store.delete(cue)
        }
        showToast(saved ? "Added to Reminders" : "Failed")
    }
    func toggleSelection(_ cue: CueItem) {
        if selectedIDs.contains(cue.id) {
            selectedIDs.remove(cue.id)
        } else {
            selectedIDs.insert(cue.id)
        }
    }
    func endSelecting() {
        selectedIDs = []
        isSelecting = false
    }
    func copySelected() {
        let text = selectedCues.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) {
            showToast("Copied")
        }
        endSelecting()
    }
    func sendSelectedToReminders() async {
        if isSendingReminders {
            return
        }
        isSendingReminders = true
        let cues = selectedCues
        let saved = await reminderService.saveAll(cues.map(\.text))
        isSendingReminders = false
        if saved {
            for cue in cues {
                store.delete(cue)
            }
            showToast("Added to Reminders")
            endSelecting()
        } else {
            showToast("Failed")
        }
    }

    var body: some View {
        VStack {
            HStack {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting {
                        endSelecting()
                    } else {
                        isSelecting = true
                    }
                }
                Spacer()
                if isSelecting {
                    Button("Select All") {
                        selectedIDs = Set(store.cues.map(\.id))
                    }
                    Button("Copy") {
                        copySelected()
                    }
                    .disabled(selectedCues.isEmpty)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)

            TextField("", text: $inputText)
                .focused($isInputFocused)
                .focusEffectDisabled()
                .padding()
                .onSubmit {
                    addCue()
                }
            
            ScrollView {
                VStack {
                    ForEach(store.cues.reversed()) { cue in
                        HStack{
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(cue.id) ? "checkmark.circle.fill" : "circle")
                                }
                                Text(cue.text)
                            }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        toggleSelection(cue)
                                        return
                                    }
                                    NSPasteboard.general.clearContents()
                                    if NSPasteboard.general.setString(cue.text, forType: .string) {
                                        showToast("Copied")
                                    }
                                }
                                .contextMenu {
                                    if !isSelecting || selectedIDs.contains(cue.id) {
                                        Button("Send to Reminders") {
                                            Task {
                                                if isSelecting {
                                                    await sendSelectedToReminders()
                                                } else {
                                                    await sendToReminders(cue)
                                                }
                                            }
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
        .background(.thinMaterial)
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

