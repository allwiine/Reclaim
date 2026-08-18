# Reclaim — Architecture

This document explains how the app is put together and why. It should let a new contributor make a meaningful change within an hour.

## Overview

Reclaim is deliberately small and layered. The core insight is that a storage cleaner is **data-driven**: everything the app does is derived from a declarative catalogue of `CleanupTarget` values. Code handles the *mechanics* (resolving paths, sizing, deleting); the catalogue handles the *knowledge* (where tools waste space and how risky it is to intervene).

```
┌──────────────────────────────────────────────────────────┐
│ Reclaim (executable target — SwiftUI views only)         │
│                                                          │
│  ReclaimApp ── RootView ── Sidebar / Overview / Browser  │
└────────────────────┼─────────────────────────────────────┘
                     │ observes
┌────────────────────▼─────────────────────────────────────┐
│ ReclaimAppCore (library target — no UI imports)          │
│                                                          │
│  AppModel (@MainActor @Observable, owns all state,       │
│            injectable Scan/CleanExecutor seams)          │
│  CleanSummary · CleanHistory                             │
└────────────────────┼─────────────────────────────────────┘
                     │ calls into (off the main actor)
┌────────────────────▼─────────────────────────────────────┐
│ ReclaimKit (library target — no UI imports)              │
│                                                          │
│  Domain    CleanupTarget · TargetRegistry · SafetyLevel  │
│            CleanupStrategy · TargetStatus · ToolCategory │
│            ExclusionRegistry · ArtifactCatalog           │
│            DiscoveredProject                             │
│  Services  PathResolver → DiskSizer → TargetScanner      │
│            BreakdownSizer · VolumeSpace                  │
│            CleanupEngine (FileRemoving protocol)         │
│            FullDiskAccessProbe                           │
│            BulkDirectoryReader → ProjectDiscovery        │
│            GitActivityReader                             │
│  Support   Log (os.Logger)                               │
└──────────────────────────────────────────────────────────┘
```

**Dependency rule:** `Reclaim` imports `ReclaimAppCore` imports `ReclaimKit`; never the reverse. `ReclaimKit` imports Foundation, os, plus `Synchronization` (`Mutex` in `CleanupEngine`) and `Darwin` in exactly one file (`BulkDirectoryReader`); `ReclaimAppCore` adds Observation. Both compile without AppKit/SwiftUI, which is what makes the entire non-view codebase fast to unit-test.

## Data flow

1. **Scan.** `AppModel.scanAll()` marks every target `.scanning`, evaluates the `FullDiskAccessProbe`, and fans work out through a `withTaskGroup` bounded to 4 concurrent walks. Each child task runs `TargetScanner.scan(_:)`:
   `pathPatterns` → `PathResolver` (tilde + glob expansion, drops non-existent paths) → a **cleanup-path snapshot** (for `.removeContents`, the directories' children at this moment) → `DiskSizer` (allocated-size walk of the snapshot; unreadable entries are counted, an unreadable root fails the target) → a `TargetStatus`. Dev-folder discovery runs in the same pass when folders are configured: a single-pass `getattrlistbulk(2)` walk per root that discovers projects, tracks newest mtimes, and sizes artifacts, reading each directory exactly once and no file contents except the reflog tail.
2. **Display.** Statuses land in `AppModel.statuses`; every view derives from that dictionary plus the registry. There is no duplicated state. A scan stopped early is flagged (`lastScanWasComplete == false`) and the Overview says so; missing Full Disk Access surfaces as a banner.
3. **Select.** The user ticks targets. Selectability is computed (`isSelectable`): only cleanable strategies with a non-zero measurement (or command targets whose availability probe passes) can be ticked.
4. **Clean.** After an explicit confirmation (which also warns if a related app is running), `cleanSelected()` runs the `CleanupEngine` per target — sequentially, cancellable between targets — passing **the scan-time cleanup snapshot**. The engine never lists directories itself, so nothing created after the scan can be deleted. Disposal is Trash or permanent delete depending on Settings.
5. **Verify.** Each cleaned target is immediately re-scanned; reclaimed space is reported as *measured before − measured after*, never assumed. The summary reports items actually removed, and counts a target as cleaned only when at least one removal succeeded.

## Concurrency model

The package compiles in Swift 6 language mode (strict data-race safety). Isolation is **explicit**, not defaulted:

- `AppModel` is `@MainActor @Observable`. All UI-visible state lives there.
- Everything in `ReclaimKit` is nonisolated, `Sendable`, and synchronous. Services are stateless structs — cheap to create per call, trivially thread-safe.
- Blocking filesystem work reaches the background two ways:
  - scan fan-out: `group.addTask { … scan(target) }` — child tasks run nonisolated on the global executor;
  - single operations: the `nonisolated static func offMain` trampoline in `AppModel`.
- The scan group is **width-limited** (4) because directory walking is disk-bound: more parallelism gains nothing and would occupy cooperative-pool threads with blocking I/O.
- Cancellation is cooperative: `DiskSizer` calls `Task.checkCancellation()` every 512 entries, so the Stop button reacts promptly even mid-walk. A cancelled scan keeps completed measurements but is flagged partial. A clean pass checks cancellation between targets — the in-flight target always finishes, so nothing is left half-cleaned.

**Why not `.defaultIsolation(MainActor.self)`?** Swift 6.2's "single-threaded by default" mode is great for apps that are mostly UI. Reclaim has a genuine concurrency boundary at its heart — scans must never touch the main thread — and annotating that boundary explicitly (`@MainActor` above it, plain `Sendable` code below it) documents the design better than a module-wide default plus scattered opt-outs. If the default is ever adopted, the background helpers in `AppModel` should gain `@concurrent` to preserve their off-main execution.

## Error handling

- **Scanning** never throws to the UI: failures become `TargetStatus.failed(message:)`, rendered inline per row with a Full-Disk-Access hint. Unreadable entries inside a walk are skipped but **counted** (`DiskMeasurement.inaccessibleItems`, shown as "N unreadable"); an unreadable root fails the target instead of measuring zero. A global `FullDiskAccessProbe` verdict drives an Overview banner.
- **Cleaning** is best-effort per item: `CleanOutcome` accumulates `CleanFailure`s so one locked file doesn't abort a pass. Failures surface in the summary alert, which distinguishes cleaned targets (≥1 removal) from failed ones.
- **Manual strategies** are triple-guarded: not selectable in the UI, refused by the engine, and covered by tests.

## Testing strategy

Swift Testing (`swift test`), three test targets:

`Tests/ReclaimKitTests`:

- **RegistryTests / ExclusionRegistryTests** — the catalogue's contract: unique ids, pattern shape, pathless ⇒ command, related-app declarations, and the guarantee that structurally excluded paths (Claude Code auth/settings/plugins among them) can never be registered. This is what makes "just add a struct" safe.
- **PathResolverTests / DiskSizerTests / BreakdownSizerTests / VolumeSpaceTests / TargetScannerTests / FullDiskAccessProbeTests** — behavior against real temporary directories via a `withTemporaryDirectory` fixture, including chmod-based permission fixtures.
- **BulkDirectoryReaderTests / ProjectDiscoveryTests / GitActivityReaderTests / ArtifactCatalogTests** — dev-folder discovery: the bulk directory walk, project detection, git activity reading, and the artifact catalogue's conventions.
- **CleanupEngineTests / CleanupEngineRemoveTests** — engine logic against a `Mutex`-protected mock `FileRemoving`, so no test can ever touch the real Trash. The protocol seam exists precisely for this. Command execution runs real (harmless) processes, including a stderr-flood regression test.
- **LocalizationTests** — parity and coverage of the Kit's `{en,nb}.lproj` catalogues.

`Tests/ReclaimAppCoreTests`:

- **AppModelTests / AppModelProjectTests** — scan lifecycle (including cancellation → partial), selection rules, cleanup-path plumbing, summary math, disposal snapshotting, dev-folder project orchestration — all against stubbed `ScanExecutor`/`CleanExecutor` closures.
- **CleanHistoryTests** — the persisted clean-history store.
- **LocalizationTests** — parity and coverage of the app-core catalogues.

`Tests/LocalizationLintTests`:

- **LocalizationLintTests** — a source-tree lint: every `localized(…)` reference exists in both of its module's catalogues, en/nb key sets are identical, and the view layer never uses literal-key SwiftUI inits (`Text("some.key")`).

UI is kept logic-free (views derive everything from `AppModel`), so model-level tests give high coverage without UI tests; add XCUITest via the XcodeGen project if flows grow.

## Extension points

| To add… | Touch… |
| --- | --- |
| A new cleanable tool | One `CleanupTarget` in `TargetRegistry` + its `target.<id>.name`/`.summary` keys in both Kit catalogues |
| A protected sibling path (credentials, settings) | One `StructuralExclusion` in `ExclusionRegistry` + reason keys in both Kit catalogues |
| A running-app warning for it | `relatedAppBundleIDs` on the target |
| A command tool whose presence needs proving | `availabilityProbePattern` on its `CommandSpec` |
| A new category | One case in `ToolCategory` (title + SF Symbol) + its `category.<id>.title` keys in both Kit catalogues |
| A new cleanup mechanism | One case in `CleanupStrategy` + one `switch` arm in `CleanupEngine`, plus the `TargetScanner.cleanupPaths(for:)` and `CleanupStrategy.isCleanable` switches |
| A different disposal (e.g. secure erase) | One case in `Disposal` + `CleanupEngine.dispose` |
| A new project artifact kind | One `ArtifactKind` in `ArtifactCatalog` + its name keys in both Kit catalogues |
| Scheduled scans, menu-bar mode, per-item drill-down | New UI over the same `AppModel`/`ReclaimKit` APIs |

## Deliberate decisions

- **Trash-first disposal.** A cleaner's worst failure mode is deleting something needed. `FileManager.trashItem` gives free undo; permanent deletion is a Settings opt-in.
- **Clean the scan-time snapshot, not re-resolved or re-listed paths.** Globs could match new items between scan and clean, and a directory listed at clean time could contain children created after the scan. The scanner therefore snapshots the exact deletion set (children for `.removeContents`), measures that snapshot, and the engine disposes only those URLs — the user must only ever lose what they saw.
- **`removeContents` over `removePaths` for caches.** Many tools assume their cache root exists; emptying it is the polite operation.
- **Allocated size, not logical size.** Sparse files and APFS clones make logical size a lie; allocated size is what deletion actually frees.
- **`import Darwin` is allowed in exactly one file** (`BulkDirectoryReader.swift`) because `getattrlistbulk` has no Foundation equivalent; everything else in ReclaimKit stays Foundation + os, plus `Synchronization` for `CleanupEngine`'s `Mutex`.
- **No sandbox.** The product's job is reading arbitrary cache locations under `$HOME`; sandboxing would reduce it to a folder-picker ritual. Consequence: no App Store, hardened runtime + notarization for direct distribution.
- **SPM-first project.** `open Package.swift` runs the app with zero setup; XcodeGen (`project.yml`) is the additive path to a distributable bundle. No `.xcodeproj` churn in code review.
