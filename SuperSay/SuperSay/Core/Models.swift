import Foundation

enum AppStatus: Equatable {
    case ready
    case grabbing
    case thinking
    case speaking
    case paused
    case error(String)
    
    var message: String {
        switch self {
        case .ready: return "Ready"
        case .grabbing: return "Reading Screen..."
        case .thinking: return "AI is Processing..."
        case .speaking: return "Speaking"
        case .paused: return "Paused"
        case .error(let m): return m
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let voice: String
    var isFavorite: Bool
    
    init(text: String, voice: String, isFavorite: Bool = false) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.voice = voice
        self.isFavorite = isFavorite
    }
}
