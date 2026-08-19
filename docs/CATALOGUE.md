# The Reclaim Catalogue

Everything Reclaim knows how to inspect and clean is data, not code:
one JSON file per item under `Sources/ReclaimKit/Catalogue/`. Adding
support for a new tool means adding one file — no Swift required.

```
Catalogue/
├── README.md                 ← you are 30 seconds from your first target
├── schema/                   ← JSON Schemas; editors validate as you type
├── xcode/ … otherTools/      ← one directory per category, one file per target
└── exclusions/               ← paths Reclaim must NEVER touch
    └── reviewed-safe-roots.json
```

Currently 123 targets across 12 categories.

## Adding a target in five steps

1. Copy `docs/templates/path-target.template.json` into the category
   directory that fits your tool, named `<id>.json` after your chosen id.
2. Fill in the fields (reference below). The `$schema` line gives most
   editors autocomplete and inline validation immediately.
3. Translate `name`, `summary` and any `note` into Norwegian. Machine
   translation is fine — say so in your PR and a native speaker will
   review it.
4. Check what lives NEXT TO the paths you target (see "Protecting what
   lives nearby" below). This is the step that keeps Reclaim safe.
5. Run `swift test`. The suite tells you precisely what is missing or
   off-convention. Green suite → open a PR.

## Target manifest reference

| Key | Required | Meaning |
| --- | --- | --- |
| `$schema` | yes | Always `"../schema/target.schema.json"`. |
| `id` | yes | Unique kebab-case identifier; must equal the file name. Ids are forever — user selections are stored against them. |
| `category` | yes | Must equal the directory name. One of: `xcode`, `android`, `dotNet`, `gameEngines`, `aiTools`, `packageManagers`, `containers`, `jvm`, `webTools`, `cloudDevOps`, `embedded`, `otherTools`. |
| `safety` | yes | `safe`, `caution`, or `destructive` — see the rubric below. |
| `paths` | unless command | Tilde-form or absolute patterns, `*` globs within one component. Nonexistent paths are dropped at scan time, so listing historical locations is fine. No trailing slash. |
| `strategy` | yes | `removeContents`, `removePaths`, `command`, or `manual` — see below. |
| `command` | with `command` | `executable` (absolute path), `arguments`, `display`, optional `availabilityProbe`. |
| `instructions` | with `manual` | Localized; keep the tool's command in backticks in every language. |
| `relatedApps` | no | Bundle ids of apps that actively use the data; a running one triggers a soft pre-clean warning. |
| `name`, `summary`, `note` | name+summary yes | Localized display text. `summary` is one or two sentences: what the data is, what happens after cleaning. |

## Choosing a safety level

- **safe** — regenerated automatically with no questions asked: build
  caches, derived data, logs, package-manager download caches. The
  only cost of cleaning is the next build/download being slower.
- **caution** — restorable, but it costs something: re-downloading
  large models, losing session history, re-creating archives. The user
  should glance at it before cleaning.
- **destructive** — removes something the user deliberately created or
  installed: simulators, emulators, installed language versions,
  virtual machines. Never rate these lower to make cleaning easier.

When torn between two levels, pick the higher one. A `manual` target
must never be rated `safe` (test-enforced — the overview ring depends
on it).

## Choosing a strategy

- **removeContents** — the default for cache roots. Deletes what's
  inside the directory, keeps the directory: many tools break if their
  cache root vanishes.
- **removePaths** — only when removing the item itself is the point
  (an old archive, a downloaded installer, an unused VM image).
- **command** — the owning tool has a purpose-built cleanup command
  that knows things Reclaim can't (e.g. `xcrun simctl delete
  unavailable`). Reclaim runs it and reports what the tool reclaimed.
- **manual** — Reclaim may measure but must not delete, because the
  data belongs to a running system that must clean itself (Docker's VM
  disk, Go's read-only module cache). The user gets your
  `instructions` instead of a Clean button.

## Protecting what lives nearby

Many tools keep credentials and settings right beside their caches:
`~/.kube/cache` sits next to `~/.kube/config`. When your target
reaches *into* a folder like that, the test suite forces an explicit
decision (`RegistryTests/rootsAreReviewed`):

- Something sensitive lives beside your target → add an exclusion
  manifest in `exclusions/` (copy
  `docs/templates/exclusion.template.json`). List the sibling paths,
  pick the Settings `group`, and give a short localized `reason`.
- Nothing sensitive lives there → add the root to
  `exclusions/reviewed-safe-roots.json` with a one-line rationale
  ("cache and logs; tokens live in ~/.npmrc"). That claim is
  reviewable and permanent, so be sure.

Exclusions are enforced three times: no target pattern may collide
with one (test), the cleanup engine refuses them at runtime, and the
list is shown in Settings. **Never** register user data as a target:
anything a person created or configured — settings, credentials,
projects, chat history they'd miss — is off-limits, always.

Standard reason phrasings (reuse before inventing a new one):

| English | Norwegian |
| --- | --- |
| access tokens | tilgangsnøkler |
| account state | kontotilstand |
| auth & app state | pålogging og apptilstand |
| auth & config | pålogging og oppsett |
| auth token | påloggingsnøkkel |
| chat history | samtalehistorikk |
| cluster credentials | klyngepålogging |
| config, may hold API keys | oppsett, kan inneholde API-nøkler |
| credential providers | påloggingsleverandører |
| credentials | påloggingsinformasjon |
| dev certs & keys | utviklingssertifikater og nøkler |
| device key & debug signing | enhetsnøkkel og debug-signering |
| editor state | editortilstand |
| GPG keys | GPG-nøkler |
| IDE settings & plugins | IDE-innstillinger og programtillegg |
| installed tools | installerte verktøy |
| instructions & custom commands | instruksjoner og egendefinerte kommandoer |
| keychains | nøkkelringer |
| MCP config | MCP-oppsett |
| OAuth credentials | OAuth-påloggingsinformasjon |
| plugins | programtillegg |
| registry auth | registerpålogging |
| registry token | registernøkkel |
| repository credentials | pålogging for pakkeregistre |
| settings | innstillinger |
| signing key | signeringsnøkkel |
| signing keys & tokens | signeringsnøkler og hemmeligheter |
| SSH keys | SSH-nøkler |
| Terraform Cloud tokens | Terraform Cloud-nøkler |
| user settings | brukerinnstillinger |

## What the tests enforce

`swift test` is the contribution gate. What each failure means:

| Failing test | It means |
| --- | --- |
| `CatalogueConventionTests/targetManifestShape` | Unknown key (typo?), wrong `$schema`, or a text object missing a locale / carrying an empty string. |
| `CatalogueConventionTests/filenamesAndDirectoriesAgree` | File name ≠ `id`, or directory ≠ `category`. |
| `CatalogueConventionTests/bundledCatalogueDecodes` | The manifest is not valid JSON, or fields don't fit the format (message names the file and reason). |
| `CatalogueConventionTests/manualInstructionsKeepCommands` | A `manual` target's instructions lost their backticked command in some locale. |
| `RegistryTests/uniqueIdentifiers` | Your `id` is already taken. |
| `RegistryTests/patternShape` | A path doesn't start with `~/` or `/`, or has a trailing slash. |
| `RegistryTests/pathlessTargetsAreCommands` | You omitted `paths` on a non-command target. |
| `RegistryTests/manualTargetsAreNeverSafe` | A `manual` target is rated `safe`. |
| `RegistryTests/exclusionsAreRespected` | Your target's paths collide with a protected path. |
| `RegistryTests/rootsAreReviewed` | You reached into a folder that needs an exclusion or a reviewed-safe-root entry (message explains both options). |
| `ExclusionRegistryTests/*` | An exclusion manifest breaks shape rules (globs, duplicates, empty reason). |

## Housekeeping notes

- **Ordering** is deterministic: category display order, then id. There
  is no index file to edit and no curated order to maintain.
- **Ids are forever.** Renaming one orphans users' saved selections.
- **Adding a locale**: extend `CatalogueLocales.supported` in
  `Sources/ReclaimKit/Domain/CatalogueManifest.swift`; the failing
  completeness test then enumerates every manifest to backfill.
- **Adding a category or exclusion group** is a code change
  (`ToolCategory` / `ExclusionGroup`) plus a `category.*.title` /
  `exclusionGroup.*.name` entry in both `.lproj` catalogues — rare,
  and fine to propose in an issue first.
