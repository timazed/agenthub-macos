# Chromium Browser Agent

## Current State

The embedded Chromium browser now supports two layers:

- A generic Codex-driven browser loop for search/booking tasks across restaurant, hotel, flight, and checkout flows.
- Deterministic OpenTable controllers retained only as prototype/reference tooling inside the Chromium pane.
- A generic semantic browser substrate that can infer workflow state, missing requirements, verification blockers, and final-submit readiness from page inspection instead of relying on site-specific booking branches.

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
- `bookingFunnel`
- `notices`
- `stepIndicators`
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
The new `bookingFunnel` model captures reusable late-stage signals such as selected date/time/party, booking-widget presence, slot selection, guest-details forms, review/payment forms, and whether the current page has truly progressed far enough to treat a `reserve/book` CTA as a confirmation boundary.
The generic date-picker action now matches normalized targets such as `2026-03-09` against visible calendar labels and day cells, and result-card action ranking now prefers venue/detail navigation over map/help/share controls.
Inspection also emits normalized field metadata such as `autocomplete`, `inputMode`, `fieldPurpose`, `isRequired`, `isSelected`, and `validationMessage`, which is what the generic requirement engine uses to infer missing profile data, verification codes, consents, payment fields, and validation errors.

## Generic Requirements And Workflow

`BrowserPageAnalyzer` now derives two reusable models from the live page:

- `requirements`: missing phone/email/name/address/payment/OTP/consent/date/time/guest fields
- `workflow`: `discovery`, `selection`, `details_form`, `verification`, `review`, `final_submit`, `success`, `failure`, `dialog`, or `browse`

This is the layer that lets the browser agent ask for exactly the missing data when it cannot proceed autonomously, instead of relying on OpenTable-specific fallbacks.

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
- pauses on missing promptable requirements and asks the user only for the exact missing data
- auto-fills known inline request data or saved persona contact data into semantic form fields before asking again
- keeps follow-up messages attached to the active Chromium session first, so later replies like phone/email/address/OTP/`yes` continue the current page instead of restarting the goal

## Profile And Follow-Up Data

The browser loop now accepts structured data from two generic sources:

- inline user data parsed from the original goal or later follow-up messages
- saved persona contact data loaded from `PersonaManager`

Supported generic fields currently include:

- full name / first name / last name
- phone number
- email
- address line 1 / address line 2
- city / state / postal code / country
- verification code
- consent toggles

This means flows like checkout, inspections, booking forms, or grocery ordering can continue from the current page using the same generic continuation path.

## Verification And OTP

The runtime now has a generic verification-code path:

- verification blockers are inferred from page semantics, notices, and step indicators
- follow-up messages containing OTP digits are applied to the active CEF page
- the browser can prepare the focused verification field for native macOS one-time-code autofill by setting `autocomplete="one-time-code"`, numeric input mode, promoting the embedded Chromium text-input view to first responder, and nudging AppKit’s text-input context to surface completion candidates

This is best-effort native OTP support inside CEF; it does not read Messages directly.

## Transaction Safety

The controller now distinguishes final confirmation boundaries from earlier search/review steps more cleanly.

- Generic approval gating triggers on semantic `final_confirmation` boundaries and strong transactional keywords.
- Auto-stop now also consults `bookingFunnel.stage`, so early venue/detail CTAs like `Reserve for Others` do not stop the agent before it has progressed into guest-details/review/final-confirmation states.
- OpenTable chat intents and smoke scenarios now run through the generic semantic browser loop by default.
- The deterministic OpenTable controller remains available only as a manual prototype/reference path in the Chromium pane.

## Tests

Unit coverage now includes:

- OpenTable booking parameter parsing
- generic browser intent parsing
- browser command response parsing
- semantic retargeting for stale selectors
- approval classification and final-boundary detection
- booking-funnel stage inference and stage-aware final-boundary gating
- generic missing-requirement inference
- generic workflow-state inference
- inline follow-up data parsing for profile fields and consent
- verification-code autofill preparation

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

The `run` subcommand executes the manifest through the headless app binary, then harvests the newest artifact per scenario. Headless runs now isolate Chromium profile state per process and persist usable artifacts reliably, but Chromium/CEF teardown is still brittle enough that some runs can fatal after the artifact is written.

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

The current OpenTable reservation validation uses the real booking query:

- `Make a reservation for me on OpenTable. Sake House By Hikari. Culver City. March 9. 7pm. 2 people.`

The latest successful artifact stops at:

- `Reserve table at Sake House By Hikari at 7:00 PM on March 9, for a party of 2`

## Known Follow-Up

The branch is now at the milestone where the generic browser substrate is live-validated across restaurant, hotel, flight, and checkout-style flows. Remaining work is narrower and lower priority:

- repeated live smoke runs to catch site drift and selector/semantic regressions
- tuning semantic extraction for more custom calendar, autocomplete, and modal variants
- refining venue-detail/page-stage inference where some detail pages still report a coarse `results` stage despite reaching the correct approval boundary
- replacing the current headless teardown containment path with a fully graceful in-process Chromium/CEF drain
