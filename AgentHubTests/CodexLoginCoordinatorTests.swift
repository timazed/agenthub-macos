import Foundation
import Testing
@testable import AgentHub

struct CodexLoginCoordinatorTests {
    @Test
    func parseChallengeExtractsVerificationURLCodeAndExpiry() throws {
        let challenge = CodexLoginCoordinator.parseChallenge(from: [
            "Welcome to Codex",
            "1. Open this link in your browser and sign in to your account",
            "   https://auth.openai.com/codex/device",
            "2. Enter this one-time code (expires in 15 minutes)",
            "   I2A8-GJU5Z"
        ])

        #expect(challenge?.verificationURL.absoluteString == "https://auth.openai.com/codex/device")
        #expect(challenge?.userCode == "I2A8-GJU5Z")
        #expect(challenge?.expiresInMinutes == 15)
    }

    @Test
    func parseChallengeIgnoresAnsiSequences() throws {
        let challenge = CodexLoginCoordinator.parseChallenge(from: [
            "\u{001B}[94mhttps://auth.openai.com/codex/device\u{001B}[0m",
            "\u{001B}[94mABCD-EFGH\u{001B}[0m"
        ])

        #expect(challenge?.verificationURL.absoluteString == "https://auth.openai.com/codex/device")
        #expect(challenge?.userCode == "ABCD-EFGH")
    }
}
