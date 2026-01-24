import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var pdf: PDFService
    @EnvironmentObject var vm: DashboardViewModel
    @State private var isHovering = false
    
    var body: some View {
        VStack {
            if pdf.pages.isEmpty {
                // Drop Zone
                VStack(spacing: 20) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 60))
                    Text("Drop PDF").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [UTType.pdf], isTargeted: $isHovering) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url { DispatchQueue.main.async { pdf.load(url: url) } }
                    }
                    return true
                }
            } else {
                // List
                HStack {
                    Text(pdf.title).font(.headline)
                    Spacer()
                    Button("Clear") { pdf.pages = [] }
                }.padding()
                
                List(pdf.pages) { page in
                    HStack {
                        Text("Page \(page.index)")
                        Spacer()
                        Button { Task { await vm.speakSelection(text: page.text) } } label: {
                            Image(systemName: "play.circle.fill")
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
