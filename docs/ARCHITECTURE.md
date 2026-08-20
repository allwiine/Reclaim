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
│  AppModel  composition root (@MainActor @Observable);    │
│            builds the sub-models, injects `Executors`    │
│  Models    SettingsStore · ActivityModel ·               │
│            TargetResultsModel · BreakdownModel ·         │
│            SelectionModel · ProjectsModel ·              │
│            ScanCoordinator · CleanCoordinator ·          │
│            HistoryModel                                  │
│  Support   CleanSummary · CleanHistory                   │
└────────────────────┼─────────────────────────────────────┘
                     │ calls into (off the main actor)
┌────────────────────▼─────────────────────────────────────┐
│ ReclaimKit (library target — no UI imports)              │
│                                                          │
│  Domain    CleanupTarget · TargetRegistry · SafetyLevel  │
│            CleanupStrategy · TargetStatus · ToolCategory │
│            ExclusionRegistry · ArtifactCatalog           │
│            DiscoveredProject · CatalogueLoader           │
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

## The catalogue

The declarative catalogue named above is not Swift — it is JSON. `Sources/ReclaimKit/Catalogue/` holds one manifest per target (`<category>/<id>.json`) and one per structural exclusion (`exclusions/<id>.json`), plus `exclusions/reviewed-safe-roots.json` and two JSON Schemas. `Package.swift` bundles the directory with `.copy("Catalogue")` so its layout survives into `Bundle.module` unmodified (the neighboring `Resources` directory keeps `.process`, since those are compiled `.lproj` tables, not passthrough files).

`Sources/ReclaimKit/Domain/CatalogueManifest.swift` defines the wire format — `TargetManifest`, `ExclusionManifest`, and a `localizedText` shape requiring every `CatalogueLocales.supported` language — and maps each manifest onto the existing domain types (`CleanupTarget`, `StructuralExclusion`). `CatalogueLoader` (`Sources/ReclaimKit/Domain/CatalogueLoader.swift`) does the materializing: it enumerates every `.json` file under the category directories and under `exclusions/` (skipping `schema/`, `README.md`, and `reviewed-safe-roots.json` itself), decodes each one, and resolves its localized text objects to plain `String`s at load time using `Bundle.module`'s preferred localization with English fallback — so `CleanupTarget` and `StructuralExclusion` keep the same resolved-`String` fields they always had, and nothing downstream of the registries changed. Loading happens once, lazily, via `static let` properties on the loader.

The loader exposes two policies over the same decoding logic. **Strict** loading (`loadTargets`, `loadExclusions`, `loadReviewedSafeRoots`) throws on the first invalid file; `CatalogueConventionTests` and `CatalogueLoaderTests` call it directly, so a malformed manifest fails CI rather than shipping. **Lenient** loading (`targetsSkippingFailures` and friends) backs `TargetRegistry.all` and `ExclusionRegistry.all` at runtime: a decode failure is impossible unless the app bundle itself is corrupt, so rather than crash, the loader logs an `os_log` fault naming the file and skips it. `TargetRegistry` and `ExclusionRegistry` themselves shrank to thin façades — `TargetRegistry.all` is now just `CatalogueLoader.bundledTargets` — so `AppModel`, `TargetScanner`, `CleanupEngine`, every view, and their tests are untouched by the catalogue's existence.

This shape is deliberate as the project's primary contribution surface: a new tool means one new file, reviewable at a glance, with no shared Swift file to merge-conflict against; the `$schema` reference gives contributors editor autocomplete and inline validation before they ever run `swift test`; and `swift test` — not reviewer vigilance — is what actually enforces shape, uniqueness, and the exclusion rules. See `docs/CATALOGUE.md` for the contributor-facing guide.

## Data flow

1. **Scan.** `model.scanner.scanAll()` (`ScanCoordinator`) marks every target `.scanning`, evaluates the `FullDiskAccessProbe`, and fans work out through a `withTaskGroup` bounded to 4 concurrent walks. Each child task runs `TargetScanner.scan(_:)`:
   `pathPatterns` → `PathResolver` (tilde + glob expansion, drops non-existent paths) → a **cleanup-path snapshot** (for `.removeContents`, the directories' children at this moment) → `DiskSizer` (allocated-size walk of the snapshot; unreadable entries are counted, an unreadable root fails the target) → a `TargetStatus`. Dev-folder discovery runs in the same pass when folders are configured (`ProjectsModel`, via `ScanCoordinator`): a single-pass `getattrlistbulk(2)` walk per root that discovers projects, tracks newest mtimes, and sizes artifacts, reading each directory exactly once and no file contents except the reflog tail.
2. **Display.** Statuses land in `model.results.statuses` (`TargetResultsModel`); every view derives from that dictionary plus the registry. There is no duplicated state. A scan stopped early is flagged (`lastScanWasComplete == false`) and the Overview says so; missing Full Disk Access surfaces as a banner.
3. **Select.** The user ticks targets, tracked by `model.selection` (`SelectionModel`). Selectability is computed (`isSelectable`): only cleanable strategies with a non-zero measurement (or command targets whose availability probe passes) can be ticked.
4. **Clean.** After an explicit confirmation (which also warns if a related app is running), `model.cleaner.cleanSelected(scope:)` (`CleanCoordinator`) runs the `CleanupEngine` per target — sequentially, cancellable between targets — passing **the scan-time cleanup snapshot**. The engine never lists directories itself, so nothing created after the scan can be deleted. Disposal is Trash or permanent delete depending on Settings.
5. **Verify.** Each cleaned target is immediately re-scanned; reclaimed space is reported as *measured before − measured after*, never assumed. The summary reports items actually removed, and counts a target as cleaned only when at least one removal succeeded.

This flow has one dependency cycle that would otherwise exist: `SelectionModel` needs to know whether a pass is running (selectability changes mid-scan and mid-clean), while `ScanCoordinator`/`CleanCoordinator` need to know the current selection to act on it. `ActivityModel` (`model.activity`) breaks the cycle by owning only the "what is the app doing right now" state — the pass flags (`isScanning`, `isCleaning`, `isCancellingScan`, `isCancellingClean`, `isReviewingSelection`) and live progress (`scanProgress`, `cleanProgress`, `lastCleanSummary`). The coordinators write it; `SelectionModel`, `ProjectsModel`, and the UI only read it, so no sub-model needs a direct reference to a coordinator.

## Concurrency model

The package compiles in Swift 6 language mode (strict data-race safety). Isolation follows Swift 6.2's "approachable concurrency": the app-facing targets default every unannotated declaration to `MainActor`, and the one real concurrency boundary — filesystem work must never touch the main thread — is marked explicitly from the other side, at each blocking call.

| Target(s) | Swift settings | Default isolation |
| --- | --- | --- |
| `ReclaimKit`, `ReclaimKitTests` | `sharedSwiftSettings` | nonisolated — the Kit *is* the off-main work |
| `ReclaimAppCore`, `ReclaimAppCoreTests` | `mainActorByDefault` | `MainActor` |
| `Reclaim`, `LocalizationLintTests` | `mainActorByDefault` | `MainActor` |

- `AppModel` and each of the nine sub-models it composes (`settings`, `activity`, `results`, `breakdowns`, `selection`, `projects`, `scanner`, `cleaner`, `history`) are `@Observable` and MainActor-isolated by `ReclaimAppCore`'s module default — no explicit `@MainActor` needed. UI-visible state lives on whichever sub-model owns it, never duplicated onto `AppModel` itself.
- Everything in `ReclaimKit` is nonisolated, `Sendable`, and synchronous by its own module default. Services are stateless structs — cheap to create per call, trivially thread-safe.
- Blocking filesystem work crosses the boundary through 14 named `@concurrent` workers — one per blocking call, each doing nothing but run its injected `Executors` closure (or a pure pin helper) off the main actor: `probeAccess` (`ScanCoordinator.swift`); `scanWorker` / `rootWorker` (`ScanCoordinator+Passes.swift`); `partitionWorker`, `cleanWorker`, `rescanWorker`, `pinWorker`, `removeWorker`, `goneWorker`, `rediscoverWorker`, `volumeWorker` (`CleanCoordinator+Workers.swift`); `computeEntries` (`BreakdownModel.swift`); `persist` (`HistoryModel.swift`); `measure` (`TargetResultsModel.swift`).
- The scan group is **width-limited** (4) because directory walking is disk-bound: more parallelism gains nothing and would occupy cooperative-pool threads with blocking I/O.
- Cancellation is cooperative: `DiskSizer` calls `Task.checkCancellation()` every 512 entries, so the Stop button reacts promptly even mid-walk. A cancelled scan keeps completed measurements but is flagged partial. A clean pass checks cancellation between targets — the in-flight target always finishes, so nothing is left half-cleaned.
- `ScanCoordinator+Passes.swift`'s `runScan(of:)` and `runProjectScan()` each nest two local functions (`publishProgress`, `startNext`) inside a `withTaskGroup` operation closure and mark them `@MainActor` explicitly. That is not a leftover: `.defaultIsolation` does not reach a local function nested inside a closure body — only one nested directly in a function body does — so a plain declaration would be nonisolated; `publishProgress` needs `@MainActor` because it reads and writes `activity.scanProgress` (and, in the first pass, `projects.devRoots`). Both nested-function pairs are load-bearing and permanent.

**`@concurrent` is a checked guarantee, and for most workers it is also the mechanism.** Twelve of the fourteen workers above are awaited from inside an unstructured `Task { … }` started by a MainActor method (`ScanCoordinator.scanAll`, `startPass(jobs:artifactJobs:)` in `CleanCoordinator+Pass.swift`, `BreakdownModel.load(for:)`, `HistoryModel.persistHistory`, `TargetResultsModel.refreshVolumeSpace`). An unstructured `Task` inherits the isolation of the context that spawned it, so for these twelve, `@concurrent` genuinely is what keeps the work off the main actor — under `NonisolatedNonsendingByDefault`, a plain `nonisolated` callee would stay right there on `MainActor`. The remaining two, `scanWorker` and `rootWorker`, run as `group.addTask { … }` children of the width-limited `withTaskGroup` in `runScan(of:)` / `runProjectScan()`. Task-group child closures are already nonisolated regardless of the enclosing method's default isolation, so today `@concurrent` is *not* the reason those two stay off-main — a temporary downgrade to plain `nonisolated` behaved identically. It is kept anyway as the explicit, compiler-checked promise that survives a future change to that closure-inheritance behavior, rather than the unstated assumption it would otherwise be. `IsolationTests` (`Tests/ReclaimAppCoreTests/IsolationTests.swift`, 4 tests) is what makes both claims checked instead of asserted: it pins all seven `Executors` closures (`scan`, `clean`, `breakdown`, `projectScan`, `artifactClean`, `fullDiskAccess`, `volume`) to off-main execution via a `ThreadRecorder` that records `Thread.isMainThread` inside each stub, and during this migration downgrading a `Task`-launched worker reliably broke the suite while downgrading a task-group worker reliably did not — exactly the asymmetry above.

The app target has one deliberate exception to "blocking work gets `@concurrent`": `TrashService.emptyTrash()` (`Sources/Reclaim/App/TrashService.swift`) hands its blocking `osascript` call to a raw `DispatchQueue.global()` thread rather than the Swift-concurrency executor pool, so a slow Finder can't starve the cooperative threads a scan or clean pass is using. The function underneath is `nonisolated`, not `@concurrent`, because `@concurrent` would move it onto the very concurrent executor it was built to avoid.

**Why the stance flipped.** The original design kept isolation fully explicit — `@MainActor` on UI/state, `nonisolated` on workers — and deliberately skipped `.defaultIsolation(MainActor.self)`, reasoning that a module-wide default plus scattered opt-outs would document the app's one real concurrency boundary worse than annotating it directly. In practice the explicit `@MainActor` had become pure repetition: nine `@Observable` model classes and every suite in `ReclaimAppCoreTests` carried it for no reason beyond "this is app state," while the actual boundary — which calls are blocking and must leave the main actor — was carried by an unenforced convention (a single `offMain` helper) a reviewer had to trust by reading call sites, not something the compiler checked. Naming every blocking call as its own `@concurrent` worker replaces that convention with one the compiler enforces per declaration; `.defaultIsolation(MainActor.self)` on the app-facing targets removes the redundant annotations for free. None of this was taken on faith: `IsolationTests` was written and made to pass *before* any isolation attribute changed, so every claim in this section — including the `addTask` asymmetry above — was verified by making an edit and watching a specific test fail, not by reasoning about what the settings file should imply.

## Error handling

- **Scanning** never throws to the UI: failures become `TargetStatus.failed(message:)`, rendered inline per row with a Full-Disk-Access hint. Unreadable entries inside a walk are skipped but **counted** (`DiskMeasurement.inaccessibleItems`, shown as "N unreadable"); an unreadable root fails the target instead of measuring zero. A global `FullDiskAccessProbe` verdict drives an Overview banner.
- **Cleaning** is best-effort per item: `CleanOutcome` accumulates `CleanFailure`s so one locked file doesn't abort a pass. Failures surface in the summary alert, which distinguishes cleaned targets (≥1 removal) from failed ones.
- **Manual strategies** are triple-guarded: not selectable in the UI, refused by the engine, and covered by tests.

## Testing strategy

Swift Testing (`swift test`), three test targets:

`Tests/ReclaimKitTests`:

- **RegistryTests / ExclusionRegistryTests** — the catalogue's contract: unique ids, pattern shape, pathless ⇒ command, related-app declarations, and the guarantee that structurally excluded paths (Claude Code auth/settings/plugins among them) can never be registered. This is what makes "just add a manifest" safe.
- **CatalogueManifestTests / CatalogueLoaderTests / CatalogueConventionTests** — the JSON layer underneath the above: manifest decoding and its mapping onto `CleanupTarget`/`StructuralExclusion` (including locale resolution and the strategy/companion-field mismatches the schema's `oneOf` is meant to catch), category-ordering and file-discovery behavior of `CatalogueLoader`, and authoring conventions the schema alone can't enforce — unknown keys, filename-equals-id, directory-equals-category, complete locales, and that every bundled manifest decodes strictly.
- **PathResolverTests / DiskSizerTests / BreakdownSizerTests / VolumeSpaceTests / TargetScannerTests / FullDiskAccessProbeTests** — behavior against real temporary directories via a `withTemporaryDirectory` fixture, including chmod-based permission fixtures.
- **BulkDirectoryReaderTests / ProjectDiscoveryTests / GitActivityReaderTests / ArtifactCatalogTests** — dev-folder discovery: the bulk directory walk, project detection, git activity reading, and the artifact catalogue's conventions.
- **CleanupEngineTests / CleanupEngineRemoveTests** — engine logic against a `Mutex`-protected mock `FileRemoving`, so no test can ever touch the real Trash. The protocol seam exists precisely for this. Command execution runs real (harmless) processes, including a stderr-flood regression test.
- **LocalizationTests** — parity and coverage of the Kit's `{en,nb}.lproj` catalogues.

`Tests/ReclaimAppCoreTests`:

- **SettingsStoreTests / SelectionTests / SelectionCherryPickingTests / TargetResultsTests / BreakdownTests** — one suite per sub-model: settings persistence, whole-target and cherry-picked selection rules, visibility and aggregates, breakdown caching.
- **ScanTests / CleanTests / CleanDryRunTests / CleanSafetyTests** — `ScanCoordinator`/`CleanCoordinator`: scan lifecycle (including cancellation → partial), the clean pass, dry-run projections, and scan-time safety pins.
- **ProjectsTests / ProjectDiscoveryTests / ProjectSelectionTests / ProjectCleanTests / ProjectCleanScopeTests** — `ProjectsModel`: dev-folder roots and discovery, artifact/project selection, and cleanup-path plumbing for dev-folder artifacts.
- **HistoryTests / CleanHistoryTests** — `HistoryModel` and the persisted clean-history store.
- **AppModelTests** — the composition root's cross-model overview aggregates (`selectedBytes`, `largestFindings(limit:)`), including dev-folder artifacts alongside registry targets. The termination handshake (`prepareForTermination()`) is exercised by the app lifecycle, not a unit test.
- **LocalizationTests** — parity and coverage of the app-core catalogues.

All of the above (aside from `LocalizationTests`) run against stubbed `Executors` (`Sources/ReclaimAppCore/Executors.swift`); only the safety-pin and history-persistence suites touch the filesystem, in throwaway temp directories.

`Tests/LocalizationLintTests`:

- **LocalizationLintTests** — a source-tree lint: every `localized(…)` reference exists in both of its module's catalogues, en/nb key sets are identical, and the view layer never uses literal-key SwiftUI inits (`Text("some.key")`).

UI is kept logic-free (views derive everything from `AppModel`'s sub-models), so model-level tests give high coverage without UI tests; add XCUITest via the XcodeGen project if flows grow.

## Extension points

| To add… | Touch… |
| --- | --- |
| A new cleanable tool | One target manifest under `Catalogue/<category>/<id>.json` (see `docs/CATALOGUE.md`) |
| A protected sibling path (credentials, settings) | One exclusion manifest under `Catalogue/exclusions/<id>.json`, or a rationale line in `Catalogue/exclusions/reviewed-safe-roots.json` |
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
