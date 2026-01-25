import AppKit

struct SelectionManager {
    static func getSelectedText() -> String? {
        // 1. Try Accessibility API first (Cleanest method)
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success {
            var selectedText: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
            
            if textResult == .success, let text = selectedText as? String, !text.isEmpty {
                print("✅ SelectionManager: Found text via AX (\(text.count) chars)")
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("⚠️ SelectionManager: AX failed (Error: \(textResult.rawValue)). Attempting Clipboard Fallback...")
            }
        }
        
        // 2. Fallback: Clipboard Simulation (Cmd+C)
        return getSelectedTextViaClipboard()
    }
    
    private static func getSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        
        // Simulate Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // kVK_Command
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)   // kVK_ANSI_C
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Wait briefly for clipboard to update (50ms)
        Thread.sleep(forTimeInterval: 0.05)
        
        if pasteboard.changeCount != oldChangeCount, let text = pasteboard.string(forType: .string), !text.isEmpty {
            print("✅ SelectionManager: Found text via Clipboard Fallback")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}
