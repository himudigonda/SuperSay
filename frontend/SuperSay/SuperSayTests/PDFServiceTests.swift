@testable import SuperSay
import XCTest

final class PDFServiceTests: XCTestCase {
    func testPDFService_InitialState() async {
        await MainActor.run {
            let pdf = PDFService()
            XCTAssertTrue(pdf.pages.isEmpty, "Pages should be initially empty")
            XCTAssertEqual(pdf.title, "", "Title should be initially empty")
            XCTAssertFalse(pdf.isLoading, "isLoading should be initially false")
        }
    }

    func testPDFService_LoadTitleUpdate() async {
        await MainActor.run {
            let pdf = PDFService()
            let mockURL = URL(fileURLWithPath: "/path/to/MyBook.pdf")

            pdf.load(url: mockURL)

            XCTAssertEqual(pdf.title, "MyBook")
            XCTAssertTrue(pdf.isLoading)
        }
    }
}
