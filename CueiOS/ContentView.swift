import SwiftUI

struct ContentView: View {
    @State private var inputText = ""
    @StateObject private var store = CueStore()
    @FocusState private var isInputFocused: Bool
    @FocusState private var isEditFocused: Bool
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?

    @State private var reminderService = ReminderService()
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSendingReminders = false
    @State private var isShowingSettings = false
    @AppStorage("showTimestamps") private var showTimestamps = false
    @AppStorage("background") private var background = CueBackground.system

    var colorScheme: ColorScheme? {
        switch background {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

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

    // Editing starts and ends without any animation.
    func startEditing(_ cue: CueItem) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            editingText = cue.text
            editingID = cue.id
        }
        // A clear click when editing starts.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func saveEdit(_ cue: CueItem) {
        let text = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if !text.isEmpty {
                store.update(cue, text: text)
            }
            editingID = nil
        }
        isInputFocused = true
    }

    func completeCue(_ cue: CueItem) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            deleteCue(cue)
        }
        showToast("Clear")
    }

    func addReminder(for cue: CueItem) {
        reminderService.save(cue.text) { saved in
            if saved {
                deleteCue(cue)
            }
            showToast(saved ? "Added to Reminders" : "Failed")
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

    // Opens the system share sheet (e.g. to Notes). Cues are deleted only when sharing completes.
    func share(_ cues: [CueItem]) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let controller = UIActivityViewController(
            activityItems: [cues.map(\.text).joined(separator: "\n")],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = presenter.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                for cue in cues {
                    store.delete(cue)
                }
                if isSelecting {
                    endSelecting()
                }
            }
            isInputFocused = true
        }
        presenter.present(controller, animated: true)
    }

    func sendSelectedToReminders() {
        if isSendingReminders {
            return
        }
        isSendingReminders = true
        let cues = selectedCues
        reminderService.saveAll(cues.map(\.text)) { saved in
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
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
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
                        if editingID == cue.id {
                            TextField("", text: $editingText)
                                .focused($isEditFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    saveEdit(cue)
                                }
                                .onAppear {
                                    isEditFocused = true
                                }
                        } else {
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(cue.id) ? "checkmark.circle.fill" : "circle")
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cue.text)
                                    if showTimestamps, let createdAt = cue.createdAt {
                                        TimelineView(.everyMinute) { context in
                                            Text(CueItem.timestampText(for: createdAt, now: context.date))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
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
                                .onLongPressGesture {
                                    if !isSelecting {
                                        startEditing(cue)
                                    }
                                }
                        }
                        Spacer()
                        // Done: take the Cue out of the queue.
                        Button("✓") {
                            completeCue(cue)
                        }
                        .buttonStyle(.borderless)
                    }
                        .swipeActions(edge: .trailing) {
                            if !isSelecting || selectedIDs.contains(cue.id) {
                                Button {
                                    share(isSelecting ? selectedCues : [cue])
                                } label: {
                                    Text("共有")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
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
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $isShowingSettings, onDismiss: {
            isInputFocused = true
        }) {
            SettingsView()
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
