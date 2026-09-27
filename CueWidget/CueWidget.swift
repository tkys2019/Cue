import WidgetKit
import SwiftUI

// Same shape, App Group and UserDefaults key ("cues") as the iPhone app's saved data.
struct CueItem: Identifiable, Codable {
    let id: UUID
    let text: String
}

struct CueEntry: TimelineEntry {
    let date: Date
    let texts: [String]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CueEntry {
        CueEntry(date: .now, texts: ["Cue"])
    }

    func getSnapshot(in context: Context, completion: @escaping (CueEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CueEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .never))
    }

    func loadEntry() -> CueEntry {
        guard let data = UserDefaults(suiteName: "group.com.takayashou.cue")?.data(forKey: "cues"),
              let cues = try? JSONDecoder().decode([CueItem].self, from: data) else {
            return CueEntry(date: .now, texts: [])
        }
        return CueEntry(date: .now, texts: cues.suffix(3).reversed().map(\.text))
    }
}

struct CueWidgetView: View {
    let entry: CueEntry

    var body: some View {
        VStack(alignment: .leading) {
            if entry.texts.isEmpty {
                Text("Cue")
            }
            ForEach(entry.texts.indices, id: \.self) { index in
                Text(entry.texts[index])
                    .lineLimit(1)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

struct CueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CueWidget", provider: Provider()) { entry in
            CueWidgetView(entry: entry)
        }
        .configurationDisplayName("Cue")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct CueWidgetBundle: WidgetBundle {
    var body: some Widget {
        CueWidget()
    }
}
