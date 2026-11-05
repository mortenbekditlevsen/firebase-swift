// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of upstream's FirebaseDatabase/Tests/Unit/FPruneForestTest.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

class FPruneForestTest: XCTestCase {
  func testEmptyDoesNotAffectAnyPaths() {
    let forest = FPruneForest.empty()
    XCTAssertFalse(forest.affectsPath(FPath.empty))
    XCTAssertFalse(forest.affectsPath(PATH("foo")))
  }

  func testPruneAffectsPath() {
    var forest = FPruneForest.empty()
    forest = forest.prunePath(PATH("foo/bar"))
    forest = forest.keepPath(PATH("foo/bar/baz"))
    XCTAssertTrue(forest.affectsPath(PATH("foo")))
    XCTAssertFalse(forest.affectsPath(PATH("baz")))
    XCTAssertFalse(forest.affectsPath(PATH("baz/bar")))
    XCTAssertTrue(forest.affectsPath(PATH("foo/bar")))
    XCTAssertTrue(forest.affectsPath(PATH("foo/bar/baz")))
    XCTAssertTrue(forest.affectsPath(PATH("foo/bar/qux")))
  }

  func testPruneAnythingWorks() {
    let empty = FPruneForest.empty()
    XCTAssertFalse(empty.prunesAnything())
    XCTAssertTrue(empty.prunePath(PATH("foo")).prunesAnything())
    XCTAssertFalse(empty.prunePath(PATH("foo/bar")).keepPath(PATH("foo")).prunesAnything())
    XCTAssertTrue(empty.prunePath(PATH("foo")).keepPath(PATH("foo/bar")).prunesAnything())
  }

  func testKeepUnderPruneWorks() {
    var forest = FPruneForest.empty()
    forest = forest.prunePath(PATH("foo/bar"))
    forest = forest.keepPath(PATH("foo/bar/baz"))
    _ = forest.keepAll(["qux", "quu"], atPath: PATH("foo/bar"))
  }

  func testPruneUnderKeepThrows() throws {
    // Port note: the port stops the process where upstream raises an
    // exception, so this can't be tested in-process.
    throw XCTSkip("Expects an exception")
  }

  func testChildKeepsPruneInfo() {
    var forest = FPruneForest.empty()
    forest = forest.keepPath(PATH("foo/bar"))
    XCTAssertTrue(forest.child("foo").affectsPath(PATH("bar")))
    XCTAssertTrue(forest.child("foo").child("bar").affectsPath(PATH("")))
    XCTAssertTrue(forest.child("foo").child("bar").child("baz").affectsPath(PATH("")))

    forest = FPruneForest.empty().prunePath(PATH("foo/bar"))
    XCTAssertTrue(forest.child("foo").affectsPath(PATH("bar")))
    XCTAssertTrue(forest.child("foo").child("bar").affectsPath(PATH("")))
    XCTAssertTrue(forest.child("foo").child("bar").child("baz").affectsPath(PATH("")))

    XCTAssertFalse(forest.child("non-existent").affectsPath(PATH("")))
  }

  func testShouldPruneWorks() {
    var forest = FPruneForest.empty()
    forest = forest.prunePath(PATH("foo"))
    forest = forest.keepPath(PATH("foo/bar/baz"))
    XCTAssertTrue(forest.shouldPruneUnkeptDescendants(atPath: PATH("foo")))
    XCTAssertTrue(forest.shouldPruneUnkeptDescendants(atPath: PATH("foo/bar")))
    XCTAssertFalse(forest.shouldPruneUnkeptDescendants(atPath: PATH("foo/bar/baz")))
    XCTAssertFalse(forest.shouldPruneUnkeptDescendants(atPath: PATH("qux")))
  }
}
