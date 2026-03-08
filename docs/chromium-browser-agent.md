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

## Known Remaining Work

The branch is materially more generic, but a few items still require live validation rather than more local refactoring:

- repeated smoke runs across hotel and flight sites
- tuning semantic extraction for more custom calendar and autocomplete variants
- validating final-confirmation boundary detection on unfamiliar checkout flows
