import AppKit

struct SelectionManager {
    static func getSelectedText() -> String? {
        // Only use Accessibility API (non-destructive)
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
        
        return nil
    }
}
