import Foundation

// Compile separately with each platform's CueStore. No production defaults used.
@main
struct CueStoreRegression {
    @MainActor
    static func main() throws {
        let name = "CueRegression.\(UUID())"
        let legacyName = "\(name).legacy"
        let defaults = UserDefaults(suiteName: name)!
        let legacy = UserDefaults(suiteName: legacyName)!
        defer {
            defaults.removePersistentDomain(forName: name)
            legacy.removePersistentDomain(forName: legacyName)
        }
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let fixture = Data("[{\"id\":\"\(id.uuidString)\",\"text\":\"日本語 🌱\"}]".utf8)
        let decoded = try JSONDecoder().decode([CueItem].self, from: fixture)
        precondition(decoded[0].id == id && decoded[0].text == "日本語 🌱")
        let encoded = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [[String: String]]
        precondition(object == [["id": id.uuidString, "text": "日本語 🌱"]])

        #if IOS_STORE
        var reloads = 0
        let store = CueStore(defaults: defaults, legacyDefaults: legacy, reloadWidget: { reloads += 1 })
        store.load()
        precondition(store.cues.isEmpty && reloads == 0)
        legacy.set(fixture, forKey: "cues")
        store.load()
        precondition(defaults.data(forKey: "cues") == fixture)
        precondition(legacy.data(forKey: "cues") == fixture && reloads == 1)
        store.load()
        precondition(reloads == 1)
        #else
        let store = CueStore(defaults: defaults)
        defaults.set(fixture, forKey: "cues")
        store.load()
        #endif
        precondition(store.cues[0].id == id)
        store.add("日本語 🌱")
        precondition(store.cues.count == 2 && store.cues[1].id != id)
        let secondID = store.cues[1].id
        store.delete(decoded[0])
        precondition(store.cues.count == 1 && store.cues[0].id == secondID)
        let persisted = try JSONDecoder().decode([CueItem].self, from: defaults.data(forKey: "cues")!)
        precondition(persisted[0].id == secondID)
        #if IOS_STORE
        precondition(reloads == 3)
        // External persisted changes must survive the next iOS mutation.
        defaults.set(fixture, forKey: "cues")
        store.add("after external write")
        precondition(store.cues.count == 2 && store.cues[0].id == id)
        defaults.set(fixture, forKey: "cues")
        store.delete(CueItem(id: secondID, text: "stale"))
        precondition(store.cues.count == 1 && store.cues[0].id == id)
        // Existing empty or malformed destination must never trigger migration.
        let beforeLoad = reloads
        for data in [Data("[]".utf8), Data("invalid".utf8)] {
            defaults.set(data, forKey: "cues")
            store.load()
            precondition(store.cues.isEmpty && defaults.data(forKey: "cues") == data)
            precondition(reloads == beforeLoad)
        }
        precondition(legacy.data(forKey: "cues") == fixture)
        #else
        // macOS mutations use in-memory state; failed loads keep that state.
        defaults.set(fixture, forKey: "cues")
        store.add("in memory")
        precondition(store.cues[0].id == secondID)
        defaults.set(Data("invalid".utf8), forKey: "cues")
        store.load()
        precondition(store.cues.count == 2 && store.cues[0].id == secondID)
        #endif
        print("CueStore regression checks passed")
    }
}
