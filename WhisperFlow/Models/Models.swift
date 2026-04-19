import Foundation

enum Speaker: String, Codable, Sendable {
    case selfSpeaker = "self"
    case other = "other"
    case unknown = "unknown"
}

struct Word: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    var speaker: Speaker

    init(text: String, start: TimeInterval, end: TimeInterval, speaker: Speaker = .unknown) {
        self.id = UUID()
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

struct ContextRing: Sendable {
    let windowSize: TimeInterval = 20.0
    private(set) var words: [Word] = []

    var text: String {
        words.map(\.text).joined(separator: " ")
    }

    var lastWordTime: TimeInterval? {
        words.last?.end
    }

    var wordCount: Int {
        words.count
    }

    mutating func add(_ word: Word) {
        words.append(word)
        trim()
    }

    func lastOtherUtterance() -> TimeInterval? {
        words.last(where: { $0.speaker == .other })?.end
    }

    private mutating func trim() {
        guard let latest = words.last?.end else { return }
        let cutoff = latest - windowSize
        words.removeAll { $0.end < cutoff }
    }

    mutating func clear() {
        words.removeAll()
    }
}

struct Emission: Identifiable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let context: String
    let topic: String
    let angles: [String]

    init(timestamp: TimeInterval, context: String, topic: String, angles: [String]) {
        self.id = UUID()
        self.timestamp = timestamp
        self.context = context
        self.topic = topic
        self.angles = angles
    }
}
