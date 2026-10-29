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
    @AppStorage("showTimestamps") private var showTimestamps = false
    @AppStorage("transparency") private var transparency = 0.9
    @AppStorage("background") private var background: CueBackground = .system

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

    var settingsMenu: some View {
        Menu {
            Section("Appearance") {
                Toggle("Show timestamps", isOn: $showTimestamps)
                Picker("Background", selection: $background) {
                    ForEach(CueBackground.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Transparency", selection: Binding(
                    get: { Int((transparency * 100).rounded()) },
                    set: { transparency = Double($0) / 100 }
                )) {
                    ForEach(Array(stride(from: 60, through: 100, by: 5)), id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .pickerStyle(.menu)
            }
            Section("Quick Launch") {
                Text("Keyboard Shortcut: ⌘⌘")
            }
            Section("About") {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                Text("Version \(version)")
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/tkys2019/Cue")!)
                }
            }
            Divider()
            Button("Quit Cue") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
                settingsMenu
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
        .background(.thinMaterial.opacity(transparency))
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

