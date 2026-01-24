import Foundation
import PDFKit
import Combine

struct BookPage: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
}

@MainActor
class PDFService: ObservableObject {
    @Published var pages: [BookPage] = []
    @Published var title: String = ""
    
    func load(url: URL) {
        self.title = url.deletingPathExtension().lastPathComponent
        
        Task {
            let extractedPages = await Task.detached(priority: .userInitiated) {
                guard let doc = PDFDocument(url: url) else { return [BookPage]() }
                var result: [BookPage] = []
                
                for i in 0..<doc.pageCount {
                    if let text = doc.page(at: i)?.string {
                        result.append(BookPage(index: i + 1, text: text))
                    }
                }
                return result
            }.value
            
            self.pages = extractedPages
        }
    }
}
