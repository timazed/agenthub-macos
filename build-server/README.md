# AgentHub Build Server Scaffold

This package is the first scaffold for the future Codex-triggered AgentHub release flow.

## Current Scope

- Accept a logical release request containing the current AgentHub version, current build number, release channel, and force flag.
- Resolve the latest stable Codex release internally rather than requiring caller-supplied artifact metadata.
- Plan the next AgentHub version/build number.
- Plan the Sparkle archive, appcast, and release notes output paths.
- Return a queued release response with the steps the future pipeline will execute.

## Not Yet Implemented

- Querying GitHub Releases and filtering out `-alpha` releases
- Real HTTP server or webhook receiver
- Codex artifact download and checksum verification
- Replacing the bundled `AgentHub/Resources/codex/codex` binary
- Xcode archive, signing, notarization, and upload
- Running Sparkle's `generate_appcast`

## v1 Assumptions

- Release builds will resolve the latest stable Codex release automatically.
- The checked-in `AgentHub/Resources/codex/codex` binary remains in the repo as a local development fallback until the pipeline is proven out.

## Local Smoke Test

```bash
swift run --package-path build-server --disable-sandbox agenthub-build-server --help
swift test --package-path build-server --disable-sandbox
```
