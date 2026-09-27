import SwiftUI

struct ContentView: View {
    @State private var inputText = ""
    @StateObject private var store = CueStore()
    @FocusState private var isInputFocused: Bool
    @State private var toastMessage: String?
    @State private var toastHideTask: Task<Void, Never>?

    @State private var reminderService = ReminderService()

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

    var body: some View {
        VStack {
            TextField("", text: $inputText)
                .focused($isInputFocused)
                .submitLabel(.done)
                .padding()
                .onSubmit {
                    addCue()
                }

            List {
                ForEach(store.cues.reversed()) { cue in
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
                        .swipeActions(edge: .trailing) {
                            Button {
                                addReminder(for: cue)
                            } label: {
                                Text("リマインダー")
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
