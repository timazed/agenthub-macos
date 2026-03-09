# Sparkle Dev Test Setup

This checklist gets AgentHub onto a safe dev-only Sparkle update loop before any Codex-triggered release automation is added.

## Goals

- Verify AgentHub can update itself through Sparkle.
- Verify the bundled Codex binary can ride inside a normal AgentHub app update.
- Keep all testing isolated from the future production appcast.

## Checklist

- [ ] Add Sparkle to the app and expose `Check for Updates...`
- [ ] Generate a dev-only Sparkle EdDSA keypair with Sparkle's `generate_keys`
- [ ] Set the app's `SUPublicEDKey` to the generated public key
- [ ] Serve a dev-only appcast feed over HTTP or HTTPS
- [ ] Build `AgentHub 1.0`
- [ ] Build `AgentHub 1.1`
- [ ] Package the newer build into an update archive
- [ ] Generate the dev appcast with Sparkle's `generate_appcast`
- [ ] Launch `1.0` and confirm it sees `1.1`
- [ ] Install the update and confirm AgentHub relaunches on `1.1`
- [ ] Confirm the relaunched app is using the newer bundled Codex version

## Suggested Local Layout

```text
/tmp/agenthub-updates/
  dev/
    appcast.xml
    AgentHub-1.1.zip
    release-notes-1.1.html
```

Serve that folder locally during development, for example with a simple static server bound to `127.0.0.1`.

## Suggested Debug Feed URL

For local testing, point debug builds at:

```text
http://127.0.0.1:8000/dev/appcast.xml
```

The project currently uses that URL as the default debug placeholder.

## Manual Test Sequence

1. Generate dev keys and wire the public key into the project.
2. Build and install `AgentHub 1.0`.
3. Build `AgentHub 1.1` with a visible version change and, if needed, a newer bundled Codex binary.
4. Put the `1.1` archive into the dev updates folder.
5. Run `generate_appcast` against the updates folder.
6. Start the local static server.
7. Launch `1.0`.
8. Use `Check for Updates...` to trigger a manual Sparkle check.
9. Install the offered update.
10. Relaunch and verify the app version and Codex version.

## Notes

- Use a dev-only keypair and appcast feed. Do not reuse the future production signing key.
- Sparkle caches update checks. During local testing you may need to clear `SULastCheckTime`.
- The updater stays disabled until `SUPublicEDKey` is set to a real key.
