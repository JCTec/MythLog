# Technical Capabilities

What MythLog can and cannot observe on macOS, and what constrains the data model.
This page exists so design work starts from real limits rather than from a
mockup. Everything here is either verified against this repository's source, or
cited; where a claim is inferred and still needs a test on a real machine, it
says so.

Last reviewed: August 2026.

---

## 1. The three capability tiers

MythLog does not have one capability ceiling. It has three, and which one
applies is decided by how the build is signed and distributed. This is the
single most important fact for any feature planning.

| Tier | Build | How it ships | Ceiling |
| --- | --- | --- | --- |
| **A** | Sandboxed | Mac App Store (`MYTHLOG_DISTRIBUTION=appstore`) | Notification-level observation of the user's own session. No system log, no arbitrary filesystem, no process spawn. |
| **B** | Unsandboxed | Developer ID DMG (`MYTHLOG_DISTRIBUTION=developer-id`) | Everything in A, plus the system-wide unified log, arbitrary paths, process spawn, IOKit. |
| **C** | Unsandboxed + restricted entitlement | Developer ID only, after Apple approval | Everything in B, plus true process-attributed file and exec events via Endpoint Security. |

Both A and B already exist in this repository and are selected by
`MYTHLOG_DISTRIBUTION` in `scripts/package-release.sh`. Tier C does not exist and
would require a separate application to Apple.

**Tier A and Tier B are not the same product.** A user who installs from the App
Store gets a meaningfully less observant app than one who downloads the DMG.
That gap is permanent and cannot be engineered away. Design must express it, not
hide it.

### Why Tier A cannot read the system log

`OSLogStore(scope: .system)` — the gateway to failed logins, TCC prompts, USB
attach, screen sharing, `sudo`, SSH, and most security-interesting signals — does
not work under App Sandbox. A sandboxed process can only use
`.currentProcessIdentifier`, i.e. read its own log entries. The
`com.apple.logging.local-store` entitlement that would lift this is not available
to third-party developers, and App Sandbox is mandatory for the Mac App Store.
There is no workaround.

`Sources/MythLogCore/UnifiedLogReader.swift` already implements both scopes; only
the `.system` path is blocked in the sandboxed build.

### Why Tier C cannot ever reach the App Store

Endpoint Security requires the restricted
`com.apple.developer.endpoint-security.client` entitlement. ES clients are not
supported on the Mac App Store at all. For Developer ID distribution the
entitlement must be requested from Apple and explicitly approved, and Apple may
grant only the development-level entitlement rather than the production one
needed to ship. Binaries must additionally be notarized and stapled.

---

## 2. What MythLog observes today

Verified by reading the source.

| Signal | Mechanism | File | Tier |
| --- | --- | --- | --- |
| Screen locked / unlocked | `DistributedNotificationCenter`, `com.apple.screenIsLocked` / `…Unlocked` | `SessionEventSource.swift` | A |
| Sleep / wake | `NSWorkspace.willSleepNotification`, `didWakeNotification` | `SessionEventSource.swift` | A |
| Displays sleep / wake | `NSWorkspace.screensDidSleep/DidWakeNotification` | `SessionEventSource.swift` | A |
| App launch / activate / terminate | `NSWorkspace.didLaunch/DidActivate/DidTerminateApplicationNotification` | `SessionEventSource.swift` | A |
| File / folder changes | `DispatchSource.makeFileSystemObjectSource` over `open(path, O_EVTONLY)` | `FileEventSource.swift` | A (user-granted paths) / B (any path) |
| Unified log matches | `OSLogStore` + `NSPredicate` | `UnifiedLogReader.swift` | B for `.system` |
| Custom events | JSON spool ingested from `mythlogctl` / app | `EventSpool.swift` | A |
| Recorder heartbeat | Timer in the agent runtime | `MythLogAgentRuntime.swift` | A |
| Ledger integrity / rotation / anchoring | Ledger internals | `HashChainLedger.swift`, `LedgerHashAnchor.swift` | A |

**Note on file watching:** the current implementation watches *specific file
descriptors* via `DispatchSource`, not `FSEvents`. That is reliable for a known
set of paths but does not naturally give recursive subtree coverage or the
coalescing behaviour FSEvents provides. Any design that promises "watch this
folder and everything under it" at volume should assume a move to `FSEventStream`
is required.

---

## 3. Candidate signals

Grouped by the tier that unlocks them. "Effort" is rough and is *information,
not a veto* — a correct design that takes longer still wins.

### Tier A — available in the App Store build

These are the cheapest wins and the only ones that improve the App Store product.

| Signal | API | Notes | Effort |
| --- | --- | --- | --- |
| Volume mounted / unmounted | `NSWorkspace.didMountNotification` / `didUnmountNotification` | External drive attach is a genuine security signal. | Low |
| Fast user switching | `NSWorkspace.sessionDidBecomeActiveNotification` / `…ResignActive` | Another account used this Mac. High signal. | Low |
| External display connected | `CGDisplayRegisterReconfigurationCallback` | Needs verification under sandbox. | Low |
| Power source / battery | `IOPSNotificationCreateRunLoopSource` | Unplugged while away is meaningful. | Low |
| Idle duration | `CGEventSourceSecondsSinceLastEventType` | A query, not an event tap — no Accessibility permission. Verify. | Low |
| Thermal / low-power state | `ProcessInfo.thermalStateDidChangeNotification`, `NSProcessInfoPowerStateDidChange` | Weak security value, cheap. | Low |
| Clipboard changed | `NSPasteboard.general.changeCount` polling | **Cannot attribute which app changed it.** Value is limited without the actor. | Low |
| Wi-Fi network changed | CoreWLAN | Reading SSID on recent macOS requires Location permission — a new TCC prompt, which conflicts with the app's consent posture. Verify before committing. | Medium |
| App focus duration | Derived from existing activate/terminate events | No new capture; pure derivation. | Low |

### Tier B — Developer ID build only

Everything here is invisible in the App Store build.

| Signal | API | Notes |
| --- | --- | --- |
| Failed login attempts | `OSLogStore(.system)` on `loginwindow` / `opendirectoryd` | The mockup's "Password, 2nd attempt". This is the strongest signal in the product and **is not achievable in the App Store build.** |
| TCC permission prompts | `OSLogStore(.system)` on `tccd` | Something asked for camera/mic/screen access. |
| USB device attach / detach | `IOServiceAddMatchingNotification`, or the unified log | Device identity needs IOKit. |
| Screen sharing / remote login | `OSLogStore(.system)`, `screensharingd` / `sshd` | Very high security value. |
| `sudo` / privilege escalation | `OSLogStore(.system)` | High value. |
| Login / logout records | `getutxent`, `/var/run/utmpx` | Historical sessions, survives reboot. |
| Arbitrary path watching | `FSEventStream` outside the container | Watch `~` or a whole volume. |
| Bluetooth device connect | IOBluetooth | Moderate value. |
| VPN / network interface state | SystemConfiguration `SCDynamicStore` | Moderate value. |
| Time Machine activity | `tmutil` (process spawn) or unified log | Process spawn is blocked under sandbox. |

### Tier C — Endpoint Security, Developer ID + Apple approval

| Signal | Notes |
| --- | --- |
| Process execution with full lineage | `ES_EVENT_TYPE_NOTIFY_EXEC` — which binary, which parent, signed by whom. |
| File events **with the responsible process** | The only way to answer "*what* changed this file", rather than "this file changed". |
| Mount, rename, unlink, task port access | Full endpoint telemetry. |

**Tier C is the only way to get actor attribution.** If the design shows "which
process touched this file", that is a Tier C feature and must be labelled as
such.

### Not possible, or out of scope by policy

- **Keystroke content** — excluded by product principle, not just by API.
- **Screen contents** — same.
- **Other apps' camera/microphone usage** — no supported public API. Inferable
  only indirectly from the unified log (Tier B), and unreliably.
- **Which app read the clipboard** — no public API.
- **Per-connection network traffic** — needs a NetworkExtension content filter
  and system extension; not App Store viable, and a very large undertaking.

---

## 4. The data-model constraint

This is the sharpest limit on any 2.0 redesign, and it is easy to miss.

`AlarmEvent` is:

```swift
public struct AlarmEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var observedAt: Date
    public var host: String
    public var source: String
    public var name: String
    public var severity: AlarmSeverity
    public var metadata: [String: String]
}
```

`HashChainLedger.computeHash` HMACs the **canonical JSON encoding of the whole
event** together with the previous hash, using `.sortedKeys`. Verification
re-encodes each stored record and recomputes its hash.

The consequence:

> **Adding a non-optional field to `AlarmEvent` retroactively breaks verification
> of every existing ledger.** An old record decodes, the new field takes its
> default, the record re-encodes *with* that field present, the canonical JSON no
> longer matches what was signed, and the hash comparison fails.

Practical rules for any schema change:

1. **New fields must be `Optional` and default to `nil`.** Synthesized `Codable`
   omits nil optionals, so historical records re-encode byte-identically and keep
   verifying.
2. Never reorder or rename existing keys — `.sortedKeys` makes order
   deterministic, but renaming changes the signed bytes.
3. Richer-than-string payloads (the nested JSON the 2.0 inspector shows) must go
   into `metadata` as an encoded string, or arrive as a new optional field. There
   is no free path to a nested structure.
4. Anything that changes encoding needs an explicit ledger version and a
   migration story, tested against a ledger written by the previous version.

**Fields the 2.0 mockup implies that do not exist today:** per-event process
attribution, user/session identity, and structured payloads. Each is a schema
change governed by the rules above, and process attribution additionally needs
Tier C.

---

## 5. What this means

Five conclusions design should start from:

1. **The App Store build cannot see the most compelling events.** Failed logins,
   TCC prompts, USB, screen sharing — all Tier B. The App Store product is
   fundamentally "session and file activity"; the DMG product is "security
   telemetry". Marketing and UI must not blur them.
2. **Capability gaps are a permanent UI state, not an error.** The app already
   has the right mechanism — `SandboxEnvironment.unavailableReason` and the
   attributed-failure principle. Event sources should extend it, so an
   unavailable source reads as "not available in this build" rather than as
   silence.
3. **Actor attribution is Tier C.** Any design that answers "who did this" is
   gated behind an Apple approval that may not be granted.
4. **Schema growth is constrained by the hash chain.** Optional-only, additive,
   versioned.
5. **Volume, not variety, is the near-term design problem.** Even Tier A sources
   already produce thousands of events per day. Adding mount, user-switch, and
   display events increases density before it increases insight.

---

## Confidence

**Verified against source in this repository:** current event sources, the event
schema, and the hash-chain constraint.

**Verified externally, cited below:** the sandbox restriction on
`OSLogStore(.system)`, and Endpoint Security's exclusion from the Mac App Store.

**Inferred, needs a test on real hardware before being relied on:** sandbox
availability of `CGDisplayRegisterReconfigurationCallback`,
`IOPSNotificationCreateRunLoopSource`, and
`CGEventSourceSecondsSinceLastEventType`; whether CoreWLAN SSID access triggers a
Location prompt on the current macOS; and IOKit USB notification behaviour
unsandboxed.

## Sources

- [OSLogStore — Apple Developer Documentation](https://developer.apple.com/documentation/oslog/oslogstore)
- [OSLogStore on Monterey — Michael Tsai](https://mjtsai.com/blog/2021/12/10/oslogstore-on-monterey/)
- [Unsatisfied entitlements: com.apple.logging.local-store — Apple Developer Forums](https://developer.apple.com/forums/thread/666679)
- [Adding EndpointSecurity client entitlement — Apple Developer Forums](https://developer.apple.com/forums/thread/129007)
- [How to get endpoint-security distribution entitlements? — Apple Developer Forums](https://developer.apple.com/forums/thread/714768)
- [Endpoint Security In a macOS World — Huntress](https://www.huntress.com/blog/endpoint-security-in-a-macos-world)
