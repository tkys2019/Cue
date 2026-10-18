import SwiftUI
import WatchKit

struct ContentView: View {
    @ObservedObject private var store = WatchCueStore.shared
    @State private var path: [UUID] = []
    @State private var feedback: String?
    @State private var feedbackHideTask: Task<Void, Never>?

    func capture(_ text: String) {
        do {
            guard let cue = try store.capture(text) else { return }
            PhoneConnector.shared.send(cue)
            WKInterfaceDevice.current().play(.success)
            showFeedback("Cue'd")
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFeedback("Not saved")
        }
    }

    // Opens the system text input (Dictation, Scribble, keyboard) without a tap.
    // Without a visible WatchKit controller, ＋ Cue stays one tap away.
    func presentSystemInput() {
        WKApplication.shared().visibleInterfaceController?
            .presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
                guard let text = results?.first as? String else { return }
                DispatchQueue.main.async {
                    capture(text)
                }
            }
    }

    func showFeedback(_ message: String) {
        feedbackHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            feedback = message
        }
        feedbackHideTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                feedback = nil
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    TextFieldLink {
                        Label("Cue", systemImage: "plus")
                    } onSubmit: { text in
                        capture(text)
                    }
                    .id("capture")

                    ForEach(store.cues) { cue in
                        NavigationLink(value: cue.id) {
                            Text(cue.text)
                                .lineLimit(2)
                        }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "cue", url.host == "capture" else { return }
                    path = []
                    proxy.scrollTo("capture", anchor: .top)
                    DispatchQueue.main.async {
                        presentSystemInput()
                    }
                }
            }
            .navigationTitle("Cue")
            .navigationDestination(for: UUID.self) { id in
                ScrollView {
                    Text(store.cues.first { $0.id == id }?.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .overlay {
            if let feedback {
                Text(feedback)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    ContentView()
}
