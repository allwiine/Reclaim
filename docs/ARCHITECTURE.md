# Reclaim — Architecture

This document explains how the app is put together and why. It should let a new contributor make a meaningful change within an hour.

## Overview

Reclaim is deliberately small and layered. The core insight is that a storage cleaner is **data-driven**: everything the app does is derived from a declarative catalogue of `CleanupTarget` values. Code handles the *mechanics* (resolving paths, sizing, deleting); the catalogue handles the *knowledge* (where tools waste space and how risky it is to intervene).

```
┌──────────────────────────────────────────────────────────┐
│ Reclaim (executable target — SwiftUI, @MainActor)        │
│                                                          │
│  ReclaimApp ── RootView ── Sidebar / Overview / Category │
│                    │                                     │
│                AppModel  (@Observable, owns all state)   │
└────────────────────┼─────────────────────────────────────┘
                     │ calls into (off the main actor)
┌────────────────────▼─────────────────────────────────────┐
│ ReclaimKit (library target — no UI imports)              │
│                                                          │
│  Domain    CleanupTarget · TargetRegistry · SafetyLevel  │
│            CleanupStrategy · TargetStatus                │
│  Services  PathResolver → DiskSizer → TargetScanner      │
│            CleanupEngine (FileRemoving protocol)         │
│  Support   Log (os.Logger)                               │
└──────────────────────────────────────────────────────────┘
```

**Dependency rule:** `Reclaim` imports `ReclaimKit`; never the reverse. `ReclaimKit` imports only Foundation and os — it compiles without AppKit/SwiftUI, which is what makes it fast to unit-test.

## Data flow

1. **Scan.** `AppModel.scanAll()` marks every target `.scanning` and fans work out through a `withTaskGroup` bounded to 4 concurrent walks. Each child task runs `TargetScanner.scan(_:)`:
   `pathPatterns` → `PathResolver` (tilde + glob expansion, drops non-existent paths) → `DiskSizer` (allocated-size walk) → a `TargetStatus`.
2. **Display.** Statuses land in `AppModel.statuses`; every view derives from that dictionary plus the registry. There is no duplicated state.
3. **Select.** The user ticks targets. Selectability is computed (`isSelectable`): only cleanable strategies with a non-zero measurement (or command targets) can be ticked.
4. **Clean.** After an explicit confirmation, `cleanSelected()` runs the `CleanupEngine` per target — sequentially, for predictability — passing **the exact URLs the scan resolved**. The engine disposes via Trash or permanent delete depending on Settings.
5. **Verify.** Each cleaned target is immediately re-scanned; reclaimed space is reported as *measured before − measured after*, never assumed.

## Concurrency model

The package compiles in Swift 6 language mode (strict data-race safety). Isolation is **explicit**, not defaulted:

- `AppModel` is `@MainActor @Observable`. All UI-visible state lives there.
- Everything in `ReclaimKit` is nonisolated, `Sendable`, and synchronous. Services are stateless structs — cheap to create per call, trivially thread-safe.
- Blocking filesystem work reaches the background two ways:
  - scan fan-out: `group.addTask { … TargetScanner().scan(target) }` — child tasks run nonisolated on the global executor;
  - single operations: `nonisolated static func` async helpers in `AppModel`.
- The scan group is **width-limited** (4) because directory walking is disk-bound: more parallelism gains nothing and would occupy cooperative-pool threads with blocking I/O.
- Cancellation is cooperative: `DiskSizer` calls `Task.checkCancellation()` every 512 entries, so the Stop button reacts promptly even mid-walk.

**Why not `.defaultIsolation(MainActor.self)`?** Swift 6.2's "single-threaded by default" mode is great for apps that are mostly UI. Reclaim has a genuine concurrency boundary at its heart — scans must never touch the main thread — and annotating that boundary explicitly (`@MainActor` above it, plain `Sendable` code below it) documents the design better than a module-wide default plus scattered opt-outs. If the default is ever adopted, the background helpers in `AppModel` should gain `@concurrent` to preserve their off-main execution.

## Error handling

- **Scanning** never throws to the UI: failures become `TargetStatus.failed(message:)`, rendered inline per row with a Full-Disk-Access hint. Unreadable entries inside a walk are skipped (enumerator error handler) rather than failing the whole target.
- **Cleaning** is best-effort per item: `CleanOutcome` accumulates `CleanFailure`s so one locked file doesn't abort a pass. Failures surface in the summary alert.
- **Manual strategies** are triple-guarded: not selectable in the UI, refused by the engine, and covered by tests.

## Testing strategy

`ReclaimKitTests` (Swift Testing, `swift test`):

- **RegistryTests** — the catalogue's contract: unique ids, pattern shape, pathless ⇒ command, and the guarantee that Claude Code auth/settings/plugins can never be registered. This is what makes "just add a struct" safe.
- **PathResolverTests / DiskSizerTests** — behavior against real temporary directories via a `withTemporaryDirectory` fixture.
- **CleanupEngineTests** — engine logic against a `Mutex`-protected mock `FileRemoving`, so no test can ever touch the real Trash. The protocol seam exists precisely for this.

UI is kept logic-free (views derive everything from `AppModel`), so model-level tests give high coverage without UI tests; add XCUITest via the XcodeGen project if flows grow.

## Extension points

| To add… | Touch… |
| --- | --- |
| A new cleanable tool | One `CleanupTarget` in `TargetRegistry` |
| A new category | One case in `ToolCategory` (title + SF Symbol) |
| A new cleanup mechanism | One case in `CleanupStrategy` + one `switch` arm in `CleanupEngine` |
| A different disposal (e.g. secure erase) | One case in `Disposal` + `CleanupEngine.dispose` |
| Scheduled scans, menu-bar mode, per-item drill-down | New UI over the same `AppModel`/`ReclaimKit` APIs |

## Deliberate decisions

- **Trash-first disposal.** A cleaner's worst failure mode is deleting something needed. `FileManager.trashItem` gives free undo; permanent deletion is a Settings opt-in.
- **Clean scan-time paths, not re-resolved ones.** Globs could match new items between scan and clean; the user must only ever lose what they saw.
- **`removeContents` over `removePaths` for caches.** Many tools assume their cache root exists; emptying it is the polite operation.
- **Allocated size, not logical size.** Sparse files and APFS clones make logical size a lie; allocated size is what deletion actually frees.
- **No sandbox.** The product's job is reading arbitrary cache locations under `$HOME`; sandboxing would reduce it to a folder-picker ritual. Consequence: no App Store, hardened runtime + notarization for direct distribution.
- **SPM-first project.** `open Package.swift` runs the app with zero setup; XcodeGen (`project.yml`) is the additive path to a distributable bundle. No `.xcodeproj` churn in code review.
