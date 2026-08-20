//
//  Entrance.swift
//  Reclaim
//
//  Fade-and-rise entrance animation used to stagger hero/dashboard
//  content in on appear, shared by several screens.
//

import SwiftUI

/// Fade-and-rise entrance used to stagger hero content in.
private struct Entrance: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // With Reduce Motion the content is simply present — no slide
            // or spring — instead of animating up into place.
            .opacity(reduceMotion ? 1 : (shown ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (shown ? 0 : 14))
            .animation(reduceMotion ? nil : Theme.springy.delay(delay), value: shown)
    }
}

extension View {
    func entrance(_ shown: Bool, delay: Double) -> some View {
        modifier(Entrance(shown: shown, delay: delay))
    }
}
