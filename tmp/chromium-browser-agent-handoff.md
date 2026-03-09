# Chromium Browser Agent Handoff

## Branch

- Worktree: `/private/tmp/agenthub-macos-mr-70`
- Branch: `codex/mr-70-chromium-prototype`

## What Changed In This Slice

- Added `BrowserPageAnalysis.swift` to derive generic page requirements and workflow state from live inspection.
- Expanded `ChromiumInspection` and page-inspection JS with generic field metadata, notices, and step indicators.
- Expanded page inspection JS to infer semantic field purposes such as phone/email/name/address/payment/OTP/consent, plus inline validation messages.
- Added generic verification-code helpers:
  - `typeVerificationCode(...)`
  - `prepareVerificationCodeAutofill`
- Updated `ChromiumBrowserView` / `ChromiumBrowserController` so the embedded CEF view can take first responder focus and prime native macOS OTP autofill for the active verification field.
- Added an AppKit-side native OTP preparation path that promotes the best embedded text-input client to first responder, activates `NSTextInputContext`, invalidates character coordinates, and triggers completion so the platform one-time-code suggestion path can engage without an extra manual click.
- Updated `ChatSessionService` to:
  - carry inline structured user data into `GenericBrowserChatIntent`
  - merge inline data with saved persona contact data
  - auto-fill known requirements on the current page before prompting Codex again
  - pause on missing promptable requirements and ask the user for exactly the missing field
  - attach later follow-up messages to the active browser session first
  - resume the generic browser loop in the same CEF page after missing data or verification codes are supplied
- Expanded `PersonaContactProfile` / `PersonaManager` so saved persona data can be loaded and updated generically for browser autofill.
- Tightened `BrowserTransactionalGuard` to use generic workflow state instead of booking-only assumptions when deciding whether to auto-stop or require approval.
- Tightened `BrowserPageAnalyzer` success/failure detection so repeated labels like `Complete reservation Complete reservation` do not accidentally become fake success signals.
- Tightened review/details-page inspection so booking/details pages are not misclassified as `results`/`success` just because they contain incidental cards, country-code lists, or repeated submit labels.
- Down-ranked auth/noise controls such as `Use email instead`, `Use phone instead`, `Sign in`, and skip-navigation links in both semantic extraction and semantic resolution.
- Added a runtime execution guard in `ChatSessionService` so final-submit and auth-toggle clicks are rejected while required input is still missing; the loop now has to clarify or fill the missing requirement instead of spinning.
- Added tests for generic missing-requirement inference, generic workflow-stage inference, inline profile-data parsing, address line 2 + consent parsing, and OTP autofill preparation.
- Added regression tests for the live OpenTable review-page failure: required phone on `booking/details` now stages as blocked `details_form`, not `success`.

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

- Profile/settings UI still needs to expose the saved contact fields now supported by `PersonaManager` if product wants zero-chat autofill for phone/email/address/name.
- Run live validation again against the OpenTable review/auth flow. The generic substrate bugs that caused `booking/details` to be misread as `results`/`success` and to loop on auth toggles are fixed in code, but this slice still needs fresh live confirmation.
- Replace the current headless containment shutdown path with a fully graceful in-process Chromium/CEF drain. Chromium/CEF can still fatal after artifacts are written.
- Continue periodic live smoke runs against the manifest to catch site drift and regressions in semantic extraction.
