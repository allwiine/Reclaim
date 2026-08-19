# The Reclaim Catalogue

One JSON file = one thing Reclaim can inspect and clean. This is the
project's main contribution surface — **the full guide is
[docs/CATALOGUE.md](../../../docs/CATALOGUE.md)**, and copy-paste
templates live in [docs/templates/](../../../docs/templates/).

A complete target manifest:

```json
{
  "$schema": "../schema/target.schema.json",
  "id": "xcode-derived-data",
  "category": "xcode",
  "safety": "safe",
  "paths": ["~/Library/Developer/Xcode/DerivedData"],
  "strategy": "removeContents",
  "relatedApps": ["com.apple.dt.Xcode"],
  "name": { "en": "Derived data", "nb": "DerivedData" },
  "summary": {
    "en": "Build products, indexes and module caches for every project you have opened. Rebuilt on the next build.",
    "nb": "Byggprodukter, indekser og modulcacher for hvert prosjekt du har åpnet. Bygges på nytt ved neste bygg."
  },
  "note": {
    "en": "The next build of each project will be a clean build.",
    "nb": "Neste bygg av hvert prosjekt blir en clean build."
  }
}
```

Ground rules, in one breath: the file name is the `id`; the directory
is the `category`; every text object carries `en` and `nb` (machine
translation welcome — flag it in the PR); never target anything a
person created or configured; check what lives *beside* your paths
(`exclusions/` protects credentials and settings); `swift test` tells
you the rest.
