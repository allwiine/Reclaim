//
//  CleanSummaryTests.swift
//  ReclaimAppCoreTests
//

import Foundation
import ReclaimKit
import Testing
@testable import ReclaimAppCore

@Suite("Clean summary")
struct CleanSummaryTests {
    @Test("Trash wording reports items and locations with plural agreement")
    func trashWording() {
        var summary = CleanSummary(disposal: .trash)
        summary.itemsRemoved = 3
        summary.cleanedTargets = 2
        summary.reclaimedBytes = 1_000_000

        #expect(summary.message.contains("3 items"))
        #expect(summary.message.contains("2 locations"))
        #expect(summary.message.contains("Trash"))
    }

    @Test("Singular counts stay singular")
    func singularWording() {
        var summary = CleanSummary(disposal: .delete)
        summary.itemsRemoved = 1
        summary.cleanedTargets = 1
        summary.reclaimedBytes = 500

        #expect(summary.message.contains("1 item"))
        #expect(!summary.message.contains("1 items"))
        #expect(!summary.message.contains("1 locations"))
    }

    @Test("A stopped pass says it was stopped early")
    func stoppedWording() {
        var summary = CleanSummary(disposal: .trash)
        summary.itemsRemoved = 1
        summary.cleanedTargets = 1
        summary.wasStopped = true

        #expect(summary.message.contains("stopped early"))
    }

    @Test("A pass where nothing was removed says so instead of claiming success")
    func totalFailure() {
        var summary = CleanSummary(disposal: .trash)
        summary.failedTargets = 1
        summary.failures = ["Gradle caches — locked"]

        #expect(summary.message.contains("Nothing was cleaned"))
        #expect(!summary.message.contains("Moved"))
    }
}
