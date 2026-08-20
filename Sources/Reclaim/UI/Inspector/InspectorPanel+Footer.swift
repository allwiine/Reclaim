//
//  InspectorPanel+Footer.swift
//  Reclaim
//
//  The panel's closing footnote: file and location counts, plus the
//  unreadable-entries caveat.
//

import ReclaimKit
import SwiftUI

extension InspectorPanel {
    @ViewBuilder
    func footer(_ status: TargetStatus) -> some View {
        if case .measured(let measurement, let resolved, _) = status {
            Text(footerLine(measurement, locations: resolved.count))
                .themeFont(.caption)
                .lineSpacing(2.5)
                .foregroundStyle(Theme.textQuaternary)
        }
    }

    private func footerLine(_ measurement: DiskMeasurement, locations: Int) -> String {
        var line = localized(
            "inspector.footer",
            defaultValue: "\(measurement.fileCount) files across \(locations) locations."
        )
        if measurement.inaccessibleItems > 0 {
            line += " " + localized(
                "inspector.footerUnreadable",
                defaultValue: "\(measurement.inaccessibleItems) entries could not be read — sizes are a lower bound."
            )
        }
        return line
    }
}
