# Jenkins Release Pipeline

This repository includes Sparkle release pipelines for prod and beta under `jenkins/` and `scripts/release/`, plus a local dev build configuration in Xcode.

## Scope

- `Release` and `Beta` release channels
- `Debug` local/dev builds in Xcode
- Shell-script based pipeline
- Sparkle artifact packaging and appcast publish
- Automatic version bump and git commit/push
- No Slack, App Center, or other notification integrations in this pass

## Pipeline Entry Points

- `jenkins/check-author.sh`
  - Prevents Jenkins from rebuilding its own release bump commit.
- `jenkins/should-build.sh`
  - Skips work when there has not been fresh activity on the tracked branch within the configured lookback window.
- `scripts/release/release.sh`
  - Shared release entrypoint used by both channels.
- `scripts/release/release-prod.sh`
  - Wrapper that runs the shared entrypoint with `AGENTHUB_RELEASE_CHANNEL=release`.
- `scripts/release/release-beta.sh`
  - Wrapper that runs the shared entrypoint with `AGENTHUB_RELEASE_CHANNEL=beta`.

## Release Flow

`release.sh` runs the following steps in order:

1. Read the current channel's version and build from `AgentHub.xcodeproj/project.pbxproj`.
2. Check the current appcast to prevent publishing a duplicate version.
3. Build the app with `xcodebuild`.
4. Re-sign the exported `.app` with Developer ID.
5. Submit the app for notarization and staple the ticket.
6. Package the app for Sparkle and generate `appcast.xml`.
7. Copy publishable artifacts into `build/release/publish/`.
8. Bump the version metadata in `project.pbxproj`.
9. Commit and push the release bump.

## Required Environment Variables

These variables control the pipeline:

| Variable | Purpose | Default |
|----------|---------|---------|
| `AGENTHUB_RELEASE_CHANNEL` | Selects `release` or `beta` defaults | `release` |
| `AGENTHUB_RELEASE_DRY_RUN` | Skip signing, notarization, version-collision enforcement, and git push, while still generating local Sparkle artifacts for validation | `false` |
| `AGENTHUB_RELEASE_BUMP` | Version bump mode: `patch` or `build` | `patch` |
| `AGENTHUB_RELEASE_BUILD_DIR` | Root output directory for release artifacts | `build/<channel>` |
| `AGENTHUB_RELEASE_DERIVED_DATA` | Derived data path used by the release build | `/tmp/agenthub-release-derived` |
| `AGENTHUB_RELEASE_BASE_URL` | Public base URL for hosted Sparkle artifacts | `https://updates.example.com/agenthub` or `/agenthub/beta` based on channel |
| `AGENTHUB_RELEASE_FEED_URL` | Feed URL embedded into the release build | `<base-url>/appcast.xml` |
| `AGENTHUB_RELEASE_APPCAST_SOURCE` | Existing appcast location used for collision checks | `<feed-url>` |
| `AGENTHUB_GIT_REMOTE` | Git remote used for the release bump push | `origin` |
| `AGENTHUB_RELEASE_GIT_BRANCH` | Branch used for the release bump push | current branch |
| `AGENTHUB_RELEASE_SKIP_GIT_PUSH` | Prevent the final push step after the release bump commit | `false` |
| `AGENTHUB_BUILD_AUTHOR_NAME` | Committer name Jenkins uses for release bump commits | `Jenkins Build Server` |
| `AGENTHUB_JENKINS_BRANCH` | Branch inspected by `should-build.sh` | `origin/main` |
| `AGENTHUB_JENKINS_LOOKBACK_HOURS` | Freshness window for `should-build.sh` | `24` |

These variables are required for real release signing and notarization:

| Variable | Purpose |
|----------|---------|
| `AGENTHUB_RELEASE_ENABLE_SIGNING` | Must be `true` for a non-dry-run release |
| `AGENTHUB_RELEASE_SIGNING_IDENTITY` | `Developer ID Application` identity used by `codesign` |
| `AGENTHUB_NOTARY_KEY_ID` | App Store Connect API key id |
| `AGENTHUB_NOTARY_ISSUER_ID` | App Store Connect issuer id |
| `AGENTHUB_NOTARY_KEY_PATH` | Filesystem path to the `.p8` key used by `notarytool` |

These variables control Sparkle appcast signing:

| Variable | Purpose |
|----------|---------|
| `AGENTHUB_SPARKLE_TOOLS_DIR` | Directory containing Sparkle tools such as `generate_appcast` |
| `AGENTHUB_SPARKLE_PRIVATE_KEY_FILE` | Path to the Sparkle private EdDSA key |
| `AGENTHUB_SPARKLE_PRIVATE_KEY_SECRET` | Inline Sparkle private key contents written to a temp file at runtime |

If no Sparkle private key is configured, `publish-sparkle.sh` only writes a placeholder unsigned `appcast.xml` during `AGENTHUB_RELEASE_DRY_RUN=true` local verification. Non-dry-run releases fail fast until a Sparkle signing key is configured.

## Environment Defaults

| Environment | Xcode configuration | Bundle id | App bundle | Default feed | Notes |
|-------------|---------------------|-----------|------------|--------------|-------|
| `dev` | `Debug` | `au.com.roseadvisory.AgentHub.dev` | `AgentHubDev.app` | `http://127.0.0.1:8000/dev/appcast.xml` | Local-only build used from Xcode via the `AgentHub-Dev` scheme |
| `beta` | `Beta` | `au.com.roseadvisory.AgentHub.beta` | `AgentHubBeta.app` | `https://updates.example.com/agenthub/beta/appcast.xml` | Release-candidate build used by the beta release pipeline |
| `release` | `Release` | `au.com.roseadvisory.AgentHub` | `AgentHub.app` | `https://updates.example.com/agenthub/appcast.xml` | Production build used by the release pipeline |

## Shared Xcode Schemes

- `AgentHub-Dev`
  - Builds, runs, tests, profiles, analyzes, and archives using `Debug`
- `AgentHub-Beta`
  - Builds, runs, profiles, analyzes, and archives using `Beta`
  - Runs unit tests using `Debug` so the existing `@testable import AgentHub` suite keeps executing against the debug app module
- `AgentHub-Release`
  - Builds, runs, profiles, analyzes, and archives using `Release`
  - Runs unit tests using `Debug` for the same reason as `AgentHub-Beta`

## Local Verification

Syntax checks:

```bash
bash -n jenkins/*.sh scripts/release/*.sh
```

Dry-run pipeline:

```bash
AGENTHUB_RELEASE_DRY_RUN=true bash scripts/release/release-prod.sh
```

Beta dry run:

```bash
AGENTHUB_RELEASE_DRY_RUN=true bash scripts/release/release-beta.sh
```

This dry run still writes local artifacts under `build/<channel>/publish/`. It does not attempt real signing, notarization, or git push.

Build only:

```bash
bash scripts/release/build-release.sh
```

List shared Xcode schemes:

```bash
xcodebuild -project AgentHub.xcodeproj -list
```

## Jenkins Fast Follow

The repository now has the script boundaries needed for a Jenkins release job, but the actual build-machine provisioning is still a follow-up task. To make non-dry-run releases work on Jenkins, the macOS agent still needs:

- Xcode and command line tools installed
- A `Developer ID Application` certificate and private key imported into a Jenkins-accessible keychain
- App Store Connect API key material for `notarytool`
- Hosting credentials for the Sparkle archive and appcast destination
- Jenkins job configuration that exports the environment variables listed above

Until that machine setup exists, use `AGENTHUB_RELEASE_DRY_RUN=true` for local validation and treat non-dry-run failures in `sign-release.sh` and `notarize-release.sh` as expected.
