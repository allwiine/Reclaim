//
//  ExclusionRegistry.swift
//  ReclaimKit
//
//  The catalogue's mirror image: paths Reclaim structurally refuses to
//  touch. Three consumers, one data source, no drift:
//    - SettingsView renders this list ("Excluded from scans"),
//    - RegistryTests forbids any target pattern from colliding with it,
//    - CleanupEngine refuses to dispose anything inside it at runtime.
//
//  Entries are a ban list, not a scan list: a path here need not exist
//  on disk. Every entry bans three things at once — the path itself,
//  anything inside it, and any target that claims one of its ancestors
//  (disposing ~/.cargo wholesale would take credentials.toml with it).
//

import Foundation

/// A tool-family heading for the Settings presentation.
public enum ExclusionGroup: String, Sendable, CaseIterable, Identifiable {
    case claudeCode
    case aiTools
    case cloudContainers
    case toolchains
    case keysCertificates
    case editorSettings

    public var id: String { rawValue }

    /// Localized heading shown above the group's rows.
    public var displayName: String {
        switch self {
        case .claudeCode:
            localized("exclusionGroup.claudeCode.name", defaultValue: "Claude Code")
        case .aiTools:
            localized("exclusionGroup.aiTools.name", defaultValue: "AI assistants")
        case .cloudContainers:
            localized("exclusionGroup.cloudContainers.name", defaultValue: "Cloud & containers")
        case .toolchains:
            localized("exclusionGroup.toolchains.name", defaultValue: "Toolchains & registries")
        case .keysCertificates:
            localized("exclusionGroup.keysCertificates.name", defaultValue: "Keys & certificates")
        case .editorSettings:
            localized("exclusionGroup.editorSettings.name", defaultValue: "Editor settings")
        }
    }
}

/// One protected path, or a small set of sibling paths sharing a reason.
public struct StructuralExclusion: Sendable, Identifiable {
    public let id: String
    /// Tilde-form paths, no trailing slash — the same shape as
    /// `CleanupTarget.pathPatterns`, but always literal (no globs).
    public let paths: [String]
    public let group: ExclusionGroup
    /// Short localized noun phrase ("auth token", "cluster credentials").
    public let reason: String

    public init(id: String, paths: [String], group: ExclusionGroup, reason: String) {
        self.id = id
        self.paths = paths
        self.group = group
        self.reason = reason
    }
}

/// Shared localized reasons — several entries legitimately carry the
/// same label, and sharing the key keeps the two catalogues small.
private enum Reason {
    static let authAppState = localized("exclusion.reason.authAppState", defaultValue: "auth & app state")
    static let settings = localized("exclusion.reason.settings", defaultValue: "settings")
    static let plugins = localized("exclusion.reason.plugins", defaultValue: "plugins")
    static let authToken = localized("exclusion.reason.authToken", defaultValue: "auth token")
    static let oauthCredentials = localized("exclusion.reason.oauthCredentials", defaultValue: "OAuth credentials")
    static let authAndConfig = localized("exclusion.reason.authAndConfig", defaultValue: "auth & config")
    static let signingKey = localized("exclusion.reason.signingKey", defaultValue: "signing key")
    static let accessTokens = localized("exclusion.reason.accessTokens", defaultValue: "access tokens")
    static let configMayHoldKeys = localized("exclusion.reason.configMayHoldKeys", defaultValue: "config, may hold API keys")
    static let chatHistory = localized("exclusion.reason.chatHistory", defaultValue: "chat history")
    static let mcpConfig = localized("exclusion.reason.mcpConfig", defaultValue: "MCP config")
    static let clusterCredentials = localized("exclusion.reason.clusterCredentials", defaultValue: "cluster credentials")
    static let credentials = localized("exclusion.reason.credentials", defaultValue: "credentials")
    static let registryAuth = localized("exclusion.reason.registryAuth", defaultValue: "registry auth")
    static let terraformTokens = localized("exclusion.reason.terraformTokens", defaultValue: "Terraform Cloud tokens")
    static let registryToken = localized("exclusion.reason.registryToken", defaultValue: "registry token")
    static let signingKeysTokens = localized("exclusion.reason.signingKeysTokens", defaultValue: "signing keys & tokens")
    static let repositoryCredentials = localized("exclusion.reason.repositoryCredentials", defaultValue: "repository credentials")
    static let credentialProviders = localized("exclusion.reason.credentialProviders", defaultValue: "credential providers")
    static let installedTools = localized("exclusion.reason.installedTools", defaultValue: "installed tools")
    static let deviceKeys = localized("exclusion.reason.deviceKeys", defaultValue: "device key & debug signing")
    static let accountState = localized("exclusion.reason.accountState", defaultValue: "account state")
    static let sshKeys = localized("exclusion.reason.sshKeys", defaultValue: "SSH keys")
    static let gpgKeys = localized("exclusion.reason.gpgKeys", defaultValue: "GPG keys")
    static let devCerts = localized("exclusion.reason.devCerts", defaultValue: "dev certs & keys")
    static let keychains = localized("exclusion.reason.keychains", defaultValue: "keychains")
    static let userSettings = localized("exclusion.reason.userSettings", defaultValue: "user settings")
    static let ideSettings = localized("exclusion.reason.ideSettings", defaultValue: "IDE settings & plugins")
    static let editorState = localized("exclusion.reason.editorState", defaultValue: "editor state")
    static let userContent = localized("exclusion.reason.userContent", defaultValue: "instructions & custom commands")
}

/// The single source of truth for structural exclusions.
public enum ExclusionRegistry {
    public static func entries(in group: ExclusionGroup) -> [StructuralExclusion] {
        all.filter { $0.group == group }
    }

    /// Absolute, tilde-expanded forms of every protected path, for the
    /// engine's runtime refusal check.
    public static let expandedProtectedPaths: [String] = all
        .flatMap(\.paths)
        .map { ($0 as NSString).expandingTildeInPath }

    /// The same paths lower-cased once, so the case-insensitive match in
    /// ``isProtected(_:)`` doesn't re-fold them on every call.
    private static let lowercasedProtectedPaths: [String] =
        expandedProtectedPaths.map { $0.lowercased() }

    /// True when `url` is a protected path, lies inside one, or is an
    /// ancestor of one (disposing an ancestor would take the protected
    /// path with it). The comparison is case-insensitive: the default
    /// APFS volume is, so `~/.SSH` must match `~/.ssh`.
    public static func isProtected(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path.lowercased()
        // The filesystem root is an ancestor of every exclusion.
        if candidate == "/" { return true }
        return lowercasedProtectedPaths.contains { protectedPath in
            candidate == protectedPath
                || candidate.hasPrefix(protectedPath + "/")
                || protectedPath.hasPrefix(candidate + "/")
        }
    }

    /// Roots that targets reach *into* which have been reviewed and
    /// hold nothing sensitive, so they need no exclusion entry. The
    /// reviewed-roots test in RegistryTests fails when a target reaches
    /// into a root that is neither listed here nor covered by an
    /// exclusion; adding a root here is an explicit, reviewable
    /// "nothing sensitive lives beside the targeted paths" claim.
    public static let reviewedSafeRoots: Set<String> = [
        "~/.aider",         // caches and tags only; config lives in ~/.aider.conf.yml
        "~/.bun",           // runtime and install cache; tokens live in ~/.bunfig.toml
        "~/.conda",         // package cache and environments.txt
        "~/.espressif",     // downloaded toolchains and Python envs
        "~/.minikube",      // local-VM certs regenerated by minikube itself
        "~/.asdf",          // installed runtimes, plugins and shims; no credentials
        "~/.cocoapods",     // cloned public podspec repos; the trunk token lives in ~/.netrc
        "~/.npm",           // cache and logs; tokens live in ~/.npmrc
        "~/.nvm",           // installed Node versions
        "~/.pyenv",         // installed Python versions
        "~/.rbenv",         // installed Ruby versions
        "~/.rustup",        // toolchains; crates.io token lives in ~/.cargo
        "~/.sdkman",        // archives and tmp; no credentials
        "~/.vagrant.d",     // boxes and the public insecure_private_key
        "~/.yarn",          // berry cache; tokens live in ~/.yarnrc.yml
        "~/.cache/firebase",     // emulator downloads; firebase auth lives in ~/.config/configstore
        "~/.cache/lm-studio",    // legacy model cache location
        "~/.cache/node",         // corepack cache only
        "~/.local/pipx",         // installed venvs and logs
        "~/.local/share/goose",  // session transcripts are the targeted data
        "~/.local/share/pipx",   // installed venvs and logs
        "~/.local/share/uv",     // downloaded Python toolchains
        "~/.local/state/goose",  // logs only
        "~/Library/Application Support/Epic",  // Unreal derived data and Zen cache
    ]

    public static let all: [StructuralExclusion] = [
        // MARK: - Claude Code
        StructuralExclusion(
            id: "claude-auth",
            paths: ["~/.claude.json"],
            group: .claudeCode,
            reason: Reason.authAppState
        ),
        StructuralExclusion(
            id: "claude-settings",
            paths: ["~/.claude/settings.json", "~/.claude/settings.local.json"],
            group: .claudeCode,
            reason: Reason.settings
        ),
        StructuralExclusion(
            id: "claude-plugins",
            paths: ["~/.claude/plugins"],
            group: .claudeCode,
            reason: Reason.plugins
        ),
        StructuralExclusion(
            id: "claude-user-content",
            paths: [
                "~/.claude/CLAUDE.md",
                "~/.claude/agents",
                "~/.claude/commands",
                "~/.claude/skills",
                "~/.claude/keybindings.json",
            ],
            group: .claudeCode,
            reason: Reason.userContent
        ),

        // MARK: - AI assistants
        StructuralExclusion(
            id: "codex-auth",
            paths: ["~/.codex/auth.json"],
            group: .aiTools,
            reason: Reason.authToken
        ),
        StructuralExclusion(
            id: "codex-config",
            paths: ["~/.codex/config.toml", "~/.codex/AGENTS.md", "~/.codex/prompts"],
            group: .aiTools,
            reason: Reason.settings
        ),
        StructuralExclusion(
            id: "gemini-auth",
            paths: ["~/.gemini/oauth_creds.json"],
            group: .aiTools,
            reason: Reason.oauthCredentials
        ),
        StructuralExclusion(
            id: "gemini-config",
            paths: ["~/.gemini/settings.json", "~/.gemini/GEMINI.md"],
            group: .aiTools,
            reason: Reason.settings
        ),
        StructuralExclusion(
            id: "copilot-auth",
            paths: ["~/.copilot/config.json"],
            group: .aiTools,
            reason: Reason.authAndConfig
        ),
        StructuralExclusion(
            id: "ollama-key",
            paths: ["~/.ollama/id_ed25519"],
            group: .aiTools,
            reason: Reason.signingKey
        ),
        StructuralExclusion(
            id: "huggingface-tokens",
            paths: ["~/.cache/huggingface/token", "~/.cache/huggingface/stored_tokens"],
            group: .aiTools,
            reason: Reason.accessTokens
        ),
        StructuralExclusion(
            id: "opencode-auth",
            paths: ["~/.local/share/opencode/auth.json"],
            group: .aiTools,
            reason: Reason.authToken
        ),
        StructuralExclusion(
            id: "continue-config",
            paths: ["~/.continue/config.json", "~/.continue/config.yaml", "~/.continue/config.ts"],
            group: .aiTools,
            reason: Reason.configMayHoldKeys
        ),
        StructuralExclusion(
            id: "continue-sessions",
            paths: ["~/.continue/sessions"],
            group: .aiTools,
            reason: Reason.chatHistory
        ),
        StructuralExclusion(
            id: "qwen-config",
            paths: ["~/.qwen/settings.json", "~/.qwen/oauth_creds.json"],
            group: .aiTools,
            reason: Reason.authAndConfig
        ),
        StructuralExclusion(
            id: "lmstudio-chats",
            paths: ["~/.lmstudio/conversations"],
            group: .aiTools,
            reason: Reason.chatHistory
        ),
        StructuralExclusion(
            id: "claude-desktop-config",
            paths: ["~/Library/Application Support/Claude/claude_desktop_config.json"],
            group: .aiTools,
            reason: Reason.mcpConfig
        ),

        // MARK: - Cloud & containers
        StructuralExclusion(
            id: "kube-config",
            paths: ["~/.kube/config"],
            group: .cloudContainers,
            reason: Reason.clusterCredentials
        ),
        StructuralExclusion(
            id: "gcloud-credentials",
            paths: [
                "~/.config/gcloud/credentials.db",
                "~/.config/gcloud/access_tokens.db",
                "~/.config/gcloud/application_default_credentials.json",
                "~/.config/gcloud/legacy_credentials",
            ],
            group: .cloudContainers,
            reason: Reason.credentials
        ),
        StructuralExclusion(
            id: "azure-tokens",
            paths: ["~/.azure/msal_token_cache.json"],
            group: .cloudContainers,
            reason: Reason.accessTokens
        ),
        StructuralExclusion(
            id: "docker-auth",
            paths: ["~/.docker/config.json"],
            group: .cloudContainers,
            reason: Reason.registryAuth
        ),
        StructuralExclusion(
            id: "pulumi-credentials",
            paths: ["~/.pulumi/credentials.json"],
            group: .cloudContainers,
            reason: Reason.accessTokens
        ),
        StructuralExclusion(
            id: "terraform-credentials",
            paths: ["~/.terraform.d/credentials.tfrc.json"],
            group: .cloudContainers,
            reason: Reason.terraformTokens
        ),
        StructuralExclusion(
            id: "aws-credentials",
            paths: ["~/.aws"],
            group: .cloudContainers,
            reason: Reason.credentials
        ),

        // MARK: - Toolchains & registries
        StructuralExclusion(
            id: "cargo-token",
            paths: ["~/.cargo/credentials.toml", "~/.cargo/credentials"],
            group: .toolchains,
            reason: Reason.registryToken
        ),
        StructuralExclusion(
            id: "pub-cache-credentials",
            paths: ["~/.pub-cache/credentials.json"],
            group: .toolchains,
            reason: Reason.credentials
        ),
        StructuralExclusion(
            id: "gradle-properties",
            paths: ["~/.gradle/gradle.properties"],
            group: .toolchains,
            reason: Reason.signingKeysTokens
        ),
        StructuralExclusion(
            id: "maven-settings",
            paths: ["~/.m2/settings.xml", "~/.m2/settings-security.xml"],
            group: .toolchains,
            reason: Reason.repositoryCredentials
        ),
        StructuralExclusion(
            id: "composer-auth",
            paths: ["~/.composer/auth.json"],
            group: .toolchains,
            reason: Reason.accessTokens
        ),
        StructuralExclusion(
            id: "npmrc",
            paths: ["~/.npmrc"],
            group: .toolchains,
            reason: Reason.registryToken
        ),
        StructuralExclusion(
            id: "pypirc",
            paths: ["~/.pypirc"],
            group: .toolchains,
            reason: Reason.registryToken
        ),
        StructuralExclusion(
            id: "nuget-plugins",
            paths: ["~/.nuget/plugins"],
            group: .toolchains,
            reason: Reason.credentialProviders
        ),
        StructuralExclusion(
            id: "dotnet-tools",
            paths: ["~/.dotnet/tools"],
            group: .toolchains,
            reason: Reason.installedTools
        ),
        StructuralExclusion(
            id: "android-keys",
            paths: ["~/.android/adbkey", "~/.android/debug.keystore"],
            group: .toolchains,
            reason: Reason.deviceKeys
        ),
        StructuralExclusion(
            id: "ivy-credentials",
            paths: ["~/.ivy2/.credentials"],
            group: .toolchains,
            reason: Reason.repositoryCredentials
        ),
        StructuralExclusion(
            id: "platformio-account",
            paths: ["~/.platformio/appstate.json"],
            group: .toolchains,
            reason: Reason.accountState
        ),

        // MARK: - Keys & certificates
        StructuralExclusion(
            id: "ssh-keys",
            paths: ["~/.ssh"],
            group: .keysCertificates,
            reason: Reason.sshKeys
        ),
        StructuralExclusion(
            id: "gnupg-keys",
            paths: ["~/.gnupg"],
            group: .keysCertificates,
            reason: Reason.gpgKeys
        ),
        StructuralExclusion(
            id: "aspnet-certs",
            paths: ["~/.aspnet"],
            group: .keysCertificates,
            reason: Reason.devCerts
        ),
        StructuralExclusion(
            id: "keychains",
            paths: ["~/Library/Keychains"],
            group: .keysCertificates,
            reason: Reason.keychains
        ),

        // MARK: - Editor settings
        StructuralExclusion(
            id: "vscode-settings",
            paths: [
                "~/Library/Application Support/Code/User/settings.json",
                "~/Library/Application Support/Code/User/keybindings.json",
                "~/Library/Application Support/Code/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "cursor-settings",
            paths: [
                "~/Library/Application Support/Cursor/User/settings.json",
                "~/Library/Application Support/Cursor/User/keybindings.json",
                "~/Library/Application Support/Cursor/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "windsurf-settings",
            paths: [
                "~/Library/Application Support/Windsurf/User/settings.json",
                "~/Library/Application Support/Windsurf/User/keybindings.json",
                "~/Library/Application Support/Windsurf/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "antigravity-settings",
            paths: [
                "~/Library/Application Support/Antigravity/User/settings.json",
                "~/Library/Application Support/Antigravity/User/keybindings.json",
                "~/Library/Application Support/Antigravity/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "vscode-insiders-settings",
            paths: [
                "~/Library/Application Support/Code - Insiders/User/settings.json",
                "~/Library/Application Support/Code - Insiders/User/keybindings.json",
                "~/Library/Application Support/Code - Insiders/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "kiro-settings",
            paths: [
                "~/Library/Application Support/Kiro/User/settings.json",
                "~/Library/Application Support/Kiro/User/keybindings.json",
                "~/Library/Application Support/Kiro/User/snippets",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "godot-editor-settings",
            paths: [
                "~/Library/Application Support/Godot/editor_settings-4.tres",
                "~/Library/Application Support/Godot/editor_settings-3.tres",
            ],
            group: .editorSettings,
            reason: Reason.userSettings
        ),
        StructuralExclusion(
            id: "jetbrains-settings",
            paths: ["~/Library/Application Support/JetBrains"],
            group: .editorSettings,
            reason: Reason.ideSettings
        ),
        StructuralExclusion(
            id: "zed-state",
            paths: ["~/Library/Application Support/Zed/db"],
            group: .editorSettings,
            reason: Reason.editorState
        ),
    ]
}
