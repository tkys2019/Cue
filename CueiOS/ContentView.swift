import SwiftUI
import WidgetKit

// Same shape and UserDefaults key ("cues") as the Mac app's saved data.
// Stored in the App Group so the lock screen widget can read it.
struct CueItem: Identifiable, Codable {
    let id: UUID
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

    private let defaults = UserDefaults(suiteName: "group.com.takayashou.cue") ?? .standard

    func addCue() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isInputFocused = true
            return
        }

        var saved = loadCues()
        saved.append(CueItem(text: text))
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "cues")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
        cues = saved
        inputText = ""
        isInputFocused = true
    }

    func deleteCue(_ cue: CueItem) {
        var saved = loadCues()
        saved.removeAll { $0.id == cue.id }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "cues")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
        cues = saved
        isInputFocused = true
    }

    // Copies cues saved before the App Group existed. The old data is left in place.
    func migrateFromStandardDefaults() {
        guard defaults.data(forKey: "cues") == nil,
              let oldData = UserDefaults.standard.data(forKey: "cues") else {
            return
        }
        defaults.set(oldData, forKey: "cues")
        WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
    }

    func loadCues() -> [CueItem] {
        guard let data = defaults.data(forKey: "cues"),
              let cues = try? JSONDecoder().decode([CueItem].self, from: data) else {
            return []
        }
        return cues
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

    var body: some View {
        VStack {
            TextField("", text: $inputText)
                .focused($isInputFocused)
                .submitLabel(.done)
                .padding()
                .onSubmit {
                    addCue()
                }

            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(cues.reversed()) { cue in
                        Text(cue.text)
                            .onTapGesture {
                                UIPasteboard.general.string = cue.text
                                showToast(copiedMessage(for: cue.text))
                            }
                            .contextMenu {
                                Button("削除", role: .destructive) {
                                    deleteCue(cue)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
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
            migrateFromStandardDefaults()
            cues = loadCues()

            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

#Preview {
    ContentView()
}
