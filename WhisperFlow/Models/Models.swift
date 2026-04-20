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
    let windowSize: TimeInterval
    private(set) var words: [Word] = []
    /// Monotonically increasing count of all words ever added (unaffected by window trimming).
    private(set) var totalWordsAdded: Int = 0

    init(windowSize: TimeInterval = 20.0) {
        self.windowSize = windowSize
    }

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
        totalWordsAdded += 1
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
        totalWordsAdded = 0
    }
}

struct Emission: Identifiable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let context: String
    let result: AngleResult

    var topic: String { result.topic }
    var angles: [String] { result.angles }

    init(timestamp: TimeInterval, context: String, result: AngleResult) {
        self.id = UUID()
        self.timestamp = timestamp
        self.context = context
        self.result = result
    }
}
