@testable import SuperSay
import CryptoKit
import Foundation
import XCTest

@MainActor
final class VoqoraInstallerServiceTests: XCTestCase {
    func testParsesOneDigestBackedVoqoraDMG() throws {
        let hash = String(repeating: "a", count: 64)
        let payload = """
        {"tag_name":"v1.0.4","assets":[{"name":"Voqora-1.0.4.dmg","browser_download_url":"https://github.com/himudigonda/Voqora/releases/download/v1.0.4/Voqora-1.0.4.dmg","size":3,"digest":"sha256:\(hash)"}]}
        """.data(using: .utf8)!
        let artifact = try VoqoraInstallerService.artifact(from: payload)
        XCTAssertEqual(artifact.version, "1.0.4")
        XCTAssertEqual(artifact.sha256, hash)
    }

    func testRejectsUnverifiableReleaseAndBadDownloadedFile() throws {
        let payload = """
        {"tag_name":"v1.0.4","assets":[{"name":"Voqora.dmg","browser_download_url":"https://github.com/himudigonda/Voqora/releases/download/v1.0.4/Voqora.dmg","size":1}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VoqoraInstallerService.artifact(from: payload))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("voqora".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let wrong = VoqoraInstallerService.ReleaseArtifact(version: "1.0.4", name: "Voqora.dmg", downloadURL: VoqoraInstallerService.releasePageURL, byteCount: 7, sha256: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try VoqoraInstallerService.verify(file, matches: wrong))
    }
}
