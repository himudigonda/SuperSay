import SwiftUI

struct VaultView: View {
    @EnvironmentObject var persistence: PersistenceService
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @State private var searchText = ""
    @State private var showOnlyFavorites = false
    
    // Group entries by day
    private var groupedEntries: [(Date, [HistoryEntry])] {
        let sorted = persistence.history.filter { entry in
            let matchesSearch = searchText.isEmpty || entry.text.localizedCaseInsensitiveContains(searchText)
            let matchesFavorite = !showOnlyFavorites || entry.isFavorite
            return matchesSearch && matchesFavorite
        }
        
        let groups = Dictionary(grouping: sorted) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }
        return groups.sorted { $0.key > $1.key }
    }
    
    var body: some View {
        List {
            ForEach(groupedEntries, id: \.0) { date, entries in
                Section(header: Text(date, style: .date)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
                ) {
                    ForEach(entries) { entry in
                        VaultEntryRow(entry: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    persistence.delete(entry: entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    persistence.toggleFavorite(entry: entry)
                                } label: {
                                    Label(entry.isFavorite ? "Unstar" : "Star", systemImage: entry.isFavorite ? "star.slash" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .navigationTitle("Vault")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search spoken text...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 15) {
                    Button { showOnlyFavorites.toggle() } label: {
                        Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                            .foregroundStyle(showOnlyFavorites ? .yellow : .secondary)
                    }
                    .help("Show starred snippets only")
                    
                    Button(role: .destructive) {
                        persistence.clearHistory()
                    } label: {
                        Label("Clear All", systemImage: "trash.slash")
                    }
                    .help("Clear entire history")
                    .disabled(persistence.history.isEmpty)
                }
            }
        }
    }
}

struct VaultEntryRow: View {
    @EnvironmentObject var persistence: PersistenceService
    @EnvironmentObject var dashboardVM: DashboardViewModel
    let entry: HistoryEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.timestamp, style: .time)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                }
                
                Text(entry.voice)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(entry.text)
                .lineLimit(2)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Re-Speak") { 
                Task { await dashboardVM.speak(text: entry.text) } 
            }
            Button(entry.isFavorite ? "Unstar" : "Star") {
                persistence.toggleFavorite(entry: entry)
            }
            Button("Copy") { 
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string) 
            }
            Divider()
            Button(role: .destructive) {
                persistence.delete(entry: entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
