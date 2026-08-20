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
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .stroke(Color.white.opacity(0.075), lineWidth: 4)
            .background(Color.white.opacity(0.025))
        }
    }
}
