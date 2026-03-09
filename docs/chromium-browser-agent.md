# Chromium Browser Agent

## Current State

The embedded Chromium browser now supports two layers:

- Deterministic controllers for OpenTable search and venue-page booking up to the final confirmation boundary.
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
- OpenTable deterministic booking still stops before the final reserve or confirm step.

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

The `run` subcommand executes the manifest through the headless app binary, then harvests the newest artifact per scenario so validation still produces a usable matrix even if the app exits non-zero after persisting artifacts.

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

## Known Remaining Work

The branch is materially more generic, but a few items still require live validation rather than more local refactoring:

- repeated smoke runs across hotel and flight sites
- tuning semantic extraction for more custom calendar and autocomplete variants
- validating final-confirmation boundary detection on unfamiliar checkout flows
- iterating on scenario-specific regressions that the smoke harness exposes
- fixing the remaining headless Chromium teardown bug where the scenario process can exit non-zero after artifacts are already written
