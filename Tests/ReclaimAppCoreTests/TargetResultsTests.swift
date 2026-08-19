//
//  TargetResultsTests.swift
//  ReclaimAppCoreTests
//
//  Orchestration-layer tests against stubbed scan/clean executors —
//  no filesystem, no Trash, deterministic.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("Target results")
struct TargetResultsTests {
    @Test("The Full Disk Access verdict is refreshed when scanning")
    func fullDiskAccessVerdict() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                fullDiskAccess: { false }
            )
        )
        #expect(model.results.hasFullDiskAccess == nil, "no verdict before the first scan")

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.results.hasFullDiskAccess == false)
    }

    @Test("All-findings visibility spans categories and honors the hide rules")
    func allVisibleTargets() async {
        let store = TemporaryDefaults()
        let found = target("found")
        let missing = target("missing")
        let empty = target("empty")
        let lowerBound = target("lower")
        let model = AppModel(
            targets: [found, missing, empty, lowerBound],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in
                    switch t.id {
                    case "found": measured(100)
                    case "empty": measured(0)
                    case "lower": .measured(
                        DiskMeasurement(bytes: 0, fileCount: 0, inaccessibleItems: 3),
                        resolvedPaths: [URL(filePath: "/fixture")],
                        cleanupPaths: []
                    )
                    default: .notInstalled
                    }
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        #expect(model.results.allVisibleTargets.count == 4,
                "everything is listed before a scan")

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        #expect(model.results.allVisibleTargets.map(\.id) == ["found", "lower"],
                "not-installed and provably empty targets hide by default; a lower-bound zero stays")

        model.settings.showNotInstalled = true
        #expect(model.results.allVisibleTargets.map(\.id) == ["found", "missing", "lower"])

        model.settings.showEmpty = true
        #expect(model.results.allVisibleTargets.count == 4, "both settings bring everything back")
        #expect(model.results.visibleTargets(in: .otherTools).count == 4,
                "the category list follows the same rules")
    }
}
