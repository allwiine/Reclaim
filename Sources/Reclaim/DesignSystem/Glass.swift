//
//  Glass.swift
//  Reclaim
//
//  Liquid Glass adoption for macOS 26 (Tahoe), gated with `#available`
//  so macOS 15–25 render exactly as before. The app stays dark-committed
//  and keeps its own accent CTA; glass is applied only to the floating
//  confirmation panel and the (already translucent) secondary controls,
//  where the system material fits the design rather than fighting it.
//

import SwiftUI

extension View {
    /// A floating panel/sheet surface: Liquid Glass on Tahoe, the solid
    /// raised fill on earlier systems (so the fallback is unchanged).
    @ViewBuilder
    func floatingSurface(
        cornerRadius: CGFloat,
        fallback: Color = Theme.surfaceRaised
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// An interactive control surface (secondary buttons, chips): Liquid
    /// Glass on Tahoe, the given fill on earlier systems.
    @ViewBuilder
    func controlGlass(
        cornerRadius: CGFloat,
        fallback: Color
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }
}
