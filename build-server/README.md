# AgentHub Build Server Scaffold

This package is the first scaffold for the future Codex-triggered AgentHub release flow.

## Current Scope

- Accept a logical release request containing the current AgentHub version, current build number, release channel, and force flag.
- Resolve the latest stable Codex release internally rather than requiring caller-supplied artifact metadata.
- Plan the next AgentHub version/build number.
- Plan the Sparkle archive, appcast, and release notes output paths.
- Return a queued release response with the steps the future pipeline will execute.

## Not Yet Implemented

- Real HTTP server or webhook receiver
- Signed/notarized release archive output
- Full release upload/publication pipeline
- Running Sparkle's `generate_appcast`

## v1 Assumptions

- Release builds will resolve the latest stable Codex release automatically.
- The checked-in `AgentHub/Resources/codex/codex` binary remains in the repo as a local development fallback until the pipeline is proven out.
- The pipeline builds an unsigned AgentHub app bundle, injects the fetched universal Codex binary into `Contents/Resources/codex`, and leaves signing/notarization for the next step of the release flow.
- Checksum verification supports either a dedicated checksum asset or GitHub release asset `digest` metadata, which matches the official `openai/codex` release layout.
- Dry runs and release prep also compare the repo-bundled fallback binary against the latest staged arm64, x64, and universal Codex artifacts and report which one, if any, matches by SHA256.

## Required Environment

- `CODEX_GITHUB_OWNER` — GitHub owner/org for the Codex releases
- `CODEX_GITHUB_REPO` — GitHub repository name for the Codex releases
- `CODEX_GITHUB_API_BASE_URL` — optional override for the GitHub API base URL
- `GITHUB_TOKEN` — optional for public repos, but required for private repos or any GitHub release API access that needs authentication

## Local Smoke Test

```bash
swift run --package-path build-server --disable-sandbox agenthub-build-server --help
swift run --package-path build-server --disable-sandbox agenthub-build-server prepare-release --agenthub-version 1.4.2 --build-number 42 --channel stable --dry-run-no-build --json
swift run --package-path build-server --disable-sandbox agenthub-build-server prepare-release --agenthub-version 1.4.2 --build-number 42 --channel stable --json
swift test --package-path build-server --disable-sandbox
```
