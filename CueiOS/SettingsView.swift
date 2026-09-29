import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showTimestamps") private var showTimestamps = false
    @AppStorage("background") private var background = CueBackground.system
    @AppStorage("lockPortraitOrientation") private var lockPortraitOrientation = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func updateOrientation(locked: Bool) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if locked {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Show timestamps", isOn: $showTimestamps)
                    Picker("Background", selection: $background) {
                        ForEach(CueBackground.allCases, id: \.self) { background in
                            Text(background.title).tag(background)
                        }
                    }
                    Toggle("Lock portrait orientation", isOn: $lockPortraitOrientation)
                        .onChange(of: lockPortraitOrientation) { _, locked in
                            updateOrientation(locked: locked)
                        }
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Link("GitHub", destination: URL(string: "https://github.com/tkys2019/Cue")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
