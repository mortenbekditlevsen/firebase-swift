//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 28/05/2022.
//

import Foundation

@testable import FirebaseDatabaseSwiftCore
import XCTest

func NODE(_ dict: [String: Any]) -> FNode {
    FSnapshotUtilities.nodeFrom(dict)
}
func PATH(_ pathString: String) -> FPath {
    FPath(with: pathString)
}

let NEVER_SPLIT_STRATEGY: FCompoundHashSplitStrategy = { _ in false }

func splitAtPaths(_ paths: [FPath]) -> FCompoundHashSplitStrategy {
    { builder in
        paths.contains(builder.currentPath)
    }
}

class FCompoundHashTest: XCTestCase {
    func testEmptyNodeYieldsEmptyHash() {
        let hash = FCompoundHash.fromNode(node: .empty)

        XCTAssertEqual(hash.posts, [])
        XCTAssertEqual(hash.hashes, [ "" ])
    }

    func testCompoundHashIsAlwaysFollowedByEmptyHash() {
        let node = NODE(["foo" : "bar"])
        let hash = FCompoundHash.fromNode(node: node, splitStrategy: NEVER_SPLIT_STRATEGY)
        let expectedHash = FStringUtilities.base64EncodedSha1("(\"foo\":(string:\"bar\"))")

        XCTAssertEqual(hash.posts, [ PATH("foo") ]);
        XCTAssertEqual(hash.hashes, ([ expectedHash, "" ]))
    }

    func testCompoundHashCanSplitAtPriority() {
        let node = NODE([
            "foo" : ["!beforePriority" : "before", ".priority" : "prio", "afterPriority" : "after"],
            "qux" : "qux"
        ])
        let hash = FCompoundHash.fromNode(node: node,
                                          splitStrategy: splitAtPaths([PATH("foo/.priority")]))
        let firstHash = FStringUtilities.base64EncodedSha1(
            "(\"foo\":(\"!beforePriority\":(string:\"before\"),\".priority\":(string:\"prio\")))")
        let comp = FStringUtilities.base64EncodedSha1("(\"foo\":(\"!beforePriority\":(string:\"before\"),\".priority\":(string:\"prio\")))")
        XCTAssertEqual(firstHash, comp);
        let secondHash = FStringUtilities.base64EncodedSha1(
            "(\"foo\":(\"afterPriority\":(string:\"after\")),\"qux\":(string:\"qux\"))")
        XCTAssertEqual(hash.posts, [ PATH("foo/.priority"), PATH("qux") ])
        XCTAssertEqual(hash.hashes, [ firstHash, secondHash, "" ])
    }

    func testHashesPriorityLeafNodes() {
        let node = NODE(["foo" : [".value" : "bar", ".priority" : "baz"]])
        let hash = FCompoundHash.fromNode(node: node, splitStrategy: NEVER_SPLIT_STRATEGY)
        let expectedHash =
        FStringUtilities.base64EncodedSha1("(\"foo\":(priority:string:\"baz\":string:\"bar\"))")

        XCTAssertEqual(hash.posts, [ PATH("foo") ])
        XCTAssertEqual(hash.hashes, [ expectedHash, "" ])
    }

    func testHashingFollowsFirebaseKeySemantics() {
        let node = NODE(["1" : "one", "2" : "two", "10" : "ten"])
        // 10 is after 2 in Firebase key semantics, but would be before 2 in string semantics
        let hash = FCompoundHash.fromNode(node: node,
                                          splitStrategy: splitAtPaths([ PATH("2") ]))
        let firstHash =
        FStringUtilities.base64EncodedSha1("(\"1\":(string:\"one\"),\"2\":(string:\"two\"))")
        let secondHash = FStringUtilities.base64EncodedSha1("(\"10\":(string:\"ten\"))")
        XCTAssertEqual(hash.posts, [ PATH("2"), PATH("10") ])
        XCTAssertEqual(hash.hashes, [ firstHash, secondHash, "" ])
    }

    func testHashingOnChildBoundariesWorks() {
        let node = NODE(["bar" : ["deep" : "value"], "foo" : ["other-deep" : "value"]])
        let hash = FCompoundHash.fromNode(node: node,
                                          splitStrategy:  splitAtPaths([ PATH("bar/deep") ]))
        let firstHash =
        FStringUtilities.base64EncodedSha1("(\"bar\":(\"deep\":(string:\"value\")))")
        let secondHash = FStringUtilities.base64EncodedSha1("(\"foo\":(\"other-deep\":(string:\"value\")))")
        XCTAssertEqual(hash.posts, [ PATH("bar/deep"), PATH("foo/other-deep") ])
        XCTAssertEqual(hash.hashes, [ firstHash, secondHash, "" ])
    }

    func testCommasAreSetForNestedChildren() {
        let node = NODE(["bar" : ["deep" : "value"], "foo" : ["other-deep" : "value"]])
        let hash = FCompoundHash.fromNode(node: node, splitStrategy:NEVER_SPLIT_STRATEGY)
        let expectedHash = FStringUtilities.base64EncodedSha1("(\"bar\":(\"deep\":(string:\"value\")),\"foo\":(\"other-deep\":(string:\"value\")))")

        XCTAssertEqual(hash.posts, [ PATH("foo/other-deep") ])
        XCTAssertEqual(hash.hashes, [ expectedHash, "" ])
    }

    func testQuotedStringsAndKeys() {
        let node = NODE(["\"" : "\\", "\"\\\"\\" : "\"\\\"\\"])
        let hash = FCompoundHash.fromNode(node: node, splitStrategy:NEVER_SPLIT_STRATEGY)
        let expectedHash = FStringUtilities.base64EncodedSha1(
            "(\"\\\"\":(string:\"\\\\\"),\"\\\"\\\\\\\"\\\\\":(string:\"\\\"\\\\\\\"\\\\\"))")

        XCTAssertEqual(hash.posts, [ PATH("\"\\\"\\") ])
        XCTAssertEqual(hash.hashes, [ expectedHash, "" ])
    }

    func testDefaultSplitHasSensibleAmountOfHashes() {
        var dict: [String: String] = [:]
        for i in 0 ..< 500 {
            // roughly 15-20 bytes serialized per node, 10k total
            dict["\(i)"] = "value"
        }
        let node10k = NODE(dict)

        dict = [:]
        for i in 0 ..< 5_000 {
            // roughly 15-20 bytes serialized per node, 100k total
            dict["\(i)"] = "value"
        }
        let node100k = NODE(dict)

        dict = [:]
        for i in 0 ..< 50_000 {
            // roughly 15-20 bytes serialized per node, 1M total
            dict["\(i)"] = "value"
        }
        let node1M = NODE(dict);

        let hash10k = FCompoundHash.fromNode(node: node10k)
        let hash100k = FCompoundHash.fromNode(node: node100k)
        let hash1M = FCompoundHash.fromNode(node: node1M)
        XCTAssertEqual(Double(hash10k.hashes.count), 15, accuracy: 3)
        XCTAssertEqual(Double(hash100k.hashes.count), 50, accuracy: 5)
        XCTAssertEqual(Double(hash1M.hashes.count), 150, accuracy: 10)
    }
}
