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

// Port of upstream's FirebaseDatabase/Tests/Unit/FPathTests.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

class FPathTests: XCTestCase {
  func testContains() {
    XCTAssertTrue(FPath(with: "/").contains(FPath(with: "/a/b/c")))
    XCTAssertTrue(FPath(with: "/a").contains(FPath(with: "/a/b/c")))
    XCTAssertTrue(FPath(with: "/a/b").contains(FPath(with: "/a/b/c")))
    XCTAssertTrue(FPath(with: "/a/b/c").contains(FPath(with: "/a/b/c")))

    XCTAssertFalse(FPath(with: "/a/b/c").contains(FPath(with: "/a/b")))
    XCTAssertFalse(FPath(with: "/a/b/c").contains(FPath(with: "/a")))
    XCTAssertFalse(FPath(with: "/a/b/c").contains(FPath(with: "/")))

    let pathPieces = ["a", "b", "c"]

    XCTAssertTrue(FPath(pieces: pathPieces, andPieceNum: 1).contains(FPath(with: "/b/c")))
    XCTAssertTrue(FPath(pieces: pathPieces, andPieceNum: 1).contains(FPath(with: "/b/c/d")))

    XCTAssertFalse(FPath(with: "/a/b/c").contains(FPath(with: "/b/c")))
    XCTAssertFalse(FPath(with: "/a/b/c").contains(FPath(with: "/a/c/b")))

    XCTAssertFalse(FPath(pieces: pathPieces, andPieceNum: 1).contains(FPath(with: "/a/b/c")))
    XCTAssertTrue(FPath(pieces: pathPieces, andPieceNum: 1).contains(FPath(with: "/b/c")))
    XCTAssertTrue(FPath(pieces: pathPieces, andPieceNum: 1).contains(FPath(with: "/b/c/d")))
  }

  func testPopFront() {
    XCTAssertEqual(FPath(with: "/a/b/c").popFront(), FPath(with: "/b/c"))
    XCTAssertEqual(FPath(with: "/a/b/c").popFront().popFront(), FPath(with: "/c"))
    XCTAssertEqual(FPath(with: "/a/b/c").popFront().popFront().popFront(), FPath(with: "/"))
    XCTAssertEqual(FPath(with: "/a/b/c").popFront().popFront().popFront().popFront(),
                   FPath(with: "/"))
  }

  func testParent() {
    XCTAssertEqual(FPath(with: "/a/b/c").parent(), FPath(with: "/a/b/"))
    XCTAssertEqual(FPath(with: "/a/b/c").parent()?.parent(), FPath(with: "/a/"))
    XCTAssertEqual(FPath(with: "/a/b/c").parent()?.parent()?.parent(), FPath(with: "/"))
    XCTAssertNil(FPath(with: "/a/b/c").parent()?.parent()?.parent()?.parent())
  }

  func testWireFormat() {
    XCTAssertEqual("/", FPath.empty.wireFormat())
    XCTAssertEqual("a/b/c", FPath(with: "/a/b//c/").wireFormat())
    XCTAssertEqual("b/c", FPath(with: "/a/b//c/").popFront().wireFormat())
  }

  func testComparison() {
    let pathsInOrder = [
      "1", "2", "10", "a", "a/1", "a/2", "a/10", "a/a", "a/aa", "a/b", "a/b/c", "b", "b/a",
    ]
    for i in 0 ..< pathsInOrder.count {
      let path1 = PATH(pathsInOrder[i])
      for j in (i + 1) ..< pathsInOrder.count {
        let path2 = PATH(pathsInOrder[j])
        XCTAssertEqual(path1.compare(path2), .orderedAscending)
        XCTAssertEqual(path2.compare(path1), .orderedDescending)
      }
      XCTAssertEqual(path1.compare(path1), .orderedSame)
    }
  }
}
