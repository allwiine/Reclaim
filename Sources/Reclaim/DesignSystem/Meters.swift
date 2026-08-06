//
//  Meters.swift
//  Reclaim
//
//  Quantitative primitives: segmented capacity bars, the category
//  donut ring, and the small relative-size bars used in rows. All
//  animate value changes through Theme.smooth/springy.
//

import SwiftUI

/// One colored share of a segmented meter.
struct MeterSegment: Identifiable, Equatable {
    let id: String
    let fraction: Double
    let color: Color

    init(id: String, fraction: Double, color: Color) {
        self.id = id
        self.fraction = max(0, fraction)
        self.color = color
    }
}

// MARK: - Segmented bar

/// Horizontal stacked bar (disk usage, category shares). Segment
/// width changes animate smoothly.
struct SegmentedBar: View {
    let segments: [MeterSegment]
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, proxy.size.width * segment.fraction))
                }
            }
            .animation(Theme.smooth, value: segments)
        }
        .frame(height: height)
        .background(Theme.barTrack)
        .clipShape(Capsule())
    }
}

// MARK: - Donut ring

/// The overview's category donut. Sweeps in on appear and animates
/// share changes; the hole is left to the caller (overlay content).
struct SegmentedRing: View {
    let segments: [MeterSegment]
    var lineWidth: CGFloat = 17
    @State private var revealed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.barTrack.opacity(0.9), lineWidth: lineWidth)
            ForEach(Array(positioned.enumerated()), id: \.element.segment.id) { index, slice in
                Circle()
                    .trim(
                        from: slice.start,
                        to: revealed ? slice.end : slice.start
                    )
                    .stroke(
                        slice.segment.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        Theme.springy.delay(Double(index) * 0.04),
                        value: revealed
                    )
                    .animation(Theme.smooth, value: segments)
            }
        }
        .padding(lineWidth / 2)
        .onAppear { revealed = true }
    }

    private var positioned: [(segment: MeterSegment, start: Double, end: Double)] {
        var start = 0.0
        return segments.map { segment in
            let end = min(1, start + segment.fraction)
            defer { start = end }
            return (segment, start, end)
        }
    }
}

// MARK: - Row bar

/// Tiny relative-size bar under a row's byte count.
struct MiniBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: max(2, proxy.size.width * min(1, max(0, fraction))))
                .animation(Theme.smooth, value: fraction)
        }
        .frame(height: height)
        .background(Theme.barTrack, in: Capsule())
    }
}

// MARK: - Progress bar

/// Determinate progress with the accent sweep (scan/clean screens).
struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.progressGradient)
                .frame(width: max(0, proxy.size.width * min(1, max(0, fraction))))
                .animation(Theme.smooth, value: fraction)
        }
        .frame(height: height)
        .background(Color.white.opacity(0.09), in: Capsule())
    }
}

/// Rotating arc spinner for the scanning screen. Driven by a
/// TimelineView so the animation pauses whenever the view is not
/// visible (a `repeatForever` animation would keep invalidating).
struct ArcSpinner: View {
    var size: CGFloat = 62

    var body: some View {
        TimelineView(.animation) { context in
            let period = 0.9
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 3)
                .overlay {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(phase * 360))
                }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(localized("accessibility.inProgress", defaultValue: "In progress"))
    }
}

// MARK: - Previews

#Preview("Meters", traits: .sizeThatFitsLayout) {
    let segments = [
        MeterSegment(id: "a", fraction: 0.35, color: Color(hex: 0x67AAED)),
        MeterSegment(id: "b", fraction: 0.22, color: Color(hex: 0x69BA7C)),
        MeterSegment(id: "c", fraction: 0.18, color: Color(hex: 0xE4896A)),
        MeterSegment(id: "d", fraction: 0.12, color: Color(hex: 0xB093E5)),
    ]
    VStack(spacing: 24) {
        SegmentedBar(segments: segments)
            .frame(width: 300)
        SegmentedRing(segments: segments)
            .frame(width: 136, height: 136)
        MiniBar(fraction: 0.6, color: Theme.safe)
            .frame(width: 110)
        ProgressBar(fraction: 0.42)
            .frame(width: 300)
        ArcSpinner()
    }
    .padding(40)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
