import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let playText = Self("playText", default: .init(.period, modifiers: [.command, .shift]))
    static let togglePause = Self("togglePause", default: .init(.slash, modifiers: [.command, .shift]))
    static let stopText = Self("stopText", default: .init(.comma, modifiers: [.command, .shift]))
    static let exportToDesktop = Self("exportToDesktop", default: .init(.m, modifiers: [.command, .shift]))
}
