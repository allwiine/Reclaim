//
//  OffMain.swift
//  ReclaimAppCore
//

/// Runs blocking work off the main actor. With this package's
/// settings a `nonisolated` async function hops to the global
/// concurrent executor. If `NonisolatedNonsendingByDefault` is ever
/// enabled, annotate this `@concurrent` to preserve that behavior.
nonisolated func offMain<T: Sendable>(
    _ work: @Sendable @escaping () -> T
) async -> T {
    work()
}
