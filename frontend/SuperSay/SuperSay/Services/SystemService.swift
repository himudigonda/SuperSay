import Foundation
import AppKit

class SystemService {
    
    func setMusicVolume(ducked: Bool) {
        let targetVol = ducked ? 10 : 85
        let script = """
        set targetVol to \(targetVol)
        
        -- Check for Music
        tell application "System Events" to set musicRunning to exists (processes where name is "Music")
        if musicRunning then
            run script "tell application \\"Music\\" to set sound volume to " & targetVol
        end if
        
        -- Check for Spotify
        tell application "System Events" to set spotifyRunning to exists (processes where name is "Spotify")
        if spotifyRunning then
            run script "tell application \\"Spotify\\" to set sound volume to " & targetVol
        end if
        """
        
        // Run in background to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            if let scriptObject = NSAppleScript(source: script) {
                var error: NSDictionary?
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
