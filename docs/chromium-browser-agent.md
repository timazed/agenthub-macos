# Chromium Browser Agent

## Current State

The embedded Chromium browser now supports two layers:

- A generic Codex-driven browser loop for search/booking tasks across restaurant, hotel, flight, and checkout flows.
- Deterministic OpenTable controllers retained only as prototype/reference tooling inside the Chromium pane.
- A generic Codex-driven browser loop that operates against semantic page inspection rather than raw selectors alone.

## Generic Agent Capabilities

The generic browser loop currently supports:

- `inspect_page`
- `open_url`
- `click_selector`
- `click_text`
- `type_text`
- `select_option`
- `choose_autocomplete_option`
- `choose_grouped_option`
- `pick_date`
- `submit_form`
- `press_key`
- `scroll`
- `wait_for_text`
- `wait_for_selector`
- `wait_for_navigation`
- `wait_for_results`
- `wait_for_dialog`
- `wait_for_settle`
- `capture_snapshot`
- `done`

## Semantic Inspection

`ChromiumInspection` now exposes:

- `pageStage`
- `interactiveElements`
- `forms`
- `resultLists`
- `cards`
- `dialogs`
- `controlGroups`
- `autocompleteSurfaces`
- `datePickers`
- `primaryActions`
- `transactionalBoundaries`
- `semanticTargets`
- OpenTable-specific `booking` metadata

The flattened `semanticTargets` graph exists to support runtime-side target resolution and stale-target recovery without forcing the model to rediscover the page after each DOM mutation.

## Runtime Behavior

The generic loop in `ChatSessionService` now:

- builds browser prompts with semantic inspection context
- resolves commands against semantic targets before execution
- re-targets recoverable stale commands after refreshed inspection
- tracks richer progress snapshots including page stage and semantic targets
- detects repeated no-progress actions and repeated action loops
- captures browser snapshots through the controller
- persists browser-run artifacts under `~/.agenthub/logs/browser-agent-runs/<session-id>/...`
- captures an automatic final snapshot when a browser run stops, fails, or reaches a confirmation boundary

## Transaction Safety

The controller now distinguishes final confirmation boundaries from earlier search/review steps more cleanly.

- Generic approval gating triggers on semantic `final_confirmation` boundaries and strong transactional keywords.
- OpenTable chat intents and smoke scenarios now run through the generic semantic browser loop by default.
- The deterministic OpenTable controller remains available only as a manual prototype/reference path in the Chromium pane.

## Tests

Unit coverage now includes:

- OpenTable booking parameter parsing
- generic browser intent parsing
- browser command response parsing
- semantic retargeting for stale selectors
- approval classification and final-boundary detection

## Live Smoke Harness

The worktree now includes a lightweight live validation harness:

- Scenario manifest: [browser-live-smoke-scenarios.json](/private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json)
- Artifact/report script: [browser_smoke_report.py](/private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py)

Useful commands:

```bash
python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py summary
python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py matrix
python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py scenarios --file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json
python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py run --file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json --selection restaurant-opentable,hotel-booking
python3 /private/tmp/agenthub-macos-mr-70/scripts/browser_smoke_report.py compare --baseline /path/to/old.json --candidate /path/to/new.json
/private/tmp/agenthub-macos-mr-70/DerivedData/AgentHub/Build/Products/Debug/AgentHub.app/Contents/MacOS/AgentHub --run-browser-scenario hotel-booking --scenario-file /private/tmp/agenthub-macos-mr-70/docs/browser-live-smoke-scenarios.json
```

The `run` subcommand executes the manifest through the headless app binary, then harvests the newest artifact per scenario. Headless runs now isolate Chromium profile state per process and exit cleanly after persisting artifacts, so manifest validation can be used directly in automation.

The persisted artifact JSON now contains:

- optional scenario id/title when launched from the scenario runner
- inferred scenario category (`restaurant`, `hotel`, `flight`, `checkout`, or `other`)
- run outcome and final summary
- recent browser history
- full inspection history
- action trace
- snapshot metadata
- flow/approval summaries
- snapshot capture warnings if artifact capture failed

## Current Validation Status

The manifest-backed live smoke matrix is now green for the main generic validation set:

- `restaurant-opentable`: `stopped_at_confirmation_boundary`
- `hotel-booking`: `stopped_at_confirmation_boundary`
- `flight-google-flights`: `stopped_at_confirmation_boundary`
- `checkout-amazon`: `stopped_at_confirmation_boundary`

## Known Follow-Up

The branch is now at the milestone where the generic browser substrate is live-validated across restaurant, hotel, flight, and checkout-style flows. Remaining work is narrower and lower priority:

- repeated live smoke runs to catch site drift and selector/semantic regressions
- tuning semantic extraction for more custom calendar, autocomplete, and modal variants
- replacing the current headless teardown containment path with a fully graceful in-process Chromium/CEF drain if that lifecycle cleanliness becomes important
