//
//  SettingsStoreTests.swift
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
@Suite("Settings")
struct SettingsStoreTests {
    @Test("The disposal chosen in Settings reaches the clean executor")
    func disposalSnapshot() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let usedDisposal = Mutex<Disposal?>(nil)

        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { _, _, disposal in
                    usedDisposal.withLock { $0 = disposal }
                    return CleanOutcome(removedItems: 1)
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.settings.disposal = .delete

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(cache, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        #expect(usedDisposal.withLock { $0 } == .delete)
    }
}
