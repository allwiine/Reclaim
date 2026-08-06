//
//  PathResolver.swift
//  ReclaimKit
//
//  Turns declarative path patterns from the registry into concrete,
//  existing URLs. Supports `~` expansion and `*` globs inside any
//  single path component. Non-existent paths are dropped.
//

import Foundation

/// Resolves registry path patterns against a base (home) directory.
///
/// Injectable `home` keeps the resolver fully testable against
/// temporary directories.
public struct PathResolver: Sendable {
    /// The directory `~` expands to.
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Resolve a single pattern to the existing paths it matches.
    ///
    /// - Parameter pattern: e.g. `~/Library/Caches/Google/AndroidStudio*`
    /// - Returns: Existing URLs, or `[]` if nothing matches.
    public func resolve(_ pattern: String) -> [URL] {
        let fileManager = FileManager.default

        // 1. Expand `~` against the injected home directory.
        let expanded: String =
            if pattern.hasPrefix("~") {
                home.path + pattern.dropFirst()
            } else {
                pattern
            }

        // 2. Walk components, branching wherever a glob appears.
        let components = expanded.split(separator: "/").map(String.init)
        var frontier: [URL] = [URL(filePath: "/")]

        for component in components {
            if component.contains("*") {
                frontier = frontier
                    .flatMap { directory in
                        (try? fileManager.contentsOfDirectory(
                            at: directory,
                            includingPropertiesForKeys: nil,
                            options: []
                        )) ?? []
                    }
                    .filter { Self.matches(name: $0.lastPathComponent, glob: component) }
            } else {
                frontier = frontier.map { $0.appending(path: component) }
            }

            // Prune dead branches early so globs never explode.
            frontier = frontier.filter { fileManager.fileExists(atPath: $0.path) }
            if frontier.isEmpty { return [] }
        }

        return frontier.sorted { $0.path < $1.path }
    }

    /// Resolve many patterns, concatenating their matches in order.
    public func resolveAll(_ patterns: [String]) -> [URL] {
        patterns.flatMap(resolve)
    }

    // MARK: - Glob matching

    /// Match one path component against a glob where `*` means
    /// "any run of characters". Implemented via an anchored regex so we
    /// avoid C string interop; literal parts are regex-escaped.
    static func matches(name: String, glob: String) -> Bool {
        guard glob.contains("*") else { return name == glob }
        let escapedParts = glob
            .components(separatedBy: "*")
            .map(NSRegularExpression.escapedPattern(for:))
        let pattern = "^" + escapedParts.joined(separator: ".*") + "$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
