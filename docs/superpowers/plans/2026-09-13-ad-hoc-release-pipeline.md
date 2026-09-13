# Ad-hoc GitHub Releases Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish a public GitHub Releases distribution pipeline for Status Trio using an Ad-hoc signed app, an Ad-hoc signed DMG, Sparkle EdDSA signatures, and a public appcast.

**Architecture:** Reuse `scripts/build-app.sh` to create the release app bundle, package the validated app into a DMG with `hdiutil`, sign the DMG with Sparkle's `sign_update`, insert a generated item into `appcast.xml`, create a GitHub Release with `gh`, and commit the updated appcast. No Developer ID or Apple notarization is available for this distribution mode.

**Tech Stack:** Swift 6, Swift Package Manager, Sparkle 2.9.6, Bash, Ruby, `hdiutil`, `gh`, GitHub Releases, XML appcast

**Spec:** No separate design spec exists. The agreed design and constraints are captured in this document.

## Global Constraints

- Target macOS 15.0 or newer.
- Do not require a paid Apple Developer Program account.
- Do not attempt Developer ID signing or Apple notarization in this pipeline.
- Keep the existing Sparkle public key in `Support/Info.plist` unchanged.
- Keep every released app and `Sparkle.framework` Ad-hoc signed.
- The appcast and DMG must be downloadable anonymously over HTTPS.
- Every release must increase `CFBundleVersion`.
- Every release must have a unique `CFBundleShortVersionString` or build number.
- Users must remove quarantine after the first manual installation.
- Do not instruct users to disable Gatekeeper globally.

## Current State

- Sparkle 2.9.6 is integrated and committed in `3b76706`.
- `Support/Info.plist` contains `SUFeedURL`, `SUPublicEDKey`, and `SUEnableInstallerLauncherService`.
- The private Sparkle Ed25519 key exists in the login Keychain.
- `appcast.xml` exists but contains no release item.
- `release.json` exists and currently points to the private `lingyired/status-trio` repository.
- `scripts/build-app.sh` embeds `Sparkle.framework` and applies Ad-hoc signatures.
- The current feed URL returns HTTP 404 because the source repository is private.
- There is no project-local release command for DMG creation, Sparkle signing, appcast updates, or GitHub Release creation.
- A release has not yet been tested from `1.0.0 (1)` to a newer Ad-hoc build.

## File Structure

| Path | Responsibility |
| --- | --- |
| `Support/Info.plist` | Public Sparkle feed URL and permanent EdDSA public key |
| `appcast.xml` | Public Sparkle update channel and release items |
| `release.json` | Public GitHub repository, DMG name, branch, and minimum macOS version |
| `scripts/build-app.sh` | Build and Ad-hoc sign the release `.app` bundle |
| `scripts/release.sh` | Orchestrate DMG creation, Sparkle signing, GitHub Release creation, and appcast publication |
| `scripts/update-appcast.rb` | Insert a validated release item into `appcast.xml` |
| `README.md` | Installation, quarantine removal, update behavior, and release documentation |

## Task 1: Choose and configure public update hosting

**Files:**
- Modify: `Support/Info.plist`
- Modify: `release.json`
- Modify: `appcast.xml`

**Interfaces:**
- Consumes: existing Sparkle configuration in `Support/Info.plist`.
- Produces: one stable public HTTPS appcast URL used by all released app versions.

Choose exactly one hosting option before implementing the remaining tasks.

### Option A: Make the source repository public

Use this when the source code will eventually be public.

```text
Repository: lingyired/status-trio
Feed URL:   https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml
DMG URL:    https://github.com/lingyired/status-trio/releases/download/vVERSION/StatusTrio-VERSION.dmg
```

- [ ] **Step 1: Change repository visibility**

Confirm that publishing the source code is intentional, then make `lingyired/status-trio` public through GitHub.

Run:

```bash
gh repo edit lingyired/status-trio --visibility public --accept-visibility-change-consequences
gh repo view lingyired/status-trio --json visibility --jq .visibility
```

Expected: `PUBLIC`

- [ ] **Step 2: Keep the current feed configuration**

Verify:

```bash
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Support/Info.plist
```

Expected:

```text
https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml
```

### Option B: Keep the source repository private

Create a public repository that contains only `appcast.xml` and public release artifacts.

```text
Source:      lingyired/status-trio
Update repo: lingyired/status-trio-updates
Feed URL:    https://raw.githubusercontent.com/lingyired/status-trio-updates/main/appcast.xml
DMG URL:     https://github.com/lingyired/status-trio-updates/releases/download/vVERSION/StatusTrio-VERSION.dmg
```

- [ ] **Step 1: Create the public update repository**

Run:

```bash
gh repo create lingyired/status-trio-updates --public \
  --description "Public Sparkle updates for Status Trio"
```

- [ ] **Step 2: Publish an empty appcast**

Create `appcast.xml` in the update repository with the same empty channel structure currently used by `appcast.xml`, then commit and push it to `main`.

- [ ] **Step 3: Point the app at the update repository**

Set:

```text
SUFeedURL=https://raw.githubusercontent.com/lingyired/status-trio-updates/main/appcast.xml
```

Change `release.json` so `github_repo` is `lingyired/status-trio-updates`.

### Finish Task 1

- [ ] **Step 1: Verify the empty feed is publicly readable**

Run:

```bash
curl --fail --silent --show-error \
  "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Support/Info.plist)"
```

Expected: exit status 0 and an RSS XML document.

- [ ] **Step 2: Commit the hosting decision**

```bash
git add Support/Info.plist release.json appcast.xml
git commit -m "chore: configure public Sparkle feed"
git push origin main
```

## Task 2: Add deterministic appcast updates

**Files:**
- Create: `scripts/update-appcast.rb`

**Interfaces:**
- Consumes: version, build, minimum macOS version, DMG URL, Sparkle signature, DMG byte length, and release notes.
- Produces: a new `<item>` inserted immediately before `</channel>` in `appcast.xml`; exits non-zero for duplicate builds or invalid input.

- [ ] **Step 1: Create the appcast updater**

Implement `scripts/update-appcast.rb` with this command-line interface:

```bash
ruby scripts/update-appcast.rb \
  VERSION \
  BUILD \
  MINIMUM_SYSTEM_VERSION \
  DMG_URL \
  ED_SIGNATURE \
  DMG_LENGTH \
  RELEASE_NOTES_FILE
```

The implementation must:

1. Require all seven arguments.
2. Read `appcast.xml` from the repository root.
3. Refuse to continue when `<sparkle:version>BUILD</sparkle:version>` already exists.
4. XML-escape version, URL, signature, and length values.
5. Convert each non-empty release-notes line into one `<li>` element.
6. Escape embedded `]]>` sequences in the description CDATA.
7. Insert the new item before the closing `</channel>` tag.

- [ ] **Step 2: Validate the Ruby syntax**

```bash
ruby -c scripts/update-appcast.rb
```

Expected:

```text
Syntax OK
```

- [ ] **Step 3: Validate generated XML manually**

Use a copy of `appcast.xml` and a temporary notes file. After running the updater:

```bash
xmllint --noout appcast.xml
grep -F '<sparkle:version>1</sparkle:version>' appcast.xml
```

Expected: valid XML and one matching release item.

- [ ] **Step 4: Commit**

```bash
git add scripts/update-appcast.rb
git commit -m "build: add Sparkle appcast updater"
```

## Task 3: Add the project-local release command

**Files:**
- Create: `scripts/release.sh`
- Modify: `release.json`

**Interfaces:**
- Consumes: `release.json`, `Support/Info.plist`, `scripts/build-app.sh`, `scripts/update-appcast.rb`, the local Sparkle `sign_update`, and an authenticated `gh` CLI.
- Produces: `dist/StatusTrio-VERSION.dmg`, `dist/StatusTrio-VERSION.dmg.sha256`, a public GitHub Release, and a committed `appcast.xml` update.

- [ ] **Step 1: Extend `release.json`**

Add the production bundle identifier:

```json
{
  "bundle_id": "com.lingsmbp.StatusTrio"
}
```

Keep `github_repo`, `git_branch`, `min_system_version`, `bundle_name`, `dmg_name`, `appcast_file`, and `derived_data_prefixes` consistent with the hosting choice from Task 1.

- [ ] **Step 2: Implement preflight checks**

`scripts/release.sh` must fail before building when:

- The current branch is not the configured release branch.
- The configured GitHub repository is not public.
- `gh`, `git`, `hdiutil`, `shasum`, `ruby`, and `plutil` are unavailable.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update` is unavailable.
- `Support/Info.plist` lacks `SUPublicEDKey`.
- `SUFeedURL` does not match the configured public repository.
- `appcast.xml` is not valid XML.
- The current build number already exists in `appcast.xml`.

Use:

```bash
gh repo view "$GITHUB_REPO" --json visibility --jq .visibility
```

Expected: `PUBLIC`.

- [ ] **Step 3: Build and package the app**

Run the existing build script without replacing a running app:

```bash
BUNDLE_ID="$BUNDLE_ID" \
APP_NAME="$APP_NAME" \
bash scripts/build-app.sh release no-open
```

Create a temporary staging directory, copy `dist/StatusTrio.app` into it, add an `/Applications` symlink, and create the DMG:

```bash
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
```

- [ ] **Step 4: Generate checksum and Sparkle signature**

Run:

```bash
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
"$SIGN_UPDATE" "$DMG_PATH"
```

Parse `sparkle:edSignature` and `length` from the `sign_update` output. Do not continue if either value is missing.

- [ ] **Step 5: Create the GitHub Release**

Create the release before publishing the appcast item so the download URL is already valid:

```bash
gh release create "v$VERSION" \
  "$DMG_PATH" \
  "$DMG_PATH.sha256" \
  --repo "$GITHUB_REPO" \
  --title "v$VERSION" \
  --notes-file "$RELEASE_NOTES_FILE"
```

- [ ] **Step 6: Update and push the appcast**

Call the updater:

```bash
ruby scripts/update-appcast.rb \
  "$VERSION" \
  "$BUILD" \
  "$MINIMUM_SYSTEM_VERSION" \
  "$DMG_URL" \
  "$ED_SIGNATURE" \
  "$DMG_LENGTH" \
  "$RELEASE_NOTES_FILE"
```

Then validate and publish:

```bash
xmllint --noout appcast.xml
git add appcast.xml
git commit --only appcast.xml -m "Release v$VERSION appcast"
git push origin "$GIT_BRANCH"
```

- [ ] **Step 7: Verify the published feed**

```bash
curl --fail --silent --show-error "$SU_FEED_URL" | grep -F "<sparkle:version>$BUILD</sparkle:version>"
```

Expected: the new build number appears in the public appcast.

- [ ] **Step 8: Commit the release tooling**

```bash
git add scripts/release.sh release.json
git commit -m "build: add Ad-hoc GitHub release pipeline"
```

## Task 4: Document installation and update behavior

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the public DMG and appcast produced by `scripts/release.sh`.
- Produces: beginner-safe instructions for the first launch and Sparkle updates.

- [ ] **Step 1: Add the first-install warning**

Document that the app is Ad-hoc signed and not notarized. Explain that Gatekeeper may block the first launch.

- [ ] **Step 2: Add the exact installation commands**

```bash
cp -R "/Volumes/Status Trio/Status Trio.app" "/Applications/Status Trio.app"
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Do not recommend disabling Gatekeeper globally.

- [ ] **Step 3: Document subsequent updates**

Explain that Sparkle authenticates updates with EdDSA, clears quarantine from the installed update, and normally does not require users to run `xattr` again.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: explain Ad-hoc installation and updates"
```

## Task 5: Validate a complete two-version update

**Files:**
- No new source files required.

**Interfaces:**
- Consumes: a released and installed `1.0.0 (1)` Ad-hoc build.
- Produces: verified evidence that a public `1.0.1 (2)` release installs through Sparkle.

- [ ] **Step 1: Install the old release**

Install `1.0.0 (1)`, remove quarantine, launch it, and confirm the Settings window shows the update controls.

- [ ] **Step 2: Prepare `1.0.1 (2)`**

Update:

```text
CFBundleShortVersionString = 1.0.1
CFBundleVersion = 2
```

Keep `SUPublicEDKey` unchanged.

- [ ] **Step 3: Publish through the release script**

Run:

```bash
bash scripts/release.sh
```

Expected: the script creates the DMG, creates the GitHub Release, and publishes the appcast item.

- [ ] **Step 4: Verify the public feed**

```bash
SU_FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Support/Info.plist)"
curl --fail --silent --show-error "$SU_FEED_URL"
```

Expected: HTTP 200 and a `1.0.1` item with an `sparkle:edSignature`.

- [ ] **Step 5: Install through Sparkle**

Open the installed `1.0.0`, choose “Check for Updates…”, install `1.0.1`, and confirm the app relaunches with version `1.0.1 (2)`.

- [ ] **Step 6: Commit fixes only**

If validation required changes, commit only those changes:

```bash
git status --short
git add scripts/release.sh scripts/update-appcast.rb README.md release.json Support/Info.plist appcast.xml
git commit -m "fix: stabilize Ad-hoc Sparkle updates"
```

## Task 6: Future Developer ID migration

**Files:**
- Modify later: `scripts/build-app.sh`
- Modify later: `scripts/release.sh`
- Keep unchanged: `Support/Info.plist` `SUPublicEDKey`

**Interfaces:**
- Consumes: paid Apple Developer Program membership and a `Developer ID Application` certificate.
- Produces: a future notarized release path without changing the Sparkle trust root.

- [ ] **Step 1: Keep the Sparkle key stable**

Do not rotate `SUPublicEDKey` during the signing-identity migration.

- [ ] **Step 2: Add Hardened Runtime signing**

Sign the app with:

```bash
DEVELOPER_ID_APPLICATION="$(
  security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' \
    | head -n 1
)"

codesign --force \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "dist/Status Trio.app"
```

- [ ] **Step 3: Add notarization**

After creating the DMG:

```bash
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile status-trio-notary \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
```

- [ ] **Step 4: Keep Sparkle signing after notarization**

Run `sign_update` on the final notarized and stapled DMG, then publish the resulting signature in the appcast.

---

## Completion Criteria

This plan is complete when:

- The public appcast URL returns HTTP 200.
- A release DMG is downloadable without GitHub authentication.
- The DMG URL and EdDSA signature are present in `appcast.xml`.
- A `1.0.0 (1)` installation updates successfully to `1.0.1 (2)` through Sparkle.
- The updated app remains Ad-hoc signed and launches after Sparkle replaces it.
- README instructions cover quarantine removal for the first manual installation.
- The Sparkle Ed25519 key remains unchanged.

## Known Limitations

- Users must bypass Gatekeeper for the first manual installation.
- Enterprise-managed Macs may block Ad-hoc applications regardless of the appcast configuration.
- Apple may tighten Gatekeeper policies in future macOS releases.
- Ad-hoc signature identity is not stable like Developer ID, so Sparkle's EdDSA signature is the primary cross-version trust mechanism.
- This distribution path is not suitable for a fully managed public release with a promise of frictionless installation.
