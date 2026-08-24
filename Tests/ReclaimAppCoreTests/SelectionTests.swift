//
//  SelectionTests.swift
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

@Suite("Selection")
struct SelectionTests {
    @Test("Only measured non-empty cleanable targets are selectable")
    func selectionRules() async {
        let store = TemporaryDefaults()
        let manual = target("manual", strategy: .manual(instructions: "Use the tool."))
        let empty = target("empty")
        let full = target("full")
        let command = commandTarget("command")
        let model = AppModel(
            targets: [manual, empty, full, command],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in
                    switch t.id {
                    case "manual": measured(500)
                    case "empty": measured(0)
                    case "full": measured(100)
                    default: .unmeasurable
                    }
                }
            )
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(!model.selection.isSelectable(manual), "manual targets must never be selectable")
        #expect(!model.selection.isSelectable(empty), "empty targets have nothing to clean")
        #expect(model.selection.isSelectable(full))
        #expect(model.selection.isSelectable(command), "command targets are cleanable while unmeasured")

        model.selection.setSelected(command, true)
        model.selection.setSelected(full, true)
        #expect(
            model.selection.selectedTargets.map(\.id) == ["full", "command"],
            "selected targets come back in registry order"
        )
    }

    @Test("selectAllSafe skips caution-rated targets")
    func selectAllSafeRespectsSafety() async {
        let store = TemporaryDefaults()
        let safe = target("safe", safety: .safe)
        let risky = target("risky", safety: .caution)
        let model = AppModel(
            targets: [safe, risky],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            )
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.selectAllSafe()

        #expect(model.selection.isSelected(safe))
        #expect(!model.selection.isSelected(risky))
    }

    @Test("A finished scan preselects Safe items, honoring the Caution setting")
    func postScanPreselection() async {
        let store = TemporaryDefaults()
        let safe = target("safe", safety: .safe)
        let risky = target("risky", safety: .caution)
        let manual = target("manual", strategy: .manual(instructions: "Use the tool."))
        let model = AppModel(
            targets: [safe, risky, manual],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.selection.isSelected(safe), "Safe items come ticked after a scan")
        #expect(!model.selection.isSelected(risky), "Caution items stay unticked by default")
        #expect(!model.selection.isSelected(manual), "manual targets can never be selected")

        model.settings.preselectCaution = true
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.selection.isSelected(risky), "the Caution preselection setting is honored")
    }

    @Test("Auto-select exclusions are honored, revocable and persistent")
    func autoSelectExclusions() async {
        let store = TemporaryDefaults()
        let kept = target("kept", safety: .safe)
        let excluded = target("excluded", safety: .safe)
        let model = AppModel(
            targets: [kept, excluded],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.selection.setExcludedFromAutoSelect(excluded, true)
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.selection.isSelected(kept))
        #expect(!model.selection.isSelected(excluded), "post-scan preselection must skip exclusions")

        model.selection.clear()
        model.selection.selectAllSafe()
        #expect(!model.selection.isSelected(excluded), "selectAllSafe must skip exclusions")

        model.selection.setSelected(excluded, true)
        #expect(model.selection.isSelected(excluded), "manual ticking still works")

        model.selection.setExcludedFromAutoSelect(excluded, true)
        #expect(!model.selection.isSelected(excluded), "excluding a ticked target unticks it")

        let second = AppModel(
            targets: [kept, excluded],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )
        #expect(second.selection.isExcludedFromAutoSelect(excluded), "exclusions survive a relaunch")

        model.selection.setExcludedFromAutoSelect(excluded, false)
        model.selection.selectAllSafe()
        #expect(model.selection.isSelected(excluded), "revoking the exclusion restores auto-selection")
    }
}
