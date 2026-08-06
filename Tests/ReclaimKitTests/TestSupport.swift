//
//  TestSupport.swift
//  ReclaimKitTests
//
//  Shared fixtures for filesystem-touching tests.
//

import Foundation

/// Run `body` with a fresh temporary directory that is removed afterwards.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "ReclaimTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

/// Create a file at `directory/name` containing `byteCount` bytes.
@discardableResult
func makeFile(in directory: URL, name: String, byteCount: Int) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    let data = Data(repeating: 0xAB, count: byteCount)
    try data.write(to: url)
    return url
}
