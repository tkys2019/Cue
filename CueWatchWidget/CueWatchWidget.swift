import WidgetKit
import SwiftUI

struct CueEntry: TimelineEntry {
    let date: Date
    let texts: [String]
}

// Reloaded by the Watch app when its Cues change; no scheduled refresh.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CueEntry {
        CueEntry(date: .now, texts: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CueEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CueEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .never))
    }

    func loadEntry() -> CueEntry {
        let cues = WatchCueState.read(from: WatchCueState.fileURL).displayCues
        return CueEntry(date: .now, texts: cues.prefix(2).map(\.text))
    }
}

struct CueWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CueEntry

    var body: some View {
        content
            .widgetURL(URL(string: "cue://capture"))
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Cue")
                    .font(.headline)
                    .widgetAccentable()
                if entry.texts.isEmpty {
                    Text("＋ Capture")
                        .foregroundStyle(.secondary)
                }
                ForEach(entry.texts.indices, id: \.self) { index in
                    Text(entry.texts[index])
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text("💡 " + (entry.texts.first ?? "Cue"))
        default:
            // Circular and corner: a capture button only.
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
            }
        }
    }
}

struct CueWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CueWatchWidget", provider: Provider()) { entry in
            CueWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Cue")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

@main
struct CueWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CueWatchWidget()
    }
}
