import Foundation

struct Tier1Trigger: Sendable {
    struct Config: Sendable, Equatable {
        var minPause: TimeInterval
        var minUserSilent: TimeInterval
        var cooldown: TimeInterval
        var minNewWords: Int

        static let `default` = Config(
            minPause: 0.5,
            minUserSilent: 0.8,
            cooldown: 3.0,
            minNewWords: 4
        )
    }

    let config: Config
    private(set) var lastFireTime: TimeInterval = -.infinity
    private(set) var wordCountAtLastFire: Int = 0

    init(config: Config = .default) {
        self.config = config
    }

    func shouldFire(now: TimeInterval, lastWordTime: TimeInterval?, wordCount: Int) -> Bool {
        guard let lwt = lastWordTime else { return false }

        let pauseLength = now - lwt
        guard pauseLength >= config.minPause else { return false }
        guard pauseLength >= config.minUserSilent else { return false }
        guard (now - lastFireTime) >= config.cooldown else { return false }

        let newWords = wordCount - wordCountAtLastFire
        guard newWords >= config.minNewWords else { return false }

        return true
    }

    mutating func markFired(at time: TimeInterval, wordCount: Int) {
        lastFireTime = time
        wordCountAtLastFire = wordCount
    }

    mutating func reset() {
        lastFireTime = -.infinity
        wordCountAtLastFire = 0
    }
}
