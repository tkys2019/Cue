import SwiftUI

struct ContentView: View {
    @State private var inputText = ""
    @StateObject private var store = CueStore()
    @FocusState private var isInputFocused: Bool
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?

    @State private var reminderService = ReminderService()
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSendingReminders = false

    var selectedCues: [CueItem] {
        store.cues.reversed().filter { selectedIDs.contains($0.id) }
    }

    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isInputFocused = true
            return
        }

        store.add(text)
        inputText = ""
        isInputFocused = true
    }

    func deleteCue(_ cue: CueItem) {
        store.delete(cue)
        isInputFocused = true
    }

    func addReminder(for cue: CueItem) {
        reminderService.save(cue.text) {
            deleteCue(cue)
            showToast("Reminded")
        }
    }

    func copiedMessage(for text: String) -> String {
        let shortText = text.count > 14 ? "\(text.prefix(14))…" : text
        return "\(shortText) Copied"
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
        UIPasteboard.general.string = selectedCues.map(\.text).joined(separator: "\n")
        showToast("Copied")
        endSelecting()
    }

    func sendSelectedToReminders() {
        if isSendingReminders {
            return
        }
        isSendingReminders = true
        reminderService.saveAll(selectedCues.map(\.text)) { saved in
            isSendingReminders = false
            if saved {
                showToast("Added to Reminders")
                endSelecting()
            } else {
                showToast("Failed")
            }
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
            .padding(.horizontal)

            TextField("", text: $inputText)
                .focused($isInputFocused)
                .submitLabel(.done)
                .padding()
                .onSubmit {
                    addCue()
                }

            List {
                ForEach(store.cues.reversed()) { cue in
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
                            UIPasteboard.general.string = cue.text
                            showToast(copiedMessage(for: cue.text))
                        }
                        .contextMenu {
                            Button("削除", role: .destructive) {
                                deleteCue(cue)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !isSelecting || selectedIDs.contains(cue.id) {
                                Button {
                                    if isSelecting {
                                        sendSelectedToReminders()
                                    } else {
                                        addReminder(for: cue)
                                    }
                                } label: {
                                    Text("リマインダー")
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .lineLimit(1)
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
