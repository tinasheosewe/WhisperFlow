import Foundation

struct Tier1Trigger: Sendable {
    let minPause: TimeInterval = 0.5
    let minUserSilent: TimeInterval = 0.8
    let cooldown: TimeInterval = 3.0
    let minNewWords: Int = 4

    private(set) var lastFireTime: TimeInterval = -.infinity
    private(set) var wordCountAtLastFire: Int = 0

    mutating func shouldFire(now: TimeInterval, lastWordTime: TimeInterval?, wordCount: Int) -> Bool {
        guard let lwt = lastWordTime else { return false }

        let pauseLength = now - lwt
        guard pauseLength >= minPause else { return false }
        guard pauseLength >= minUserSilent else { return false }
        guard (now - lastFireTime) >= cooldown else { return false }

        let newWords = wordCount - wordCountAtLastFire
        guard newWords >= minNewWords else { return false }

        return true
    }

    mutating func markFired(at time: TimeInterval, wordCount: Int) {
        lastFireTime = time
        wordCountAtLastFire = wordCount
    }
}
