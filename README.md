# Reclaim

A native macOS app for finding and cleaning wasted developer storage — with a focus on the space quietly retained by **Xcode**, **Android Studio**, **Claude Code** and similar tools.

Reclaim scans a curated catalogue of known cache and scratch locations, shows what each one is, how risky it is to remove, and cleans your selection — to the Trash by default, so mistakes are recoverable.

Built with **Swift 6.2**, **SwiftUI**, the **Observation** framework, strict concurrency, **Swift Charts**, and **Swift Testing**.

## What it covers

| Category | Examples |
| --- | --- |
| Xcode & Simulators | Derived data, device support files, archives, simulator caches, SwiftUI Previews data, unavailable simulators (`simctl`) |
| Android Studio | Gradle caches, wrapper distributions, IDE caches, SDK system images, AVDs |
| Claude & AI tools | Claude Code CLI caches (`~/Library/Caches/claude-cli-nodejs`), logs & scratch data, session transcripts, Claude Desktop caches, Ollama / Hugging Face / LM Studio models |
| Package managers | Homebrew, npm, pnpm, Yarn, pip, uv, CocoaPods, SwiftPM, Cargo, Go |
| Other dev tools | VS Code caches, JetBrains caches, Docker VM disk (measured; cleaned via Docker itself) |

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
2. **Cleaning operates on scanned paths only.** The engine receives the exact URLs the scan resolved — what you saw is what gets cleaned.
3. **Trash by default.** Permanent deletion is opt-in via Settings.
4. **Explicit confirmation** with size and consequence before any cleanup.
5. **Manual-only items are never touched** — the UI physically cannot select them.
6. **Post-clean rescan.** Numbers on screen are re-measured, never assumed.

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
Package.swift               Swift 6.2 package (app + core + tests)
project.yml                 Optional XcodeGen spec for a .app bundle
Sources/
  ReclaimKit/               UI-free core library (fully unit-tested)
    Domain/                 CleanupTarget, registry, safety levels, status
    Services/               PathResolver, DiskSizer, TargetScanner, CleanupEngine
    Support/                os.log categories
  Reclaim/                  The SwiftUI app
    App/                    Entry point, AppModel (@Observable, @MainActor)
    UI/                     Views + components
Tests/ReclaimKitTests/      Swift Testing suite
docs/ARCHITECTURE.md        Design and concurrency documentation
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design rationale.

## License

MIT — see [LICENSE](LICENSE).
