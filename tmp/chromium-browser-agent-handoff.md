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
- Added `bookingFunnel` inference to `ChromiumInspection` so the runtime can distinguish search/results/venue/widget/slot-selection/guest-details/review/final states from generic page semantics.
- Updated `BrowserTransactionalGuard` to require late-stage booking progression before auto-stopping on semantic final-confirmation boundaries, which closes the false-stop class for early `Reserve` CTAs on venue/detail pages.
- Tightened the generic browser prompt so booking goals prefer exact venue/detail discovery before changing date/time/party parameters.
- Hardened generic `pick_date` handling so normalized targets like `2026-03-09` match real calendar labels and day cells.
- Ranked result-card actions semantically so the generic runtime prefers venue/detail navigation instead of map/help/share controls embedded in cards.
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

The checkout validation now succeeds on a checkout-style ecommerce flow after the generic text-entry fix.
OpenTable-specific chat/scenario handling now exercises the same generic semantic loop as the other domains, so failures land in the shared browser substrate instead of a site-specific controller path.
The latest real OpenTable booking artifact is:

1. `~/.agenthub/logs/browser-agent-runs/96E9A240-CE69-49C4-A8CF-139F51D41C26/2026-03-09T05:18:35.672Z-stopped_at_confirmation_boundary.json`

That run used the query:

1. `Make a reservation for me on OpenTable. Sake House By Hikari. Culver City. March 9. 7pm. 2 people.`

It reached:

1. `https://www.opentable.com/r/sake-house-by-hikari-culver-city?dateTime=2026-03-09T19%3A00&covers=2`
2. Approval boundary: `Reserve table at Sake House By Hikari at 7:00 PM on March 9, for a party of 2`

## Known Follow-Up

- Refine venue-detail/page-stage inference. The current OpenTable detail-page artifact reaches the correct approval boundary, but `pageStage` / `bookingFunnel.stage` can still stay overly coarse on some detail pages.
- Replace the current headless containment shutdown path with a fully graceful in-process Chromium/CEF drain. Chromium/CEF can still fatal after artifacts are written.
- Continue periodic live smoke runs against the manifest to catch site drift and regressions in semantic extraction.
