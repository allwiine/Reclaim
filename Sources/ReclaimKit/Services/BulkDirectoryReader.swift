//
//  BulkDirectoryReader.swift
//  ReclaimKit
//
//  High-throughput directory enumeration via getattrlistbulk(2): one
//  syscall returns a batch of entries with their attributes already
//  attached (name, type, mtime, allocated size, link count, file id),
//  eliminating the per-entry stat that dominates enumerator walks.
//
//  This file carries the module's single deliberate `import Darwin`
//  (a syscall, not a framework dependency; see docs/ARCHITECTURE.md).
//  When the syscall is unsupported (some network volumes) the reader
//  falls back to FileManager for that directory.
//

import Darwin
import Foundation

/// One directory entry from a bulk read.
struct BulkEntry: Equatable {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var isRegularFile: Bool
    var modificationDate: Date?
    /// Allocated bytes for regular files; 0 for directories/symlinks.
    var allocatedBytes: Int64
    var linkCount: UInt32
    /// Inode number, for hard-link deduplication.
    var fileID: UInt64
}

/// Every readable entry of one directory, plus how many could not be read.
struct BulkDirectoryListing {
    var entries: [BulkEntry]
    var inaccessibleCount: Int
}

enum BulkDirectoryReader {
    // Attribute bits from <sys/attr.h>, redeclared as UInt32 so the
    // request/parse code is independent of how the C macros import.
    private static let attrCmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let attrCmnError: UInt32 = 0x2000_0000
    private static let attrCmnName: UInt32 = 0x0000_0001
    private static let attrCmnObjType: UInt32 = 0x0000_0008
    private static let attrCmnModTime: UInt32 = 0x0000_0400
    private static let attrCmnFileID: UInt32 = 0x0200_0000
    private static let attrFileLinkCount: UInt32 = 0x0000_0001
    private static let attrFileAllocSize: UInt32 = 0x0000_0004

    // Object types from <sys/vnode.h> `enum vtype`.
    private static let vREG: UInt32 = 1
    private static let vDIR: UInt32 = 2
    private static let vLNK: UInt32 = 5

    /// Read every entry of `path`. Tries getattrlistbulk first; falls
    /// back to FileManager when the volume does not support it. Returns
    /// nil only when the directory itself cannot be read at all.
    static func listing(atPath path: String, bufferSize: Int = 262_144) -> BulkDirectoryListing? {
        if let bulk = bulkListing(atPath: path, bufferSize: bufferSize) {
            return bulk
        }
        return fallbackListing(atPath: path)
    }

    // MARK: - getattrlistbulk path

    private static func bulkListing(atPath path: String, bufferSize: Int) -> BulkDirectoryListing? {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrCmnReturnedAttrs | attrCmnError | attrCmnName
            | attrCmnObjType | attrCmnModTime | attrCmnFileID
        request.fileattr = attrFileLinkCount | attrFileAllocSize

        var listing = BulkDirectoryListing(entries: [], inaccessibleCount: 0)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        while true {
            let batchCount = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if batchCount < 0 { return nil }
            if batchCount == 0 { break }

            var cursor = buffer
            for _ in 0..<batchCount {
                let recordLength = Int(cursor.loadUnaligned(as: UInt32.self))
                guard recordLength > 0 else { return nil }
                guard parseRecord(at: cursor, into: &listing) else { return nil }
                cursor += recordLength
            }
        }
        return listing
    }

    /// Fields follow the length word 4-byte-aligned, in the canonical
    /// order of getattrlist(2): RETURNED_ATTRS, ERROR, NAME, OBJTYPE,
    /// MODTIME, FILEID, then the file group: LINKCOUNT, ALLOCSIZE.
    /// The per-entry returned set says which are actually present
    /// (directories carry no file group, for example).
    private static func parseRecord(
        at record: UnsafeMutableRawPointer, into listing: inout BulkDirectoryListing
    ) -> Bool {
        var offset = MemoryLayout<UInt32>.size

        let returned = (record + offset).loadUnaligned(as: attribute_set_t.self)
        offset += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & attrCmnError != 0 {
            let errorCode = (record + offset).loadUnaligned(as: UInt32.self)
            offset += 4
            if errorCode != 0 {
                listing.inaccessibleCount += 1
                return true
            }
        }

        // Name and object type are non-negotiable; a volume that cannot
        // return them cannot be bulk-walked — fall back entirely.
        guard returned.commonattr & attrCmnName != 0,
              returned.commonattr & attrCmnObjType != 0 else { return false }

        let nameRefOffset = offset
        let nameRef = (record + offset).loadUnaligned(as: attrreference_t.self)
        offset += MemoryLayout<attrreference_t>.size
        let name = String(
            cString: (record + nameRefOffset + Int(nameRef.attr_dataoffset))
                .assumingMemoryBound(to: CChar.self)
        )

        let objType = (record + offset).loadUnaligned(as: UInt32.self)
        offset += 4

        var modificationDate: Date?
        if returned.commonattr & attrCmnModTime != 0 {
            let time = (record + offset).loadUnaligned(as: timespec.self)
            offset += MemoryLayout<timespec>.size
            modificationDate = Date(
                timeIntervalSince1970: TimeInterval(time.tv_sec)
                    + TimeInterval(time.tv_nsec) / 1_000_000_000
            )
        }

        var fileID: UInt64 = 0
        if returned.commonattr & attrCmnFileID != 0 {
            fileID = (record + offset).loadUnaligned(as: UInt64.self)
            offset += 8
        }

        var linkCount: UInt32 = 0
        if returned.fileattr & attrFileLinkCount != 0 {
            linkCount = (record + offset).loadUnaligned(as: UInt32.self)
            offset += 4
        }

        var allocatedBytes: Int64 = 0
        if returned.fileattr & attrFileAllocSize != 0 {
            allocatedBytes = (record + offset).loadUnaligned(as: Int64.self)
            offset += 8
        }

        listing.entries.append(BulkEntry(
            name: name,
            isDirectory: objType == vDIR,
            isSymlink: objType == vLNK,
            isRegularFile: objType == vREG,
            modificationDate: modificationDate,
            allocatedBytes: objType == vREG ? allocatedBytes : 0,
            linkCount: linkCount,
            fileID: fileID
        ))
        return true
    }

    // MARK: - FileManager fallback

    private static func fallbackListing(atPath path: String) -> BulkDirectoryListing? {
        let url = URL(filePath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .contentModificationDateKey, .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey, .linkCountKey,
        ]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return nil }

        var listing = BulkDirectoryListing(entries: [], inaccessibleCount: 0)
        for child in children {
            guard let values = try? child.resourceValues(forKeys: keys) else {
                listing.inaccessibleCount += 1
                continue
            }
            let isRegular = values.isRegularFile == true
            let linkCount = UInt32(values.linkCount ?? 1)
            // Inode only fetched for multi-link files — the one case
            // where deduplication needs it.
            var fileID: UInt64 = 0
            if linkCount > 1 {
                var status = stat()
                if lstat(child.path, &status) == 0 { fileID = UInt64(status.st_ino) }
            }
            listing.entries.append(BulkEntry(
                name: child.lastPathComponent,
                isDirectory: values.isDirectory == true && values.isSymbolicLink != true,
                isSymlink: values.isSymbolicLink == true,
                isRegularFile: isRegular,
                modificationDate: values.contentModificationDate,
                allocatedBytes: isRegular
                    ? Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    : 0,
                linkCount: linkCount,
                fileID: fileID
            ))
        }
        return listing
    }
}
