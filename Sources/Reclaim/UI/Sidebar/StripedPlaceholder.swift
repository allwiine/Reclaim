//
//  StripedPlaceholder.swift
//  Reclaim
//
//  Diagonal-stripe placeholder for not-yet-measured numbers.
//

import SwiftUI

/// Diagonal-stripe placeholder for not-yet-measured numbers.
struct StripedPlaceholder: View {
    var body: some View {
        stripes
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusIconChip))
            .accessibilityLabel(localized("accessibility.notMeasuredYet", defaultValue: "Not measured yet"))
    }

    private var stripes: some View {
        GeometryReader { proxy in
            let step: CGFloat = 8
            Path { path in
                var x: CGFloat = -proxy.size.height
                while x < proxy.size.width + proxy.size.height {
                    path.move(to: CGPoint(x: x, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: x + proxy.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Theme.hairline, lineWidth: 4)
            .background(Theme.placeholderFill)
        }
    }
}
