//
//  AppModelTests.swift
//  ReclaimAppCoreTests
//
//  Cross-model aggregates that no single sub-model owns: registry
//  targets and dev-folder projects combined into one overview.
//

import Foundation
import ReclaimKit
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("App model")
struct AppModelTests {
    @Test("Selected bytes and totals include artifacts")
    func totalsIncludeArtifacts() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        // Post-scan auto-selection ticked the safe target (100).
        #expect(model.selectedBytes == 100)
        model.projects.setArtifactSelected(fixture.artifacts[0], true)
        #expect(model.selectedBytes == 600)
        #expect(model.projects.selectedArtifactBytes == 500)
    }

    @Test("Largest findings mix registry targets and projects by size")
    func largestFindingsMix() async {
        let store = TemporaryDefaults()
        let big = project(
            "/dev/big", devRoot: "/dev",
            artifacts: [artifact("/dev/big/node_modules", bytes: 500)]
        )
        let small = project(
            "/dev/small", devRoot: "/dev",
            artifacts: [artifact("/dev/small/node_modules", bytes: 50)]
        )
        let model = AppModel(
            targets: [target("cache"), target("nothing")],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in t.id == "cache" ? measured(100) : measured(0) },
                projectScan: { root in
                    DevRootScan(root: root, projects: [big, small])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        let findings = model.largestFindings(limit: 6)
        #expect(findings.map(\.id) == ["project:/dev/big", "target:cache", "project:/dev/small"])
        #expect(findings.map(\.bytes) == [500, 100, 50])
        #expect(model.largestFindings(limit: 1).map(\.id) == ["project:/dev/big"])
    }
}
