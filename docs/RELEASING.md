# Releasing

MythLog releases are built **locally on a Mac**. Signing and notarization run
against the Developer ID certificate and notarytool keychain profile on the
release machine.

CI (`.github/workflows/ci.yml`) runs the gate suite on every branch push and pull
request. On a `v*.*.*` **tag** it additionally packages a DMG and publishes a
**GitHub Release** — marked prerelease — with the DMG, zip, and checksums
attached and the version taken from the tag. It builds the `developer-id`
(unsandboxed) shape so it is actually launchable, but it is ad-hoc signed and
unnotarized, so Gatekeeper refuses it until you clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/MythLog.app
```

That build is for your own testing only — it is not something to hand to another
person. Everything below is the real release path.

Two distribution channels are produced from the same source, selected with
`MYTHLOG_DISTRIBUTION`:

| Channel | Value | Shape |
| --- | --- | --- |
| Mac App Store | `appstore` (default) | Sandboxed; App Group + iCloud ubiquity container. Requires an embedded provisioning profile. |
| Direct download | `developer-id` | Unsandboxed; signed with the Developer ID certificate and notarized for distribution outside the App Store. |

Signing the App Store entitlements with a Developer ID certificate produces
binaries the kernel SIGKILLs on launch, because the App Group and iCloud
container entitlements must be authorized by a provisioning profile that only
the App Store and Development channels have. `MYTHLOG_DISTRIBUTION=developer-id`
selects the unsandboxed entitlements instead
(`Xcode/MythLog.DeveloperID.entitlements`).

## Prerequisites

- A **Developer ID Application** certificate in the login keychain.
- A notarytool keychain profile:
  ```sh
  xcrun notarytool store-credentials MythLogNotary \
    --apple-id you@example.com --team-id TEAMID
  ```
  The app-specific password used here is a credential — keep it out of the
  repository (`.gitignore` already blocks `Apple.md`, `*.p12`, and provisioning
  profiles).

## Gate suite

Run before packaging anything you intend to ship. The `MYTHLOG_DMG_FINDER_LAYOUT=skip`
here is deliberate — this is a fast verification pass, and its DMG is a
throwaway artifact, not a release build:

```sh
./scripts/check-repository-metadata.sh
./scripts/check-format.sh
./scripts/check-swiftui-appkit-boundaries.sh
./scripts/check-swiftui-background-tasks.sh
./scripts/check-swiftui-main-thread-io.sh
./scripts/check-swiftui-store-boundaries.sh
./scripts/verify-release.sh
MYTHLOG_SKIP_RELEASE_BUILD=1 MYTHLOG_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
./scripts/audit-distribution.sh
```

## Building the direct-download DMG

This is the artifact users install. It runs `package-dmg.sh` without
`MYTHLOG_DMG_FINDER_LAYOUT=skip`, so it defaults to `required`: the styled
Finder layout (background art, positioned icons) is built, and the script fails
loudly rather than silently shipping a plain DMG. Run it from an interactive
macOS session so Finder automation can actually run.

```sh
MYTHLOG_DISTRIBUTION=developer-id \
MYTHLOG_VERSION=1.0.0 \
MYTHLOG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MYTHLOG_NOTARIZE=1 \
MYTHLOG_NOTARY_PROFILE=MythLogNotary \
  ./scripts/package-dmg.sh
```

Then audit the result:

```sh
MYTHLOG_VERSION=1.0.0 ./scripts/audit-distribution.sh
```

Expect `Public distribution readiness: PASS`, a stapled notarization ticket, and
`spctl` accepting both the DMG and the app as Notarized Developer ID.

Artifacts land in `dist/` (gitignored):

```text
dist/MythLog-1.0.0.dmg
dist/MythLog-1.0.0.dmg.sha256
dist/MythLog-1.0.0.zip
dist/MythLog-1.0.0.zip.sha256
dist/MythLog.app
```

## Building for the Mac App Store

Leave `MYTHLOG_DISTRIBUTION` at its default and archive through Xcode, which
applies the sandboxed entitlements and the provisioning profile. App Store
builds are uploaded through Xcode/Transporter, not through these scripts.

## Version numbers

`MYTHLOG_VERSION` threads the version through both packaging scripts and
defaults to `1.0.0`. Keep it in sync with `MARKETING_VERSION` in `project.yml`.

## Tagging

Tags are still worth cutting for your own history even without a release
pipeline attached to them:

```sh
git tag -a v1.0.0 -m "MythLog 1.0.0"
git push origin v1.0.0
```

Never move or re-point a published tag; cut a new patch version instead.
