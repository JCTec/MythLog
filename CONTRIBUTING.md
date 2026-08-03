# Contributing

MythLog is intended to be a consent-first macOS security event recorder.

MythLog's source is available under the [MythLog Personal Use License](LICENSE) — copying and modifying for personal use is welcome, but the license does not permit redistributing the Software or using it to offer a product or service to others. The license carries an explicit exception for contributions: forking or copying the repository solely to prepare and submit a pull request, patch, or issue back to this project is permitted.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md). Do not publish exploit details, private ledger records, hostnames, paths, tokens, or secrets in public issues or pull requests.

## Development

```sh
./scripts/check-repository-metadata.sh
./scripts/check-format.sh
./scripts/check-swiftui-appkit-boundaries.sh
./scripts/check-swiftui-background-tasks.sh
./scripts/check-swiftui-main-thread-io.sh
./scripts/check-swiftui-store-boundaries.sh
swift build
swift run -c debug mythlog-tests
swift run mythlog-probe --self-test --duration 2
```

Before opening a pull request that touches app code, the app bundle, or installer flow, run the full release gate. `MYTHLOG_DMG_FINDER_LAYOUT=skip` below is intentional — this is a fast verification pass, not a build meant to be shipped, so it skips the Finder-styled layout that requires an interactive GUI session:

```sh
./scripts/verify-release.sh
MYTHLOG_SKIP_RELEASE_BUILD=1 MYTHLOG_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
./scripts/audit-distribution.sh
```

For the maintainer-facing public release pass, use [Release Checklist](docs/RELEASE_CHECKLIST.md).

## Branches, tags, and releases

CI runs the gate suite on every push to `main` and on pull requests, and
uploads ad-hoc signed convenience builds for testing. **Shipping builds are not
produced by CI** — the release DMG is built, signed with the Developer ID
certificate, and notarized locally on a Mac.

- Day-to-day work lands on `main`; CI must be green.
- A release is built locally with `./scripts/package-dmg.sh` and tagged
  `vX.Y.Z`. **Tags are immutable** — never move a published tag; cut a new patch
  instead.

The full flow lives in [Releasing](docs/RELEASING.md).

## Documentation and the wiki

`docs/` is the source of truth. The project Wiki is generated from `docs/**`
(and this file) by the [`Wiki Sync`](.github/workflows/wiki-sync.yml) workflow on
every push to `main` — edit the Markdown under `docs/`, not the wiki directly
(direct wiki edits are overwritten). New docs appear automatically; add a nice
sidebar title in `.github/scripts/build-wiki.py` if the derived one needs polish.

## Code Organization

- `MythLogCore` contains reusable event, ledger, rule, config, and notifier logic.
- Keep LaunchAgent behavior split by responsibility: lifecycle surface in `LaunchAgentManager`, command/status models, install preparation, secret hardening, ledger migration, process execution, and status parsing in focused helper files.
- `MythLogCLIKit` contains testable CLI command helpers; keep the `mythlogctl` executable target focused on command dispatch.
- `MythLogAppSupport` contains the reusable viewer implementation.
- `MythLogApp` is intentionally tiny and should remain only the executable entrypoint.
- App code is organized by feature: `App`, `State`, `Timeline`, `Inspector`, `Filters`, and `SharedUI`.
- Keep AppKit shell files split by responsibility: menu construction belongs in `MainMenuController`, while menu command handlers belong in focused action files.
- Pure app logic that can be tested without rendering SwiftUI belongs in `MythLogAppSupport/State` or `Timeline/Canvas`.
- Keep state contracts separate from shipped defaults and derived-state engines. For example, filter definitions, default filter templates, and display-state computation live in separate files.
- Keep `SharedUI` files focused on one reusable component or a tight design-system family; keep spacing/radius tokens in `DesignTokens`, and avoid catch-all toolbar/view files.
- Editor defaults are documented in `.editorconfig`; Git line-ending and binary handling are documented in `.gitattributes`.
- Swift formatting is enforced with `swift-format` through `.swift-format` and `./scripts/check-format.sh`.
- GitHub issue templates, PR template, security policy, and script permissions are checked with `./scripts/check-repository-metadata.sh`.
- Release readiness is enforced locally and in CI through `./scripts/verify-release.sh`, `./scripts/package-dmg.sh`, and `./scripts/audit-distribution.sh`.
- `Sources/MythLogTests/MythLogTests.swift` should stay a small orchestrator. Put reusable assertions and fixtures in `TestSupport.swift`; split core coverage across `CoreLedgerTests.swift`, `CoreRuleTests.swift`, `CoreConfigSecretTests.swift`, `CoreOperationsTests.swift`, and `CoreLaunchAgentTests.swift`; put CLI doctor helper behavior in `CLIKitTests.swift`, runtime smoke coverage in `AgentRuntimeTests.swift`, app shell/helper behavior in `AppSupportTests.swift`, timeline state/export behavior in `TimelineStateTests.swift`, timeline placement behavior in `TimelineLayoutTests.swift`, and store/preference behavior in `TimelineStoreTests.swift`.

## SwiftUI Guidelines

- Keep container views responsible for app state and leaf views responsible for rendering values.
- Prefer passing value models and callbacks into leaf views instead of broad `@EnvironmentObject` access.
- Keep `@EnvironmentObject` usage inside root/container views only; `./scripts/check-swiftui-store-boundaries.sh` enforces the current boundary.
- Keep AppKit delegate, menu, window, and system-setting commands in `MythLogAppSupport/App`; pass them into SwiftUI through focused action structs such as `MythLogAppActions`. `./scripts/check-swiftui-appkit-boundaries.sh` enforces this for `NSApplication`/`NSApp` shell access.
- Keep file reads, JSON decoding, layout placement, process waits, and other expensive work off the main actor.
- In `MythLogAppSupport`, use `MythLogBackgroundTask` for detached work so cancellation behavior stays consistent.
- Keep stores focused on orchestration and publication; move pure classification, layout, filtering, and export logic into separate helpers that can run off-main and be tested without SwiftUI.
- Do not call synchronous file-content APIs or spawn/wait on processes directly from `MythLogAppSupport`; `./scripts/check-swiftui-main-thread-io.sh` catches the obvious cases.
- Keep loaded timeline records and their lookup index together as a `TimelineRecordSet`; do not rebuild large indexes in main-actor property observers.
- Publish derived timeline state as a single value update; do not add separate `@Published` arrays for values that must stay in sync.
- Make expensive SwiftUI tasks cancellation-aware when their inputs can change quickly, especially timeline layout, search, and filtering paths.
- Add tests for derived state, layout, filtering, persistence, and core behavior when changing those areas.
- Prefer Apple frameworks and local helpers over new dependencies.

## Rules

- Keep the project pure Swift unless there is an explicit native API reason.
- Prefer Apple frameworks over third-party dependencies.
- Keep event collectors narrow and auditable.
- Add tests for core behavior and pure app-side behavior.
- Document any hook that requires manual verification, privileges, or entitlements.
- Do not add keylogging, screenshot capture, hidden surveillance, or private-content capture.
- Do not commit local ledgers, proof exports, app logs, host-specific screenshots, `.pyc` files, or built release artifacts unless the file is intentionally part of public documentation or a tagged release process.
