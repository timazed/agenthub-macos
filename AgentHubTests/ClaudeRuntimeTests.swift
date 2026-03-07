import Foundation
import Testing
@testable import AgentHub

struct ClaudeRuntimeTests {
    @Test
    func buildArgumentsUsesSessionIDForNewThreads() {
        let args = ClaudeRuntime.buildArguments(
            prompt: "Hello",
            command: .startNewThread("session-123"),
            config: CodexLaunchConfig(
                agentHomeDirectory: "/tmp/persona",
                codexHome: "/tmp/codex",
                runtimeMode: .chatOnly,
                externalDirectory: nil,
                enableSearch: false,
                model: "gpt-5.4",
                reasoningEffort: .medium
            ),
            personaInstructions: "You are concise."
        )

        #expect(args.contains("--session-id"))
        #expect(args.contains("session-123"))
        #expect(!args.contains("--model"))
    }

    @Test
    func buildArgumentsUsesResumeForExistingThreadsAndClaudeModels() {
        let args = ClaudeRuntime.buildArguments(
            prompt: "Hello again",
            command: .resume("session-456"),
            config: CodexLaunchConfig(
                agentHomeDirectory: "/tmp/persona",
                codexHome: "/tmp/codex",
                runtimeMode: .chatOnly,
                externalDirectory: "/tmp/repo",
                enableSearch: false,
                model: "claude-sonnet-4-6",
                reasoningEffort: .medium
            ),
            personaInstructions: "You are concise."
        )

        #expect(args.contains("--resume"))
        #expect(args.contains("session-456"))
        #expect(args.contains("--model"))
        #expect(args.contains("claude-sonnet-4-6"))
        #expect(args.contains("--add-dir"))
        #expect(args.contains("/tmp/repo"))
    }

    @Test
    func buildEnvironmentRedirectsClaudeHomeIntoAgentHubRoot() {
        let environment = ClaudeRuntime.buildEnvironment(claudeHome: "/tmp/agenthub-home")

        #expect(environment["HOME"] == "/tmp/agenthub-home")
        #expect(environment["XDG_CONFIG_HOME"] == "/tmp/agenthub-home")
    }
}
