import Foundation
import Combine

@MainActor
class HistoryManager: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    // Using simple file writing/reading as requested
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json")
    
    init() {
        // Ensure directory exists
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load() 
    }
    
    func log(text: String, voice: String) {
        let entry = HistoryEntry(text: text, voice: voice)
        entries.insert(entry, at: 0)
        save()
    }
    
    func delete(entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func toggleFavorite(entry: HistoryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].isFavorite.toggle()
            save()
        }
    }
    
    func clearAll() {
        entries.removeAll()
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url) }
    }
    
    private func load() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            self.entries = decoded
        }
    }
}
