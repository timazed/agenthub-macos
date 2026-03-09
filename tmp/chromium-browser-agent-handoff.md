# Chromium Browser Agent Handoff

## Branch

- Worktree: `/private/tmp/agenthub-macos-mr-70`
- Branch: `codex/mr-70-chromium-prototype`

## What Changed In This Slice

- Added `BrowserAgentModels.swift` for the generic browser command schema.
- Expanded `ChromiumInspection` with `pageStage` and flattened `semanticTargets`.
- Expanded page inspection JS to model forms, lists, cards, dialogs, grouped controls, autocomplete, date pickers, transactional boundaries, and semantic targets.
- Added `BrowserSemanticResolver.swift` to resolve browser actions against semantic targets and retarget stale selectors after inspection refresh.
- Added `BrowserTransactionalGuard.swift` to centralize generic transactional-boundary stopping and approval classification.
- Updated `ChatSessionService` to:
  - route generic browser intents
  - prompt Codex with semantic page context
  - resolve semantic targets before execution
  - retry recoverable stale actions against refreshed semantic targets
  - track richer browser progress snapshots
  - persist browser-agent run artifacts with scenario category, inspection history, action trace, snapshots, and automatic final snapshot capture
- Tightened `ChromiumBrowserController` approval behavior so semantic final-confirmation boundaries gate approval more precisely.
- Added a live-smoke scenario manifest and artifact-report script for cross-site validation.
- Added a manifest runner mode to `browser_smoke_report.py` so scenario manifests can be executed and summarized from one command.
- Hardened generic text entry in `BrowserJavaScript.swift` so controlled inputs use native value setters plus input/change dispatch, which fixed checkout/login flows on modern forms.
- Re-routed OpenTable chat intents and smoke scenarios through the generic semantic browser loop instead of the deterministic OpenTable controller path.
- Updated headless runtime shutdown so scenario execution isolates Chromium profile state per process, terminates helper subprocesses on exit, and leaves headless scenario commands green even though in-process `CefShutdown()` draining remains brittle.
- Added tests for booking parameter parsing, generic intent parsing, browser command parsing, semantic retargeting, and transactional-boundary classification.

## Verification

Verified in the worktree with:

- `xcodebuild -project /private/tmp/agenthub-macos-mr-70/AgentHub.xcodeproj -scheme AgentHub -sdk macosx -derivedDataPath /private/tmp/agenthub-macos-mr-70/DerivedData/AgentHub CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project /private/tmp/agenthub-macos-mr-70/AgentHub.xcodeproj -scheme AgentHub -sdk macosx -derivedDataPath /private/tmp/agenthub-macos-mr-70/DerivedData/AgentHub CODE_SIGNING_ALLOWED=NO test -only-testing:AgentHubTests`

Both are green.

## Live Smoke Harness

- Scenario manifest: `/private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json`
- Report script: `/private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py`
- Artifact root: `~/.agenthub/logs/browser-agent-runs`

Recommended commands:

- `python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py summary`
- `python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py matrix`
- `python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py scenarios --file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json`
- `python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py run --file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json --selection restaurant-opentable,hotel-booking`
- `/private/tmp/agenthub-macos-mr-70/DerivedData/AgentHub/Build/Products/Debug/AgentHub.app/Contents/MacOS/AgentHub --run-browser-scenario <scenario-id|all> --scenario-file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json`

## Live Validation Status

Latest manifest-backed outcomes:

1. `restaurant-opentable`: `stopped_at_confirmation_boundary`
2. `hotel-booking`: `stopped_at_confirmation_boundary`
3. `flight-google-flights`: `stopped_at_confirmation_boundary`
4. `checkout-amazon`: `stopped_at_confirmation_boundary`

The checkout validation now succeeds on a checkout-style ecommerce flow after the generic text-entry fix. Headless scenario commands also exit `0` with persisted artifacts.
OpenTable-specific chat/scenario handling now exercises the same generic semantic loop as the other domains, so failures land in the shared browser substrate instead of a site-specific controller path.

## Known Follow-Up

- If desired, replace the current headless containment shutdown path with a fully graceful in-process Chromium/CEF drain. That is no longer blocking scenario execution or artifact collection.
- Continue periodic live smoke runs against the manifest to catch site drift and regressions in semantic extraction.
