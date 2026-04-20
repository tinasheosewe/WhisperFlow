@testable import WhisperFlow
import Foundation

actor MockLLMService: LLMService {
    private let gateResults: [Bool]
    private let angleResults: [AngleResult]
    private let errorToThrow: (any Error)?

    private(set) var gateCallCount = 0
    private(set) var angleCallCount = 0
    private(set) var gateContexts: [String] = []
    private(set) var angleContexts: [String] = []

    init(
        gateResults: [Bool] = [true],
        angleResults: [AngleResult] = [AngleResult(topic: "test topic", angles: ["angle1", "angle2"])],
        errorToThrow: (any Error)? = nil
    ) {
        self.gateResults = gateResults
        self.angleResults = angleResults
        self.errorToThrow = errorToThrow
    }

    func evaluateGate(context: String) async throws -> Bool {
        if let error = errorToThrow { throw error }
        gateContexts.append(context)
        let result = gateResults[min(gateCallCount, gateResults.count - 1)]
        gateCallCount += 1
        return result
    }

    func generateAngles(context: String) async throws -> AngleResult {
        if let error = errorToThrow { throw error }
        angleContexts.append(context)
        let result = angleResults[min(angleCallCount, angleResults.count - 1)]
        angleCallCount += 1
        return result
    }
}
