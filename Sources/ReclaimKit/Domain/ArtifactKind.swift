//
//  ArtifactKind.swift
//  ReclaimKit
//
//  The declarative catalogue of regenerable project artifacts — the
//  dev-folder counterpart of TargetRegistry. A directory only counts
//  as an artifact when its *proof* holds (a marker file that shows
//  which tool generates it), so generic names like `build` or `dist`
//  can never claim user content. Matching is by name only; no file is
//  ever opened or parsed.
//

import Foundation

/// One kind of regenerable artifact directory found inside projects.
public struct ArtifactKind: Identifiable, Sendable, Equatable {
    /// How a directory name proves it is this artifact.
    public enum Proof: Sendable, Equatable {
        /// One of these names must exist beside the directory.
        case sibling([String])
        /// This name must exist directly inside the directory.
        case contains(String)
        /// The name alone is unambiguous.
        case nameAlone
    }

    /// Stable kebab-case identifier.
    public let id: String
    /// Localized display name, resolved at catalogue construction.
    public let name: String
    /// Directory names this kind claims (e.g. [".next", "dist"]).
    public let directoryNames: [String]
    /// When set, the artifact is this child inside the matched
    /// directory (Carthage → Build); the matched directory itself
    /// remains ordinary project content.
    public let nestedChild: String?
    public let proof: Proof

    public init(
        id: String, name: String, directoryNames: [String],
        nestedChild: String? = nil, proof: Proof
    ) {
        self.id = id
        self.name = name
        self.directoryNames = directoryNames
        self.nestedChild = nestedChild
        self.proof = proof
    }
}

/// All artifact kinds the dev-folder feature recognizes (v1 set).
public enum ArtifactCatalog {
    public static let all: [ArtifactKind] = [
        ArtifactKind(
            id: "node-modules",
            name: localized("artifact.node-modules.name", defaultValue: "node_modules"),
            directoryNames: ["node_modules"],
            proof: .sibling(["package.json"])
        ),
        ArtifactKind(
            id: "js-build",
            name: localized("artifact.js-build.name", defaultValue: "JS build output"),
            directoryNames: [".next", ".nuxt", "dist", ".turbo"],
            proof: .sibling(["package.json"])
        ),
        ArtifactKind(
            id: "cargo-target",
            name: localized("artifact.cargo-target.name", defaultValue: "Rust build (target)"),
            directoryNames: ["target"],
            proof: .sibling(["Cargo.toml"])
        ),
        ArtifactKind(
            id: "swiftpm-build",
            name: localized("artifact.swiftpm-build.name", defaultValue: "Swift build (.build)"),
            directoryNames: [".build"],
            proof: .sibling(["Package.swift"])
        ),
        ArtifactKind(
            id: "gradle-build",
            name: localized("artifact.gradle-build.name", defaultValue: "Gradle build"),
            directoryNames: ["build", ".gradle"],
            proof: .sibling(["build.gradle", "build.gradle.kts"])
        ),
        ArtifactKind(
            id: "python-venv",
            name: localized("artifact.python-venv.name", defaultValue: "Python virtualenv"),
            directoryNames: [".venv", "venv"],
            proof: .contains("pyvenv.cfg")
        ),
        ArtifactKind(
            id: "python-cache",
            name: localized("artifact.python-cache.name", defaultValue: "Python caches"),
            directoryNames: ["__pycache__", ".pytest_cache", ".tox"],
            proof: .nameAlone
        ),
        ArtifactKind(
            id: "cocoapods",
            name: localized("artifact.cocoapods.name", defaultValue: "CocoaPods (Pods)"),
            directoryNames: ["Pods"],
            proof: .sibling(["Podfile"])
        ),
        ArtifactKind(
            id: "carthage",
            name: localized("artifact.carthage.name", defaultValue: "Carthage build"),
            directoryNames: ["Carthage"],
            nestedChild: "Build",
            proof: .sibling(["Cartfile"])
        ),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byDirectoryName: [String: ArtifactKind] = {
        var map: [String: ArtifactKind] = [:]
        for kind in all {
            for name in kind.directoryNames { map[name] = kind }
        }
        return map
    }()

    public static func kind(withID id: String) -> ArtifactKind? { byID[id] }

    /// File names whose presence marks a directory as a project root
    /// (alongside `.git`): every sibling-proof marker.
    public static var projectMarkers: Set<String> {
        Set(all.flatMap { kind in
            if case .sibling(let markers) = kind.proof { return markers }
            return []
        })
    }

    /// The kind a directory name matches given its siblings — sibling
    /// proof is checked here; `contains` proof needs the directory's
    /// own listing and is the walker's job.
    public static func match(
        directoryName: String, siblingNames: Set<String>
    ) -> ArtifactKind? {
        guard let kind = byDirectoryName[directoryName] else { return nil }
        switch kind.proof {
        case .nameAlone, .contains:
            return kind
        case .sibling(let markers):
            return markers.contains(where: siblingNames.contains) ? kind : nil
        }
    }
}
