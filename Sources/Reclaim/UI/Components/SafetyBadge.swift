//
//  SafetyBadge.swift
//  Reclaim
//
//  Small colored capsule communicating a target's SafetyLevel.
//

import ReclaimKit
import SwiftUI

struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        Text(level.title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .help(level.explanation)
            .accessibilityLabel("Safety: \(level.title)")
    }

    private var color: Color {
        switch level {
        case .safe: .green
        case .caution: .orange
        case .destructive: .red
        }
    }
}
