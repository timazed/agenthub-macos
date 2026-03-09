# AgentHub Build Server Scaffold

This package is the first scaffold for the future Codex-triggered AgentHub release flow.

## Current Scope

- Accept a logical release request containing a Codex version, artifact URL, checksum, and current AgentHub version.
- Plan the next AgentHub version/build number.
- Plan the Sparkle archive, appcast, and release notes output paths.
- Return a queued release response with the steps the future pipeline will execute.

## Not Yet Implemented

- Real HTTP server or webhook receiver
- Codex artifact download and checksum verification
- Replacing the bundled `AgentHub/Resources/codex/codex` binary
- Xcode archive, signing, notarization, and upload
- Running Sparkle's `generate_appcast`

## Local Smoke Test

```bash
swift run --package-path build-server agenthub-build-server --help
swift test --package-path build-server
```
