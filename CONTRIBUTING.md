# Contributing to Reclaim

Thanks for helping make Reclaim better! Contributions of every size are
welcome — new cleanup targets are the sweet spot (one struct plus its name
and summary strings in both language catalogues), and bug reports with good
reproduction steps are gold.

## Development setup

Requirements: macOS 15+, Xcode 26 (Swift 6.2 toolchain).

```bash
git clone https://github.com/allwiine/Reclaim.git
cd Reclaim
swift build            # build
swift run Reclaim      # run the app
swift test             # run the test suite
```

Xcode users can `open Package.swift` directly. Building a distributable
`.app` uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install
xcodegen && xcodegen`), but day-to-day work never needs it.

## Architecture ground rules

Reclaim is three targets with a strict dependency rule — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full rationale:

- `Reclaim` (SwiftUI views) → `ReclaimAppCore` (UI-free app state) →
  `ReclaimKit` (core library). Never the reverse.
- `ReclaimKit` imports Foundation, os, plus `Synchronization` (`Mutex` in
  `CleanupEngine`) and `Darwin` in exactly one file (`BulkDirectoryReader`);
  `ReclaimAppCore` adds Observation. Neither may import AppKit or SwiftUI —
  that keeps them unit-testable.
- Views are logic-free: everything derives from `AppModel` state plus the
  target registry. Don't add duplicated state to views.
- Swift 6 strict concurrency with explicit isolation. UI state is
  `@MainActor`; everything in `ReclaimKit` is nonisolated, `Sendable`,
  synchronous, stateless structs. Filesystem work stays off the main actor.

## Adding a cleanup target

The most valuable contribution! One `CleanupTarget` struct in
`Sources/ReclaimKit/Domain/TargetRegistry.swift`, plus `target.<id>.name` /
`.summary` (and `.note` / `.instructions` when present) entries in **both**
`Sources/ReclaimKit/Resources/en.lproj/Localizable.strings` and
`nb.lproj/Localizable.strings`. Conventions (test-enforced — `swift test`
fails if broken):

- Unique id; non-empty name/summary; path patterns start with `~/` or `/`,
  no trailing slash; pathless targets use the `.command` strategy.
- Prefer `.removeContents` for cache roots (tools expect the folder to
  exist); `.removePaths` only when removing the item itself is the point.
- Set `relatedAppBundleIDs` when a running app actively uses the data.
- **Never register user data.** Anything a person created or configured
  (settings, credentials, projects, chat history they'd miss) is off-limits.
- **Look beside what you target.** If a target reaches into a folder that
  also holds credentials, settings, or other user data (`~/.kube/cache`
  sits next to `~/.kube/config`), register those sibling paths in
  `Sources/ReclaimKit/Domain/ExclusionRegistry.swift` (with reason
  strings in both catalogues), or add the folder to
  `ExclusionRegistry.reviewedSafeRoots` if nothing sensitive lives
  there. A test fails until you have made that call, and the exclusion
  list is enforced twice: no target pattern may touch it, and the
  cleanup engine refuses those paths at runtime.

## Localization

Every user-facing string resolves through a `localized(key, defaultValue:)`
helper against the `{en,nb}.lproj` tables. English lives inline as the
default value; both catalogues must carry every key (tests enforce parity).
Don't use literal-key SwiftUI inits like `Text("some.key")` — resolve to
`String` first. Numbers, bytes and dates go through locale-aware
`.formatted(…)` APIs.

## Safety invariants

These are product guarantees. PRs that weaken them will not be merged:

1. Scanning never deletes anything.
2. Trash is the default disposal; permanent deletion is a Settings opt-in.
3. Manual-only targets are never cleanable from the UI or engine.
4. Cleaning is best-effort per item — one locked file must not abort a pass.
5. Cleaning disposes only the scan-time snapshot — nothing created after the
   scan can ever be deleted.
6. Structural exclusions (`ExclusionRegistry`) are never touched — no target
   pattern may collide with them, and the cleanup engine refuses them at
   runtime.

## Tests

Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest. Filesystem tests
use the `withTemporaryDirectory` fixture; engine tests use a mock
`FileRemoving` so nothing touches the real Trash. Run `swift test` before
pushing; CI runs it on every PR.

## Commits and pull requests

- Atomic commits, [Conventional Commits](https://www.conventionalcommits.org)
  style (`feat(registry): …`, `fix(ui): …`, `docs: …`).
- One logical change per PR. Fill in the PR template checklist.
- CI (build + test) must be green before review.

## Questions?

Open an issue — including half-formed ideas for new cleanup targets.
