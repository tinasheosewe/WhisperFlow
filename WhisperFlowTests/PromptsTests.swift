@testable import WhisperFlow
import XCTest

final class PromptsTests: XCTestCase {

    func testVersionIsSet() {
        XCTAssertFalse(Prompts.version.isEmpty)
    }

    func testFormatGateUserSubstitutesContext() {
        let result = Prompts.formatGateUser(context: "Hello world test")
        XCTAssertTrue(result.contains("Hello world test"))
        XCTAssertFalse(result.contains("{context}"))
    }

    func testFormatAngleUserSubstitutesContext() {
        let result = Prompts.formatAngleUser(context: "Some conversation")
        XCTAssertTrue(result.contains("Some conversation"))
        XCTAssertFalse(result.contains("{context}"))
    }

    func testGatePromptContainsDecisionGuidance() {
        let system = Prompts.emissionGateSystem
        XCTAssertTrue(system.contains("YES"))
        XCTAssertTrue(system.contains("NO"))
    }

    func testAnglePromptRequiresJSON() {
        let user = Prompts.angleGeneratorUser
        XCTAssertTrue(user.contains("JSON"))
        XCTAssertTrue(user.contains("topic"))
        XCTAssertTrue(user.contains("angles"))
    }

    func testAngleSystemPromptHasToneGuardrail() {
        let system = Prompts.angleGeneratorSystem
        XCTAssertTrue(system.lowercased().contains("tone"))
    }

    func testAngleSystemPromptBansVagueWords() {
        let system = Prompts.angleGeneratorSystem
        XCTAssertTrue(system.contains("challenges"))
        XCTAssertTrue(system.contains("experiences"))
        XCTAssertTrue(system.contains("journey"))
    }
}
