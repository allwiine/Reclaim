//
//  StatusLabel.swift
//  Reclaim
//
//  Trailing status column of a target row: size, spinner, or a
//  human-readable state.
//

import ReclaimKit
import SwiftUI

struct StatusLabel: View {
    let status: TargetStatus

    var body: some View {
        switch status {
        case .idle:
            Text("—")
                .foregroundStyle(.tertiary)

        case .scanning:
            ProgressView()
                .controlSize(.small)

        case .measured(let measurement, _):
            if measurement.bytes == 0 {
                Text("Empty")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(measurement.bytes.formattedBytes)
                        .monospacedDigit()
                        .fontWeight(.medium)
                    Text("\(measurement.fileCount.formatted()) file\(measurement.fileCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .notInstalled:
            Text("Not installed")
                .foregroundStyle(.secondary)

        case .unmeasurable:
            Text("Size unknown")
                .foregroundStyle(.secondary)
                .help("The reclaimable size is only known after cleaning.")

        case .failed(let message):
            Label("Couldn't scan", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .help(message + "\n\nIf access was denied, grant Reclaim Full Disk Access in System Settings → Privacy & Security.")
        }
    }
}
