import SwiftUI

struct ContentView: View {
    @ObservedObject var keyRouter: CueKeyRouter
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
    @AppStorage("hoverStyle") private var hoverStyle: CueHoverStyle = .glow
    // "" = default color. Otherwise "#RRGGBB" picked in the system color panel.
    @AppStorage("hoverColor") private var hoverColorHex = ""
    @State private var hoveredID: UUID?
    @State private var hoveredDeleteID: UUID?
    @State private var cursorID: UUID?
    @State private var sendingCueIDs: Set<UUID> = []

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
        AccessibilityNotification.Announcement(message).post()
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
        guard !sendingCueIDs.contains(cue.id), !isSendingReminders else { return }
        sendingCueIDs.insert(cue.id)
        defer { sendingCueIDs.remove(cue.id) }
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
        if keyRouter.context == .selecting { keyRouter.context = .list }
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
        if isSendingReminders || !sendingCueIDs.isEmpty {
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

    private func copyCue(_ cue: CueItem) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(cue.text, forType: .string) { showToast("Copied") }
    }

    private func returnToInput() {
        keyRouter.context = .input
        cursorID = nil
        isInputFocused = true
    }

    private func enterList() {
        guard let first = store.cues.last else { return }
        isInputFocused = false
        keyRouter.resignInput?()
        cursorID = first.id
        keyRouter.context = isSelecting ? .selecting : .list
    }

    private func moveCursor(_ offset: Int) {
        let ids = store.cues.reversed().map(\.id)
        guard !ids.isEmpty else { returnToInput(); return }
        let index = cursorID.flatMap { ids.firstIndex(of: $0) } ?? 0
        if offset < 0, index == 0, !isSelecting { returnToInput(); return }
        cursorID = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func perform(_ action: CueKeyAction) {
        let cue = store.cues.first { $0.id == cursorID }
        switch action {
        case .save: addCue()
        case .toList: enterList()
        case .up: moveCursor(-1)
        case .down: moveCursor(1)
        case .back: returnToInput()
        case .copy: if let cue { copyCue(cue) }
        case .toggleSelect:
            if let cue { isSelecting = true; keyRouter.context = .selecting; toggleSelection(cue) }
        case .selectAll:
            isSelecting = true
            keyRouter.context = .selecting
            selectedIDs = Set(store.cues.map(\.id))
        case .copySelected: if !selectedCues.isEmpty { copySelected() }
        case .reminders:
            Task {
                if isSelecting {
                    if !selectedCues.isEmpty { await sendSelectedToReminders() }
                } else if let cue { await sendToReminders(cue) }
            }
        case .delete: if let cue { store.delete(cue) }
        case .endSelect: endSelecting()
        case .openShortcuts: isInputFocused = false; keyRouter.openEditor()
        case .toggle: break
        }
    }

    private func reconcileCursor(old: [UUID], new: [UUID]) {
        selectedIDs.formIntersection(new)
        guard keyRouter.context != .input else { return }
        guard !new.isEmpty else { returnToInput(); return }
        if let cursorID, new.contains(cursorID) { return }
        let index = cursorID.flatMap { old.firstIndex(of: $0) } ?? 0
        cursorID = new[min(index, new.count - 1)]
    }

    // Item hover color: the picked color, or the defaults (accent glow, neutral highlight).
    var hoverTint: Color {
        if let custom = HoverColorPanel.color(from: hoverColorHex) {
            return Color(nsColor: custom)
        }
        return hoverStyle == .glow ? .accentColor : .primary
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
                Picker("Hover", selection: $hoverStyle) {
                    ForEach(CueHoverStyle.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Button("Hover Color…") {
                    HoverColorPanel.shared.show()
                }
                Button("Reset Hover Color") {
                    hoverColorHex = ""
                }
                .disabled(hoverColorHex.isEmpty)
            }
            Section("Quick Launch") {
                Button("Keyboard Shortcuts…  \(keyRouter.display(.openShortcuts))") {
                    isInputFocused = false
                    keyRouter.openEditor()
                }
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
        .accessibilityLabel("Settings")
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
                    if keyRouter.context == .selecting, !keyRouter.editorIsOpen {
                        Text(keyRouter.display(.copySelected))
                            .font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                }
                settingsMenu
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)

            TextField("", text: $inputText)
                .focused($isInputFocused)
                .focusEffectDisabled()
                .disabled(keyRouter.editorIsOpen)
                .padding()

            if keyRouter.editorIsOpen {
                CueShortcutsEditor(router: keyRouter)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            ForEach(store.cues.reversed()) { cue in
                                cueRow(cue).id(cue.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: cursorID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
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
        .onReceive(keyRouter.commands) { perform($0) }
        .onReceive(keyRouter.panelShown) {
            endSelecting()
            returnToInput()
            DispatchQueue.main.async { isInputFocused = true }
        }
        .onChange(of: isSelecting) { _, selecting in
            if keyRouter.context != .input { keyRouter.context = selecting ? .selecting : .list }
        }
        .onChange(of: isInputFocused) { _, focused in
            if focused { keyRouter.context = .input; cursorID = nil }
        }
        .onChange(of: keyRouter.editorIsOpen) { _, open in
            if !open, keyRouter.context == .input { isInputFocused = true }
        }
        .onChange(of: store.cues.reversed().map(\.id)) { old, new in
            reconcileCursor(old: old, new: new)
        }
    }

    private func cueRow(_ cue: CueItem) -> some View {
        HStack {
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
            .cueHover(cue.id, hovered: $hoveredID, style: hoverStyle, color: hoverTint,
                      keyboardActive: keyRouter.context != .input && cursorID == cue.id)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting { toggleSelection(cue); return }
                copyCue(cue)
            }
            .contextMenu {
                if !isSelecting || selectedIDs.contains(cue.id) {
                    Button("Send to Reminders") {
                        Task {
                            if isSelecting { await sendSelectedToReminders() }
                            else { await sendToReminders(cue) }
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selectedIDs.contains(cue.id) ? .isSelected : [])
            .accessibilityAction { copyCue(cue) }
            .accessibilityAction(named: "Send to Reminders") {
                Task {
                    if isSelecting {
                        if selectedIDs.contains(cue.id) { await sendSelectedToReminders() }
                    } else { await sendToReminders(cue) }
                }
            }
            .accessibilityAction(named: "Delete") { store.delete(cue) }
            if keyRouter.context != .input, cursorID == cue.id {
                let actions: [CueKeyAction] = isSelecting ? [.toggleSelect, .reminders] : [.copy, .reminders, .delete]
                Text(actions.map { keyRouter.display($0) }.filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            Button("×") { store.delete(cue) }
                .cueHover(cue.id, hovered: $hoveredDeleteID, style: hoverStyle, color: .red)
                .accessibilityLabel("Delete")
        }
    }
}

// One hover look for every Cue control, following the Hover setting.
private struct CueHoverEffect: ViewModifier {
    let isActive: Bool
    let style: CueHoverStyle
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive && style == .glow ? color.opacity(0.7) : .clear, radius: 4)
            .shadow(color: isActive && style == .glow ? color.opacity(0.4) : .clear, radius: 8)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive && style == .highlight ? color.opacity(0.1) : .clear)
                    .padding(-4)
            }
            .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}

private extension View {
    func cueHover(_ id: UUID, hovered: Binding<UUID?>, style: CueHoverStyle, color: Color, keyboardActive: Bool = false) -> some View {
        modifier(CueHoverEffect(isActive: hovered.wrappedValue == id || keyboardActive, style: style, color: color))
            .onHover { isHovering in
                if isHovering {
                    hovered.wrappedValue = id
                } else if hovered.wrappedValue == id {
                    hovered.wrappedValue = nil
                }
            }
    }
}

// Picks the hover color with the standard macOS color panel and stores it as "#RRGGBB".
final class HoverColorPanel: NSObject {
    static let shared = HoverColorPanel()
    private static let key = "hoverColor"

    static func color(from hex: String) -> NSColor? {
        guard hex.count == 7, hex.hasPrefix("#"),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func show() {
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = false
        colorPanel.isContinuous = true
        colorPanel.color = Self.color(from: UserDefaults.standard.string(forKey: Self.key) ?? "")
            ?? .controlAccentColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        // The Cue panel sits at screen saver level; keep the color panel in front of it.
        colorPanel.level = .screenSaver
        NSApp.activate()
        colorPanel.orderFrontRegardless()
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
        UserDefaults.standard.set(hex, forKey: Self.key)
    }
}

#Preview {
    ContentView(keyRouter: CueKeyRouter())
}

