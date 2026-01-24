import Foundation
import AppKit

class SystemService {
    
    func setMusicVolume(ducked: Bool) {
        let targetVol = ducked ? 10 : 85
        let script = """
        try
            tell application "Music" to set sound volume to \(targetVol)
        end try
        try
            tell application "Spotify" to set sound volume to \(targetVol)
        end try
        """
        
        // Run in background to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    func requestPermissions() {
        // Accessibility (Implicitly requested via API usage, but good to have a check)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility Access: \(accessEnabled)")
    }
}
