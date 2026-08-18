//
//  Glass.swift
//  Reclaim
//
//  Liquid Glass surface helpers. The app targets macOS 26 (Tahoe), so
//  these are unconditional. Buttons use the native glass styles via the
//  `.rc*` helpers in Buttons.swift; this covers the floating chrome.
//

import SwiftUI

extension View {
    /// A floating panel/sheet surface — used by the confirmation sheet.
    func floatingSurface(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
