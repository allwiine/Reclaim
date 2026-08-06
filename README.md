# Reclaim

[![CI](https://github.com/allwiine/Reclaim/actions/workflows/ci.yml/badge.svg)](https://github.com/allwiine/Reclaim/actions/workflows/ci.yml)

A native macOS app for finding and cleaning wasted developer storage — with a focus on the space quietly retained by **Xcode**, **Android Studio**, **Claude Code** and similar tools.

Reclaim scans a curated catalogue of known cache and scratch locations, shows what each one is, how risky it is to remove, and cleans your selection — to the Trash by default, so mistakes are recoverable.

Built with **Swift 6.2**, **SwiftUI**, the **Observation** framework, strict concurrency, **Swift Charts**, and **Swift Testing**.

## What it covers

| Category | Examples |
| --- | --- |
| Xcode & Simulators | Derived data, device support files, archives, simulator caches, SwiftUI Previews data, device logs, XCTest simulator clones, unavailable simulators (`simctl`) |
| Android Studio | Gradle caches, wrapper distributions, build-scan data, IDE caches, Kotlin/Native toolchains, SDK system images, AVDs |
| Claude & AI tools | Claude Code CLI caches (`~/Library/Caches/claude-cli-nodejs`), logs & scratch data, session transcripts, Claude Desktop caches, Ollama / Hugging Face / LM Studio models |
| Package managers | Homebrew, npm, pnpm, Yarn (classic & Berry), pip, uv, Poetry, CocoaPods, SwiftPM, Cargo, Go, Deno, node-gyp |
| Other dev tools | VS Code caches & workspace storage, JetBrains caches & logs, Playwright / Puppeteer browsers, pre-commit environments, Docker VM disk (measured; cleaned via Docker itself) |

Every item carries a safety rating:

- **Safe** — regenerated automatically (build caches, logs).
- **Caution** — restorable, but re-downloading or losing history costs something (AI models, Claude Code transcripts, Xcode archives).
- **Destructive** — removes things you created (Android emulators).

Items Reclaim should *not* delete itself (Docker's VM disk, Go's read-only module cache) are still measured, but cleaning is delegated to the owning tool with clear instructions. Claude Code's auth, settings and plugins are structurally excluded from the catalogue — a unit test enforces it.

## Requirements

- macOS 15 or later (macOS Tahoe 26 fully supported)
- Xcode 26 / Swift 6.2 toolchain to build

## Running

The project is a Swift package that Xcode opens directly:

```bash
git clone <this repo>
cd Reclaim
open Package.swift        # then select the "Reclaim" scheme and Run
# or, without Xcode's UI:
swift run Reclaim
```

Run the tests with:

```bash
swift test
```

### Building a distributable .app

For day-to-day use, `swift run` is enough. To produce a proper `.app` bundle, an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec is included:

```bash
brew install xcodegen
xcodegen                  # generates Reclaim.xcodeproj
open Reclaim.xcodeproj    # archive / export as usual
```

The app is intentionally **not sandboxed**: its whole purpose is reading and cleaning locations across `~/Library` and dot-directories in your home folder. That rules out App Store distribution but keeps the UX honest — no folder-picker ceremony for every path.

### Permissions

Most locations are readable out of the box. If a scan row shows *Couldn't scan*, grant Reclaim (or your terminal, when using `swift run`) **Full Disk Access** in System Settings → Privacy & Security. Settings has a shortcut button.

## Safety model

1. **Scan is read-only.** Nothing is ever deleted during a scan.
2. **Cleaning operates on the scan-time snapshot only.** The scanner captures the exact deletion set (for cache roots, their children at scan time), and the engine disposes precisely those URLs — anything created after the scan is untouchable. What you saw is what gets cleaned.
3. **Trash by default.** Permanent deletion is opt-in via Settings.
4. **Explicit confirmation** with size and consequence before any cleanup — including a warning when a related app (Xcode, Android Studio, VS Code…) is currently running.
5. **Manual-only items are never touched** — the UI physically cannot select them.
6. **Post-clean rescan.** Numbers on screen are re-measured, never assumed; the summary counts only what was actually removed.
7. **Honest failures.** Unreadable locations show as "Couldn't scan" or "N unreadable" (with a Full Disk Access banner) instead of quietly measuring as empty; scans stopped early are labeled partial; a clean pass can be stopped between items.

## Adding a new tool

One struct in [`TargetRegistry`](Sources/ReclaimKit/Domain/TargetRegistry.swift) — no other changes needed:

```swift
CleanupTarget(
    id: "deno-cache",
    name: "Deno cache",
    summary: "Remote modules cached by Deno. Re-downloaded on demand.",
    category: .packageManagers,
    safety: .safe,
    pathPatterns: ["~/Library/Caches/deno"],
    strategy: .removeContents
)
```

Patterns support `~` and `*` globs (`~/Library/Caches/Google/AndroidStudio*`); paths that don't exist on a machine are simply dropped. Registry conventions are enforced by `RegistryTests`, so `swift test` tells you immediately if a new entry breaks the rules.

## Project layout

```
Package.swift               Swift 6.2 package (app + libraries + tests)
project.yml                 Optional XcodeGen spec for a .app bundle
Sources/
  ReclaimKit/               UI-free core library (fully unit-tested)
    Domain/                 CleanupTarget, registry, safety levels, status
    Services/               PathResolver, DiskSizer, TargetScanner,
                            CleanupEngine, FullDiskAccessProbe
    Support/                os.log categories
  ReclaimAppCore/           UI-free app state: AppModel, CleanSummary
  Reclaim/                  The SwiftUI app (views only)
Tests/ReclaimKitTests/      Core library suite
Tests/ReclaimAppCoreTests/  Orchestration suite (stubbed executors)
docs/ARCHITECTURE.md        Design and concurrency documentation
.github/workflows/ci.yml    Build & test on every push / PR
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design rationale.

## License

MIT — see [LICENSE](LICENSE).
