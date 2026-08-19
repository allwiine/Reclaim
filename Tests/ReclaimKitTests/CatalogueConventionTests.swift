//
//  CatalogueConventionTests.swift
//  ReclaimKitTests
//
//  Authoring conventions for the JSON catalogue, checked against the
//  SOURCE TREE (not the bundle): these rules govern the files
//  contributors actually write. docs/CATALOGUE.md explains each rule;
//  this suite enforces them.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Catalogue authoring conventions")
struct CatalogueConventionTests {
    /// Repo-relative path of the catalogue, derived from this file's
    /// location: Tests/ReclaimKitTests/ → repo root → Sources/….
    static let catalogueRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReclaimKit/Catalogue")

    @Test("Schemas are valid JSON and every property is documented", arguments: ["target", "exclusion"])
    func schemasAreDocumented(name: String) throws {
        let url = Self.catalogueRoot.appending(path: "schema/\(name).schema.json")
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let missing = Self.propertiesMissingDescriptions(in: schema, path: name)
        #expect(missing.isEmpty, "properties without a description: \(missing)")
    }

    /// Walks a JSON Schema and returns the paths of `properties`
    /// entries that define a value shape (type/enum/const) without a
    /// "description". Exempt: "$ref" entries (documented at the ref
    /// site), boolean schemas (`"command": false` forbids a key), and
    /// bare refinements (`{"minItems": 1}` inside a conditional).
    private static func propertiesMissingDescriptions(in node: Any, path: String) -> [String] {
        if let array = node as? [Any] {
            return array.flatMap { propertiesMissingDescriptions(in: $0, path: path) }
        }
        guard let object = node as? [String: Any] else { return [] }
        var missing: [String] = []
        if let properties = object["properties"] as? [String: Any] {
            for (key, sub) in properties {
                guard let subObject = sub as? [String: Any] else { continue }
                let definesShape = subObject["type"] != nil
                    || subObject["enum"] != nil
                    || subObject["const"] != nil
                if definesShape, subObject["description"] == nil, subObject["$ref"] == nil {
                    missing.append("\(path).\(key)")
                }
                missing += propertiesMissingDescriptions(in: subObject, path: "\(path).\(key)")
            }
        }
        for (key, value) in object where key != "properties" {
            missing += propertiesMissingDescriptions(in: value, path: "\(path).\(key)")
        }
        return missing.sorted()
    }
}
