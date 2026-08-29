# Architecture 2.0 — Proposal

Not a migration plan yet. This is the shape being argued for, the reasoning, and
the places where the preferred conventions have real trade-offs worth deciding
deliberately.

## Why restructure

The stated motivation is auditability: someone should be able to read this code
and satisfy themselves it does what it claims. That motivation is worth taking
literally, because it implies something sharper than "tidier code".

**Auditability is not uniform.** Nobody audits 200 files evenly. An auditor
checks the claim: *events are appended to a hash chain that cannot be silently
altered*. Everything else — menus, layout, filter pills — is not what they came
for. So the goal is not to distribute 143 files more evenly. It is to make the
part that carries the security claim **small, isolated, and provably unable to
depend on anything else**.

That gives three concrete design rules:

1. The ledger and its crypto live in a module with no dependencies beyond
   Foundation and CryptoKit, small enough to read in one sitting.
2. Dependency direction is enforced by the compiler, not by convention. An
   auditor should be able to observe that the ledger *cannot* import the UI,
   because the module graph forbids it.
3. Anything that can reach the network, the filesystem outside the container, or
   the user's data is in a named module an auditor can enumerate.

Current state works against all three: `MythLogCore` is 41 files in a **flat
directory** mixing ledger, config, event sources, notifiers, Telegram, and
LaunchAgent management; `MythLogAppSupport` is **143 files** in one module.

## Proposed module graph

Arrows point in the only permitted direction of dependency.

```
                    ┌──────────────────┐
                    │ MythLogPrimitives│  values only: AlarmEvent, severity,
                    └──────────────────┘  CanonicalJSON, hex. No I/O at all.
                             ▲
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────────────┐   ┌────────────────┐   ┌────────────────────┐
│ MythLogLedger │   │ MythLogConfig  │   │  MythLogPlatform   │
│ chain, HMAC,  │   │ config schema, │   │ sandbox detection, │
│ lock, anchor, │   │ validation,    │   │ container, paths,  │
│ proof export  │   │ install paths  │   │ entitlements       │
└───────────────┘   └────────────────┘   └────────────────────┘
        ▲                    ▲                    ▲
        └────────────────────┼────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
┌───────────────┐   ┌────────────────┐   ┌────────────────────┐
│MythLogSources │   │MythLogDelivery │   │ MythLogLifecycle   │
│ session, file,│   │ notifiers,     │   │ SMAppService,      │
│ unified log,  │   │ Telegram,      │   │ LaunchAgent,       │
│ spool         │   │ checkpoint     │   │ install/uninstall  │
└───────────────┘   └────────────────┘   └────────────────────┘
                             ▲
                    ┌────────────────┐
                    │ MythLogRuntime │  pipeline, rules, heartbeat,
                    └────────────────┘  agent status
                             ▲
        ┌────────────────────┴────────────────────┐
┌───────────────────┐                   ┌────────────────────┐
│ MythLogDesign     │                   │  MythLogFeatures   │
│ tokens, primitives│◀──────────────────│ Timeline, Inspector│
│ no app knowledge  │                   │ Filters, Health    │
└───────────────────┘                   └────────────────────┘
                                                 ▲
                                        ┌────────────────────┐
                                        │  MythLogAppShell   │  AppKit shell,
                                        └────────────────────┘  menus, window
```

Executables (`MythLogApp`, `mythlog-agent`, `mythlogctl`, `mythlog-probe`) stay
as thin entry points, as they already are.

**The load-bearing property:** `MythLogLedger` depends only on
`MythLogPrimitives`. It cannot import config, sources, delivery, or UI. That is
the module an auditor reads, and the compiler guarantees its isolation.

**Why `MythLogPlatform` is separate:** sandbox detection, container resolution,
and entitlement reading are consulted from nearly everywhere and are the source
of the class of bug that shipped in 1.0.0 — the viewer reading a different
container than the recorder wrote to. Making it one module with one resolution
point removes the possibility of a second, divergent implementation.

**Why `MythLogDelivery` is separate and named:** it is the only module that can
reach the network. "Which code can talk to the internet?" becomes a one-word
answer.

### Sizing

| Module | Rough files | Notes |
| --- | --- | --- |
| MythLogPrimitives | 6–8 | Should stay tiny |
| MythLogLedger | 8–10 | The audit target |
| MythLogConfig | 6–8 | |
| MythLogPlatform | 5–6 | |
| MythLogSources | 8–10 | Grows with each new event source |
| MythLogDelivery | 6–8 | |
| MythLogLifecycle | 10–12 | Currently the LaunchAgent* cluster |
| MythLogRuntime | 6–8 | |
| MythLogDesign | 20–25 | From SharedUI |
| MythLogFeatures | 90–110 | Still the largest; folder-divided internally |
| MythLogAppShell | 25 | |

`MythLogFeatures` stays big because feature UI legitimately is big. If it needs
splitting later, the seam is per-feature modules (`…Timeline`, `…Inspector`),
which is a cheap follow-up once the layer boundaries exist.

## Folder conventions inside a module

```
MythLogFeatures/
  Timeline/
    TimelineScreen.swift
    TimelineScreen+ViewModel.swift
    TimelineScreen+Actions.swift
    Zoom/
      TimelineZoom.swift
      TimelineZoom+Levels.swift
    Canvas/
      …
  Inspector/
  Filters/
```

Rules:

- One primary type per file; the file is named for it.
- A folder gets subfolders once it exceeds ~15 files.
- No `Utils`, `Helpers`, `Common`, or `Misc` folder — those become dumping
  grounds and destroy the reasoning the structure exists to provide. If
  something has no home, that is information about a missing concept.

## Naming conventions

The preferred style, formalised:

**Nest types inside their owner.**

```swift
// TimelineScreen.swift
struct TimelineScreen: View { … }

// TimelineScreen+ViewModel.swift
extension TimelineScreen {
    @MainActor final class ViewModel: ObservableObject { … }
}
```

Referred to as `TimelineScreen.ViewModel`, never `TimelineScreenViewModel`.

**File names mirror the type path.** `Owner.swift` for the owner,
`Owner+Aspect.swift` for each extension. This sorts adjacently in Xcode and
makes related files visually contiguous, which is the point.

This convention **already exists here** — `TimelineStore+DerivedState.swift`,
`TimelineStore+Filters.swift`, `AlarmSeverity+TimelineUI.swift`, and 12 others.
So this is formalising and extending established practice, not importing a new
idea.

### Where nesting has real costs

Worth knowing before committing:

- **Generic owners.** A type nested in a generic type inherits its generic
  parameters. If a view becomes generic later, its nested `ViewModel` becomes
  `SomeView<T>.ViewModel` and can no longer be referenced independently.
  Recommendation: nest inside concrete views only; if a view is generic, hoist
  the model out.
- **Search friction.** Twenty types all named `ViewModel` means searching the
  symbol name is useless; navigation must go through the owner. In practice this
  is fine in Xcode but is a real change in habit.
- **Swift 6 concurrency.** Nested view models must be explicitly `@MainActor`.
  Nesting does not inherit isolation from the enclosing view.
- **Cross-module access.** A nested type's access level is capped by its owner.
  A `public` nested type inside an `internal` view is not visible outside the
  module — easy to trip over when splitting modules and nesting at the same
  time.

## The ViewModel question — decide this deliberately

This is the one place the preferred convention and the current architecture
genuinely conflict, and it should be a decision rather than a drift.

Today MythLog uses a **single shared store**: `TimelineStore`, with derived state
computed in `TimelineStore+DerivedState.swift`, and `@EnvironmentObject` confined
to `TimelineScreen.swift` by an enforced lint gate
(`scripts/check-swiftui-store-boundaries.sh`). Leaf views receive plain values.

Per-view `View.ViewModel` types are a different model. Both are defensible, but
mixing them arbitrarily is not.

**The risk specific to this app:** every surface — timeline, list, inspector,
filters, integrity banner — is a projection of *one* dataset, the ledger. If each
view's ViewModel loads and derives independently, the same ledger gets read and
derived several times, the derivations can disagree, and the timeline and the
list can show different truths. For an app whose entire claim is a consistent,
trustworthy record, that is a worse failure than verbosity.

**Recommended shape:**

- One `LedgerStore` (or several domain stores) owns loading, watching, and the
  expensive shared derivations. Single source of truth.
- Each screen gets a `Screen.ViewModel` that **projects** from the store —
  presentation state, selection, formatting, local UI concerns. It does not load
  or re-derive shared data.
- Leaf views stay value-driven, as they already are.

That keeps the naming convention, adds per-screen SRP, and preserves the
single-source-of-truth property. The existing store-boundary lint gate would need
its rule updated rather than removed — ViewModels may read the store; views may
not.

## Migration

Not a rewrite. The 2.0 UI work is the opportunity, and the split should happen
underneath it rather than as a separate big-bang refactor.

1. **Split `MythLogCore` first.** It is 41 flat files and has the clearest seams.
   `MythLogPrimitives` → `MythLogLedger` → `MythLogPlatform` → `MythLogConfig`.
   Do it before any 2.0 UI work so new code lands on the right foundation. Purely
   mechanical: move files, add `public`, fix imports. No behaviour change, so the
   existing test suite is the safety net.
2. **Extract `MythLogDesign`** from `SharedUI`. Also mechanical, and it makes the
   2.0 component inventory land somewhere principled.
3. **Build 2.0 features into `MythLogFeatures`** with the new conventions, rather
   than converting the existing 143 files up front.
4. **Convert older UI opportunistically**, when a file is being touched anyway.
5. **`MythLogLifecycle` last** — it is the most sandbox-sensitive code and the
   least urgent to move.

Each step is independently shippable and independently revertible.

## Enforcement

This repository already gates architecture with scripts rather than trusting
convention (`check-swiftui-store-boundaries.sh`,
`check-container-path-resolution.sh`, and others). The same approach should carry
the new rules:

- Module dependency direction — the compiler enforces this for free once the
  split exists. This is the main argument for real modules over folders.
- No `Utils`/`Helpers`/`Common` folder names.
- File name matches its primary type, and `Owner+Aspect.swift` matches an
  `extension Owner`.
- ViewModels are `@MainActor` and nested.

## Open questions

1. **Who is the audience for auditability?** The store listing currently claims
   users can read the source, while the repository is private and the licence is
   all-rights-reserved. Published audit, read-only source release, reproducible
   builds, or drop the claim — this decision changes how much the module boundary
   argument is worth.
2. **How many modules is too many?** The graph above is eleven. Fewer, larger
   modules build faster and demand less `public` annotation; more, smaller ones
   give stronger guarantees. The ledger boundary is worth it unconditionally; the
   rest is a judgement call.
3. **Store-per-domain or one store?** If 2.0 adds materially more shared derived
   state, one store may become the bottleneck, and splitting by domain (ledger,
   health, filters) may be better than by screen.
