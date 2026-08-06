//
//  Formatters.swift
//  Reclaim
//
//  Shared display formatting. Keeping this in one place guarantees
//  every byte count in the app reads identically.
//

import Foundation

extension Int64 {
    /// File-style byte formatting ("1.24 GB"), matching Finder.
    var formattedBytes: String {
        formatted(.byteCount(style: .file))
    }
}
