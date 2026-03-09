# Sparkle Dev Test README

This document is the manual test path for AgentHub's v1 update model:

- Sparkle updates the full AgentHub app.
- New Codex binaries ship inside new AgentHub releases.
- The build server is not required for this first validation loop.

## What Is Already Wired

- Debug builds point at `http://127.0.0.1:8000/dev/appcast.xml`.
- Release builds point at `https://updates.example.com/agenthub/appcast.xml`.
- Sparkle stays disabled until `SUPublicEDKey` is set to a real value.
- The app exposes `Check for Updates...` in the app menu when the updater is configured.

## Preconditions

- Xcode can build `AgentHub.xcodeproj`.
- You have a macOS account that can approve Keychain access prompts.
- You can run a local static file server on `127.0.0.1:8000`.

## 1. Build Sparkle's Helper Tools Once

Locate the Sparkle checkout that Xcode resolved:

```bash
export SPARKLE_CHECKOUT="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/checkouts/Sparkle' -type d | head -n 1)"
```

Build the two Sparkle helper tools:

```bash
xcodebuild -project "$SPARKLE_CHECKOUT/Sparkle.xcodeproj" -scheme generate_keys -configuration Release build
xcodebuild -project "$SPARKLE_CHECKOUT/Sparkle.xcodeproj" -scheme generate_appcast -configuration Release build
```

Locate the built binaries:

```bash
export GENERATE_KEYS_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/Release/generate_keys' -type f | head -n 1)"
export GENERATE_APPCAST_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/Release/generate_appcast' -type f | head -n 1)"
```

## 2. Generate a Dev Signing Key

Run Sparkle's key generator:

```bash
"$GENERATE_KEYS_BIN"
```

This stores the private key in your login keychain and prints the public key value for `SUPublicEDKey`.

Save the printed public key:

```bash
export SPARKLE_PUBLIC_ED_KEY="<paste-public-key-here>"
```

## 3. Prepare a Local Dev Feed Folder

Create a local updates directory:

```bash
mkdir -p /tmp/agenthub-updates/dev
```

Optional release notes file:

```bash
cat >/tmp/agenthub-updates/dev/release-notes-1.1.html <<'EOF'
<html>
  <body>
    <h1>AgentHub 1.1</h1>
    <p>Dev-only Sparkle verification build.</p>
  </body>
</html>
EOF
```

## 4. Build the Installed Baseline App

Build an older app version into a dedicated output directory. These overrides avoid editing the project just for local validation:

```bash
xcodebuild -project AgentHub.xcodeproj -scheme AgentHub -configuration Debug \
  MARKETING_VERSION=1.0 \
  CURRENT_PROJECT_VERSION=100 \
  AGENTHUB_SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CONFIGURATION_BUILD_DIR=/tmp/agenthub-builds/1.0 \
  build
```

Result:

```text
/tmp/agenthub-builds/1.0/AgentHub.app
```

Install or launch that copy as your baseline app.

## 5. Build the Update Candidate

Build the newer app version:

```bash
xcodebuild -project AgentHub.xcodeproj -scheme AgentHub -configuration Debug \
  MARKETING_VERSION=1.1 \
  CURRENT_PROJECT_VERSION=101 \
  AGENTHUB_SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CONFIGURATION_BUILD_DIR=/tmp/agenthub-builds/1.1 \
  build
```

Package it for Sparkle:

```bash
ditto -c -k --keepParent /tmp/agenthub-builds/1.1/AgentHub.app /tmp/agenthub-updates/dev/AgentHub-1.1.zip
```

## 6. Generate the Dev Appcast

Generate `appcast.xml` for the updates folder:

```bash
"$GENERATE_APPCAST_BIN" \
  --download-url-prefix http://127.0.0.1:8000/dev \
  --release-notes-url-prefix http://127.0.0.1:8000/dev \
  -o /tmp/agenthub-updates/dev/appcast.xml \
  /tmp/agenthub-updates/dev
```

At this point the folder should look like:

```text
/tmp/agenthub-updates/dev/
  AgentHub-1.1.zip
  appcast.xml
  release-notes-1.1.html
```

## 7. Serve the Feed Locally

From `/tmp/agenthub-updates`, start a local static server:

```bash
cd /tmp/agenthub-updates
python3 -m http.server 8000 --bind 127.0.0.1
```

The feed URL now matches the app's Debug default:

```text
http://127.0.0.1:8000/dev/appcast.xml
```

## 8. Trigger the Update in AgentHub

Launch `/tmp/agenthub-builds/1.0/AgentHub.app`.

In the app:

1. Open `AgentHub -> Check for Updates...`
2. Confirm Sparkle finds `1.1`
3. Accept the update
4. Let Sparkle install and relaunch the app

If Sparkle does not re-check because of caching, clear the last-check timestamp and retry:

```bash
defaults delete au.com.roseadvisory.AgentHub SULastCheckTime
```

## 9. Verify the App Update Worked

Confirm the relaunched app reports the newer version:

```bash
defaults read /tmp/agenthub-builds/1.1/AgentHub.app/Contents/Info CFBundleShortVersionString
defaults read /tmp/agenthub-builds/1.1/AgentHub.app/Contents/Info CFBundleVersion
```

Expected values:

- `CFBundleShortVersionString = 1.1`
- `CFBundleVersion = 101`

## 10. Verify the Bundled Codex Payload Changed

For v1, the product contract is "Codex updates arrive inside a new AgentHub app build." The simplest manual check is to compare the bundled binary checksum in the baseline build and the update build.

Run:

```bash
shasum -a 256 /tmp/agenthub-builds/1.0/AgentHub.app/Contents/Resources/codex
shasum -a 256 /tmp/agenthub-builds/1.1/AgentHub.app/Contents/Resources/codex
```

If you intentionally changed the bundled Codex binary between the two builds, the hashes should differ. After Sparkle finishes, the installed app should match the `1.1` checksum.

## Pass/Fail Checklist

- [ ] `AgentHub.app` builds with Sparkle linked and signed.
- [ ] `Check for Updates...` is visible in the app menu.
- [ ] Sparkle reads the local dev appcast.
- [ ] Sparkle offers `1.1` when `1.0` is installed.
- [ ] Sparkle installs the new build and relaunches AgentHub.
- [ ] The relaunched app reports the expected version/build.
- [ ] The bundled Codex payload matches the newer app build.

## Known Limits Of This Manual Test

- This validates the client update loop, not notarization or production hosting.
- It does not validate the future build server, webhook receiver, or automatic Codex-release detection.
- The current repo still emits an existing deployment target warning (`26.2` vs supported `26.0.99`) during Xcode builds.
