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

## Next Live Validation

If continuing from here, do live smoke runs in this order:

1. Hotel search and property flow on Booking.com or Expedia.
2. Flight search flow on Google Flights or Kayak.
3. Transaction boundary validation on a shopping or checkout-adjacent site.

The code substrate is now much better suited for those tests than the earlier selector-driven loop.

## Known Follow-Up

- Headless scenario runs still persist usable artifacts before shutdown, but the process can exit non-zero because Chromium/CEF browser contexts are not yet fully draining during teardown. The smoke runner now surfaces artifact outcomes even in that case, but the runtime shutdown path still needs a dedicated fix.
