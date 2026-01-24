import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: SuperSayStore
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            if store.pdf.pages.isEmpty {
                // DROP ZONE
                VStack(spacing: 20) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.cyan.gradient)
                    
                    Text("Drop a PDF here to begin")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 20).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10])))
                .padding(40)
                .onDrop(of: [.pdf], isTargeted: $isHovering) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            DispatchQueue.main.async { store.pdf.load(url: url) }
                        }
                    }
                    return true
                }
            } else {
                // BOOK PLAYER
                HStack {
                    Text(store.pdf.title).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Clear Library") { store.pdf.pages = [] }
                        .buttonStyle(.link).foregroundColor(.red)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                List(store.pdf.pages) { page in
                    HStack {
                        Text("Page \(page.index)").font(.system(.body, design: .monospaced)).frame(width: 70, alignment: .leading)
                        Text(page.text).lineLimit(1).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button {
                            Task { await store.speakSelection(text: page.text) }
                        } label: {
                            Image(systemName: "play.circle.fill").font(.title3).foregroundColor(.cyan)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}
