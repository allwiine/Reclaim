# Contributing to Reclaim

Thanks for helping make Reclaim better! Contributions of every size are
welcome — new cleanup targets are the sweet spot (one JSON manifest, no
Swift required), and bug reports with good reproduction steps are gold.

## Development setup

Requirements: macOS 26 (Tahoe), Xcode 26 (Swift 6.2 toolchain).

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

## Tooling

Install [SwiftLint](https://github.com/realm/SwiftLint) and
[lefthook](https://github.com/evilmartians/lefthook), then set up the
pre-commit hook once after cloning:

```bash
brew install swiftlint lefthook
lefthook install
```

CI pins SwiftLint 0.59.1 (its `file_length` counting defines the gate);
keep your local install on the same minor version — `brew install
swiftlint` currently matches.

Every Swift file is capped at 200 lines of code — `.swiftlint.yml`'s
`file_length` rule (`ignore_comment_only_lines: true`), which the hook
enforces on staged files via `swiftlint lint --strict`. `.swiftlint.yml`
deliberately sets `only_rules: [file_length, custom_rules]`: the gate's
scope is exact by design, not a starting point for accumulating unrelated
style rules.

The same gate enforces the design-token boundary. Views under
`Sources/Reclaim` may not write a raw styling literal — `.padding(N)` /
`spacing: N`, `cornerRadius: N`, `.font(.system(...))` / `Font.system(...)`,
`scaledFont(size: N)`, or `Color(hex:)` — a `custom_rules` regex fails the
lint for each. Those values live in exactly one place,
`Sources/Reclaim/DesignSystem` (spacing in `Spacing.swift`, typography in
`Theme.swift`/`TextRoles.swift`/`ScaledFont.swift`, color in
`Theme.swift`/`Palette+Views.swift`), named as a token and applied from
views via `Theme.*`, `.themeFont(_:)`, etc. A further rule,
`single_environment_root`, keeps model injection funneled through the
single `appEnvironment(_:)` call in `Sources/Reclaim/App/AppEnvironment.swift`
instead of ad hoc `.environment(...)` calls in views (keypath environment
values like `.environment(\.locale, …)` are exempt). All of this runs at
`error` severity through the same pre-commit hook — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the DesignSystem's shape.

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

The most valuable contribution — and it's one JSON file, no Swift.

1. Copy a template from [docs/templates/](docs/templates/) into
   `Sources/ReclaimKit/Catalogue/<category>/`, named `<id>.json`.
2. Fill it in. The `$schema` line gives your editor autocomplete and
   validation; the full field reference is
   [docs/CATALOGUE.md](docs/CATALOGUE.md).
3. Translate the text into Norwegian (`nb`). Machine translation is
   welcome — mention it in the PR and we review it.
4. Check what lives *beside* the paths you target. If credentials or
   settings sit next to them (`~/.kube/cache` next to
   `~/.kube/config`), add an exclusion manifest in
   `Catalogue/exclusions/`, or add the root to
   `Catalogue/exclusions/reviewed-safe-roots.json` with a rationale if
   nothing sensitive lives there. A test fails until you have made
   that call.
5. `swift test` — the suite names anything missing or off-convention.

**Never register user data.** Anything a person created or configured
(settings, credentials, projects, chat history they'd miss) is
off-limits.

## Localization

Every user-facing string resolves through a `localized(key, defaultValue:)`
helper against the `{en,nb}.lproj` tables. English lives inline as the
default value; both catalogues must carry every key (tests enforce parity).
Don't use literal-key SwiftUI inits like `Text("some.key")` — resolve to
`String` first. Numbers, bytes and dates go through locale-aware
`.formatted(…)` APIs. Catalogue text — target names, summaries, notes,
instructions, exclusion reasons — lives inline in the JSON manifests
instead, not in the `.lproj` catalogues.

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
