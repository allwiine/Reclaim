//
//  VolumeSpaceTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Volume space")
struct VolumeSpaceTests {
    @Test("The home volume reports a sane capacity")
    func homeVolume() {
        let space = VolumeSpaceProbe().measure()

        let unwrapped = try? #require(space)
        guard let unwrapped else { return }
        #expect(unwrapped.totalBytes > 0)
        #expect(unwrapped.availableBytes > 0)
        #expect(unwrapped.availableBytes <= unwrapped.totalBytes)
        #expect(unwrapped.usedBytes == unwrapped.totalBytes - unwrapped.availableBytes)
    }

    @Test("A nonexistent path yields no measurement")
    func missingPath() {
        let space = VolumeSpaceProbe().measure(
            volumeContaining: URL(filePath: "/nonexistent/\(UUID().uuidString)")
        )
        #expect(space == nil)
    }
}
