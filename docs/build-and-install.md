# Build, package and install IQUNIX-DRIVE

This document describes how the IQUNIX-DRIVE macOS app is built **without Xcode**
(Command Line Tools + `swiftc` only), how the `.app` bundle and ZIP are produced,
and how to install it with Homebrew.

Everything here is local/offline: no network downloads, no notarization, no
Developer ID certificate. The app is ad-hoc signed and meant for personal use on
the machine that builds it.

---

## 1. Requirements

| Item | Requirement |
| --- | --- |
| macOS | 13.0 (Ventura) or newer — bundle sets `LSMinimumSystemVersion = 13.0` |
| Toolchain | Command Line Tools (`xcode-select -p` → `/Library/Developer/CommandLineTools`); full Xcode **not** required |
| Tools used | `swiftc`, `iconutil`, `codesign`, `ditto`, `plutil`, `shasum`, `open`, `pgrep`, `osascript` |
| Homebrew | Homebrew 7 (tested with 7.0.9). Homebrew 7 refuses cask files loaded from a plain path unless developer mode is on — see §4.1 |

No Xcode project exists on purpose: `scripts/build.sh` compiles the Swift sources
directly with `swiftc`.

---

## 2. Build the executables

```bash
cd /Volumes/MyFiles/Projects/IQUNIX-DRIVE
./scripts/build.sh release
```

Outputs:

```
.build-manual/iqunixctl       # CLI
.build-manual/IQUNIX-DRIVE    # SwiftUI app executable (not yet a .app)
```

When running inside a sandbox that restricts writes outside the repository,
`scripts/build.sh` already keeps `TMPDIR` and the Clang module cache inside
`.build-manual/{tmp,modulecache}`.

Debug build: `./scripts/build.sh debug`.

---

## 3. Package the `.app` (one command)

```bash
./scripts/make-app.sh
```

What it does:

1. Runs `./scripts/build.sh release` (skip with `SKIP_BUILD=1`).
2. Generates the app icon (skip with `SKIP_ICON=1`):
   - `scripts/make-icon.swift` renders a 1024×1024 master (dark rounded square,
     abstract keyboard, teal accent key) with AppKit/CoreGraphics and writes all
     10 required `.iconset` PNG sizes at their native pixel dimensions.
   - `iconutil -c icns` turns the iconset into `dist/AppIcon.icns`.
   - Note: in the DSH sandbox `iconutil` cannot write its output onto the
     workspace volume, so the script writes the `.icns` to `/tmp` first and
     copies it back. That is transparent on a normal machine.
3. Assembles `dist/IQUNIX-DRIVE.app`:

   ```
   dist/IQUNIX-DRIVE.app/
   ├── Contents/
   │   ├── Info.plist
   │   ├── PkgInfo                  # APPL????
   │   ├── MacOS/IQUNIX-DRIVE         # main executable
   │   ├── Helpers/iqunixctl          # CLI helper inside the bundle
   │   └── Resources/AppIcon.icns   # when icon generation succeeded
   ```

   `Info.plist` highlights: `CFBundleName`/`CFBundleDisplayName` = `IQUNIX-DRIVE`,
   `CFBundleIdentifier` = `com.iqunix.drive`, `CFBundleExecutable` =
   `IQUNIX-DRIVE`, `CFBundlePackageType` = `APPL`, `CFBundleShortVersionString` =
   `0.2.0`, `CFBundleVersion` = `1`, `LSMinimumSystemVersion` = `13.0`,
   `LSApplicationCategoryType` = `public.app-category.utilities`,
   `CFBundleIconFile` = `AppIcon`, `NSHighResolutionCapable` = true.
   **No App Sandbox entitlement** is added: the app needs unsandboxed
   `IOHIDManager` access to talk to the keyboard.
4. Ad-hoc signs: `codesign --force --deep --sign - dist/IQUNIX-DRIVE.app`.
5. Creates `dist/IQUNIX-DRIVE-0.2.0.zip` with `ditto -c -k --keepParent` and
   verifies it by extracting to `.build-manual/zipverify` and running
   `codesign --verify --deep --strict` on the extracted bundle.
6. Prints the zip's SHA-256 and **syncs `Casks/iqunix-drive.rb`** (`version`,
   `url`); the cask uses `sha256 :no_check` because the ZIP is built locally
   (a committed checksum would not match someone else's rebuild).
7. Smoke test: `open -n dist/IQUNIX-DRIVE.app`, waits 2 s, checks
   `pgrep -x IQUNIX-DRIVE`, then quits via AppleScript and falls back to `pkill`.
   Result is printed (`smoke test: PASS …`). Disable with `SMOKE_TEST=0`.

Useful environment switches:

```bash
SKIP_BUILD=1 ./scripts/make-app.sh   # reuse .build-manual binaries
SKIP_ICON=1  ./scripts/make-app.sh   # keep existing dist/AppIcon.icns
SMOKE_TEST=0 ./scripts/make-app.sh   # assemble only, do not launch
VERSION=0.2.0 ./scripts/make-app.sh  # other version (also updates the cask)
```

Artifacts after a successful run:

```
dist/IQUNIX-DRIVE.app
dist/IQUNIX-DRIVE-0.2.0.zip
dist/AppIcon.icns
dist/iqunixctl
dist/AppIcon.iconset/        # intermediate PNGs
```

The SHA-256 of the current zip is printed by the script and stored in
`Casks/iqunix-drive.rb`. Recompute any time with:

```bash
shasum -a 256 dist/IQUNIX-DRIVE-0.2.0.zip
```

The zip is not byte-for-byte reproducible (file timestamps are preserved), so
**always let `make-app.sh` update the cask sha256 after repackaging** — it does
this automatically.

---

## 4. Install with Homebrew

The cask (`Casks/iqunix-drive.rb`) uses a local `file://` URL pointing at
`dist/IQUNIX-DRIVE-0.2.0.zip`; no network access is involved and there is nothing
to notarize.

### 4.1 One command (Homebrew 7 requires developer mode for path casks)

Homebrew 7 rejects casks loaded from a plain file path unless developer mode is
enabled. The working one-liner is:

```bash
HOMEBREW_DEVELOPER=1 brew install --cask /Volumes/MyFiles/Projects/IQUNIX-DRIVE/Casks/iqunix-drive.rb
```

This installs `/Applications/IQUNIX-DRIVE.app`:

```bash
open "/Applications/IQUNIX-DRIVE.app"
```

If `/Applications` is not writable for your account (or you prefer a per-user
install), point Homebrew at another app directory:

```bash
HOMEBREW_DEVELOPER=1 brew install --cask \
  --appdir="$HOME/Applications" \
  /Volumes/MyFiles/Projects/IQUNIX-DRIVE/Casks/iqunix-drive.rb
open "$HOME/Applications/IQUNIX-DRIVE.app"
```

### 4.2 Local tap route (no developer mode needed)

Homebrew never installs casks outside a tap in normal mode, so create a
throw-away local tap once, copy the cask into it and install by tap token:

```bash
brew tap-new local/iqunix-drive --no-git
cp /Volumes/MyFiles/Projects/IQUNIX-DRIVE/Casks/iqunix-drive.rb \
   "$(brew --repository)/Library/Taps/local/homebrew-iqunix-drive/Casks/"
brew install --cask local/iqunix-drive/iqunix-drive
open "/Applications/IQUNIX-DRIVE.app"
```

After a rebuild, copy the cask into the tap again and reinstall:

```bash
cp /Volumes/MyFiles/Projects/IQUNIX-DRIVE/Casks/iqunix-drive.rb \
   "$(brew --repository)/Library/Taps/local/homebrew-iqunix-drive/Casks/"
brew reinstall --cask local/iqunix-drive/iqunix-drive
```

### 4.3 Verify the cask without installing

These are the checks used while building this integration (they pass):

```bash
HOMEBREW_DEVELOPER=1 brew info  --cask ./Casks/iqunix-drive.rb
HOMEBREW_DEVELOPER=1 brew fetch --cask ./Casks/iqunix-drive.rb   # downloads + verifies sha256

# local-tap variant
brew info  --cask local/iqunix-drive/iqunix-drive
brew fetch --cask local/iqunix-drive/iqunix-drive
```

### 4.4 Uninstall

```bash
brew uninstall --cask iqunix-drive                # path-installed cask
# or
brew uninstall --cask local/iqunix-drive/iqunix-drive
```

The cask's `uninstall quit: "com.iqunix.drive"` quits the running app first.
If you also created the local tap and want to remove it:

```bash
brew untap local/iqunix-drive
```

### 4.5 Manual install (no Homebrew)

```bash
ditto -x -k dist/IQUNIX-DRIVE-0.2.0.zip /tmp/iqunix-install
cp -R /tmp/iqunix-install/IQUNIX-DRIVE.app "/Applications/IQUNIX-DRIVE.app"
open "/Applications/IQUNIX-DRIVE.app"
```

### 4.6 Sandbox limitations seen during development

The packaging was developed inside the DeepSeek Harness sandbox, which is
stricter than a normal login shell. Consequences and workarounds:

- `/Applications` and `/opt/homebrew` are **not writable** from the sandbox, so
  a full `brew install` cannot complete there. `brew info`/`brew fetch` were run
  against a temporary Homebrew prefix in `/tmp` and both pass (fetch verifies
  the sha256).
- Homebrew runs its extraction step inside its own `sandbox-exec`; nesting that
  inside the harness sandbox fails (`sandbox-exec: sandbox_apply: Operation not
  permitted`). This is a harness limitation, not a cask problem — from a normal
  Terminal the same command works.
- `iconutil` cannot write onto the external workspace volume from the sandbox;
  `make-app.sh` writes the `.icns` to `/tmp` and copies it into `dist/`.

---

## 5. Signing, Gatekeeper and TCC (Input Monitoring)

### Ad-hoc signature

- The bundle is signed with `codesign --force --deep --sign -`, i.e. an **ad-hoc**
  signature with no Team ID. `codesign -dv` shows `Signature=adhoc`,
  `TeamIdentifier=not set`.
- It is **not notarized**. `spctl -a -vv dist/IQUNIX-DRIVE.app` prints
  `rejected` — that is expected and harmless for a locally built app.
- Because the app is built locally it has no `com.apple.quarantine` attribute,
  so double-clicking / `open` works without a Gatekeeper dialog. If you move a
  downloaded copy of the zip to another machine, remove quarantine once:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/IQUNIX-DRIVE.app"
  # or: right-click → Open the first time
  ```

### Input Monitoring permission (expected first-run prompt)

IQUNIX-DRIVE reads raw HID reports (usage page `0xFF60`) via `IOHIDManager`. On
macOS 13+ that requires the **Input Monitoring** TCC permission:

1. Launch the app once. macOS shows a prompt, or the app shows its
   "需要输入监控权限" state.
2. Open **System Settings → Privacy & Security → Input Monitoring**.
3. Enable **IQUNIX-DRIVE** (quit and relaunch if it does not appear; restarting
   once after enabling is normal).
4. Keep the keyboard plugged in and re-open the app.

This prompt is intentional and must not be silently bypassed.

**Why it may ask again:** TCC keys access on the code signature identity. The
ad-hoc identity changes whenever the executable is re-signed (every rebuild) or
the bundle is moved/renamed (bundle path is part of the identity). After a
`brew reinstall`, a new `make-app.sh` build, or moving the app to another
folder, macOS may show the Input Monitoring prompt again — re-toggle the entry
in System Settings. A Developer ID signature + notarization would keep the
identity stable; that is out of scope for this local-only setup.

### No App Sandbox

The bundle deliberately has **no** `com.apple.security.app-sandbox`
entitlement: a sandboxed app cannot open `IOHIDManager` devices on macOS, so
sandboxing would break the keyboard connection. Do not add it.

---

## 6. Known limitations

- Not notarized, no Developer ID; for local/personal use only.
- Homebrew 7 needs `HOMEBREW_DEVELOPER=1` for path casks (or use the local tap
  route).
- Ad-hoc signature ⇒ TCC "Input Monitoring" permission may need re-approval
  after each rebuild/move.
- Apple Silicon tested (macOS 26.6.2, arm64). **Intel Macs untested** (the
  build is a thin arm64 binary made with `swiftc` on this Mac).
- The `.app` contains only an ad-hoc-signed SwiftUI executable; there is no
  `CFBundleIconName` asset catalog — the icon is a plain `.icns`.
- `iqunixctl` is bundled at `Contents/Helpers/iqunixctl` for convenience; the GUI
  does not depend on it and it is not on `PATH` after a cask install. Use
  `"/Applications/IQUNIX-DRIVE.app/Contents/Helpers/iqunixctl" --help` if needed.
- Do not run `iqunixctl` write commands during smoke tests — they change the
  keyboard state.

---

## 7. Troubleshooting

| Symptom | Check |
| --- | --- |
| `swiftc: command not found` | `xcode-select --install` / `xcode-select -p` |
| Build failure in `Sources/IQUNIX-DRIVE` | UI sources mid-edit; `SKIP_BUILD=1 ./scripts/make-app.sh` reuses last successful binaries, or fix the Swift errors |
| Icon missing | run `./scripts/make-app.sh` (without `SKIP_ICON=1`) and check the `icon:` / `ICON: yes` lines |
| Cask sha mismatch after repackaging | rerun `./scripts/make-app.sh` — it updates `Casks/iqunix-drive.rb` automatically |
| `brew install` says cask must be in a tap | use `HOMEBREW_DEVELOPER=1` (see 4.1) or the local tap (4.2) |
| App launches but no keyboard found | grant Input Monitoring (§5), replug keyboard, relaunch app |
| `spctl` rejects the app | expected for ad-hoc, not-notarized builds; locally built copies are not quarantined |
| Leftover process after testing | `pkill -x IQUNIX-DRIVE` |

---

## 8. Files involved

| Path | Purpose |
| --- | --- |
| `scripts/build.sh` | swiftc build of `iqunixctl` + `IQUNIX-DRIVE` (owned by the build/UI work) |
| `scripts/make-app.sh` | build → icon → bundle → ad-hoc sign → zip → verify → cask sync → smoke test |
| `scripts/make-icon.swift` | AppKit/CoreGraphics icon renderer (iconset output, repeatable) |
| `Casks/iqunix-drive.rb` | local Homebrew cask (`file://` URL, auto-synced sha256) |
| `dist/IQUNIX-DRIVE.app` | assembled, ad-hoc-signed app bundle |
| `dist/IQUNIX-DRIVE-0.2.0.zip` | distribution zip + checksum |
| `dist/AppIcon.icns` | generated icon |
