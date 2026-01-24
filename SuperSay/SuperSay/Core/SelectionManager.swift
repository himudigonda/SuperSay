import AppKit

struct SelectionManager {
    static func getSelectedText() -> String? {
        // 1. Try Accessibility API first (non-destructive)
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success {
            var selectedText: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
            if textResult == .success, let text = selectedText as? String, !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 2. Non-Destructive Clipboard Fallback (preserves user's clipboard)
        return getViaClipboardSafe()
    }
    
    private static func getViaClipboardSafe() -> String? {
        let pb = NSPasteboard.general
        
        // BACKUP: Store current clipboard content
        let previousItems = pb.pasteboardItems?.compactMap { item -> [String: Data]? in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict.isEmpty ? nil : dict
        }
        
        let oldCount = pb.changeCount
        
        // Simulate Cmd+C
        simulateCopyShortcut()
        
        // Wait for changeCount to tick (max 0.5s)
        for _ in 0..<10 {
            if pb.changeCount != oldCount { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Capture the new text
        let capturedText = pb.string(forType: .string)
        
        // RESTORE: Put back the original clipboard content
        if let items = previousItems, !items.isEmpty {
            pb.clearContents()
            for itemDict in items {
                let pbItem = NSPasteboardItem()
                for (typeString, data) in itemDict {
                    pbItem.setData(data, forType: NSPasteboard.PasteboardType(typeString))
                }
                pb.writeObjects([pbItem])
            }
        }
        
        return capturedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func simulateCopyShortcut() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cgAnnotatedSessionEventTap)
        cUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
