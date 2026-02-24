import Combine
import Foundation
import PDFKit

struct BookPage: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
}

@MainActor
class PDFService: ObservableObject {
    @Published var pages: [BookPage] = []
    @Published var title: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    func load(url: URL) {
        isLoading = true
        errorMessage = nil
        pages = [] // Clear previous
        title = url.deletingPathExtension().lastPathComponent

        Task {
            // 1. Security / Access Handling
            // Even with Sandbox off, it's safer to read data immediately or copy it
            // if it came from a drop operation.
            let safeURL: URL
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                // Create a copy in temp to ensure we have persistent access during parsing
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("SuperSay_Import_\(UUID().uuidString).pdf")
                try? FileManager.default.copyItem(at: url, to: tempURL)
                safeURL = tempURL
            } else {
                safeURL = url
            }

            // 2. Heavy lifting off main thread
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[BookPage], Error> in
                guard let doc = PDFDocument(url: safeURL) else {
                    return .failure(NSError(domain: "PDFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF document."]))
                }

                if doc.isLocked {
                    return .failure(NSError(domain: "PDFService", code: 2, userInfo: [NSLocalizedDescriptionKey: "PDF is password protected."]))
                }

                let pageCount = doc.pageCount
                var rawPages: [String] = []

                // PASS 1: Extract raw text and build a frequency map of lines to detect headers/footers
                var lineFrequency: [String: Int] = [:]
                for i in 0 ..< pageCount {
                    if let pageText = doc.page(at: i)?.string {
                        rawPages.append(pageText)
                        let lines = pageText.components(separatedBy: .newlines)
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.count > 5 { // Ignore very short lines like page numbers for now
                                lineFrequency[trimmed, default: 0] += 1
                            }
                        }
                    } else {
                        rawPages.append("")
                    }
                }

                // Identify lines that appear on more than 30% of pages (likely headers/footers)
                let commonArtifacts = lineFrequency.filter { $0.value > max(1, Int(Double(pageCount) * 0.3)) }.keys

                // PASS 2: Clean and extract
                var extracted: [BookPage] = []
                for (i, rawText) in rawPages.enumerated() {
                    if rawText.isEmpty { continue }

                    // A. Remove detected common artifacts (headers/footers)
                    var workingText = rawText
                    for artifact in commonArtifacts {
                        workingText = workingText.replacingOccurrences(of: artifact, with: "")
                    }

                    // B. Deep Academic Cleaning
                    let cleanedText = TextProcessor.sanitize(workingText, options: .init(
                        cleanURLs: true,
                        cleanHandles: true,
                        fixLigatures: true,
                        expandAbbr: true,
                        academicClean: true
                    ))

                    if !cleanedText.isEmpty {
                        extracted.append(BookPage(index: i + 1, text: cleanedText))
                    }
                }

                if extracted.isEmpty {
                    return .failure(NSError(domain: "PDFService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No readable text found in PDF. It might be an image scan."]))
                }

                return .success(extracted)
            }.value

            // 3. Update UI on Main Actor
            self.isLoading = false
            switch result {
            case let .success(extractedPages):
                self.pages = extractedPages
            case let .failure(error):
                self.errorMessage = error.localizedDescription
                self.title = "Error Loading PDF"
            }
        }
    }
}
