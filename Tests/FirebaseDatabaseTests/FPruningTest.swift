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

// Port of upstream's FirebaseDatabase/Tests/Unit/FPruningTest.m (13.1.1).

import XCTest

@testable import FirebaseDatabase

private let ABC_NODE = NODE(["a": ["aa": 1.1, "ab": 1.2], "b": 2, "c": 3] as [String: Any])
private let DEF_NODE = NODE(["d": 4, "e": 5, "f": 6])
private let A_NODE = NODE(["a": ["aa": 1.1, "ab": 1.2]])
private let D_NODE = NODE(["d": 4])
private let LARGE_NODE = FTestHelpers.leafNodeOfSize(5 * 1024 * 1024)
private let BC_NODE = ABC_NODE.updateImmediateChild("a", withNewChild: .empty)

class FPruningTest: XCTestCase {
  private func runWithDb(_ block: (FStorageEngine) -> Void) {
    do {
      // Run with level DB implementation
      // Port note: a directory per run, as test classes run in parallel.
      let engine = FLevelDBStorageEngine(path: "purge-tests-\(UUID().uuidString)")
      block(engine)
      engine.purgeEverything()
      engine.close()
    }
    do {
      // Run with mock implementation
      let engine = FMockStorageEngine()
      block(engine)
      engine.close()
    }
  }

  private func prune(_ pathStr: String) -> FPruneForest {
    FPruneForest.empty().prunePath(PATH(pathStr))
  }

  private func prune(_ path: String, exceptRelative except: [String]) -> FPruneForest {
    var pruneForest = FPruneForest.empty()
    pruneForest = pruneForest.prunePath(PATH(path))
    for keepPath in except {
      pruneForest = pruneForest.keepPath(PATH(path).child(fromString: keepPath))
    }
    return pruneForest
  }

  // Write document at root, prune it.
  func test010() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH(""), merge: false)
      engine.pruneCache(prune(""), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("")), FNode.empty)
    }
  }

  // Write document at /x, prune it via PruneForest for /x, at root.
  func test020() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.pruneCache(prune("x"), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("")), FNode.empty)
    }
  }

  // Write document at /x, prune it via PruneForest for root, at /x.
  func test030() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.pruneCache(prune(""), atPath: PATH("x"))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x")), FNode.empty)
    }
  }

  // Write document at /x, prune it via PruneForest for root, at root
  func test040() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.pruneCache(prune(""), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x")), FNode.empty)
    }
  }

  // Write document at /x/y, prune it via PruneForest for /y, at /x
  func test050() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x/y"), merge: false)
      engine.pruneCache(prune("y"), atPath: PATH("x"))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x/y")), FNode.empty)
    }
  }

  // Write abc at /x/y, prune /x/y except b,c via PruneForest for /x/y -b,c, at root
  func test060() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x/y"), merge: false)
      engine.pruneCache(prune("x/y", exceptRelative: ["b", "c"]), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x/y")), BC_NODE)
    }
  }

  // Write abc at /x/y, prune /x/y except b,c via PruneForest for /y -b,c, at /x
  func test070() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x/y"), merge: false)
      engine.pruneCache(prune("y", exceptRelative: ["b", "c"]), atPath: PATH("x"))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x/y")), BC_NODE)
    }
  }

  // Write abc at /x/y, prune /x/y except not-there via PruneForest for /x/y -d, at root
  func test080() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x/y"), merge: false)
      engine.pruneCache(prune("x/y", exceptRelative: ["not-there"]), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x/y")), FNode.empty)
    }
  }

  // Write abc at / and def at /a, prune all via PruneForest for / at root
  func test090() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH(""), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("a"), merge: false)
      engine.pruneCache(prune(""), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("")), FNode.empty)
    }
  }

  // Write abc at / and def at /a, prune all except b,c via PruneForest for root -b,c, at root
  func test100() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH(""), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("a"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["b", "c"]), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("")), BC_NODE)
    }
  }

  // Write abc at /x and def at /x/a, prune /x except b,c via PruneForest for /x -b,c, at root
  func test110() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("x", exceptRelative: ["b", "c"]), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x")), BC_NODE)
    }
  }

  // Write abc at /x and def at /x/a, prune /x except b,c via PruneForest for root -b,c, at /x
  func test120() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["b", "c"]), atPath: PATH("x"))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x")), BC_NODE)
    }
  }

  // Write abc at /x and def at /x/a, prune /x except a via PruneForest for /x -a, at root
  func test130() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        ABC_NODE.updateImmediateChild("a", withNewChild: DEF_NODE))
      engine.pruneCache(prune("x", exceptRelative: ["a"]), atPath: PATH(""))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateImmediateChild("a", withNewChild: DEF_NODE))
    }
  }

  // Write abc at /x and def at /x/a, prune /x except a via PruneForest for root -a, at /x
  func test140() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["a"]), atPath: PATH("x"))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateImmediateChild("a", withNewChild: DEF_NODE))
    }
  }

  // Write abc at /x and def at /x/a, prune /x except a/d via PruneForest for /x -a/d, at root
  func test150() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("x", exceptRelative: ["a/d"]), atPath: PATH(""))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateImmediateChild("a", withNewChild: D_NODE))
    }
  }

  // Write abc at /x and def at /x/a, prune /x except a/d via PruneForest for / -a/d, at /x
  func test160() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["a/d"]), atPath: PATH("x"))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateImmediateChild("a", withNewChild: D_NODE))
    }
  }

  // Write abc at /x and def at /x/a/aa, prune /x except a via PruneForest for /x -a, at root
  func test170() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a/aa"), merge: false)
      engine.pruneCache(prune("x", exceptRelative: ["a"]), atPath: PATH(""))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        A_NODE.updateChild(PATH("a/aa"), withNewChild: DEF_NODE))
    }
  }

  // Write abc at /x and def at /x/a/aa, prune /x except a via PruneForest for / -a, at /x
  func test180() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a/aa"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["a/aa"]), atPath: PATH("x"))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateChild(PATH("a/aa"), withNewChild: DEF_NODE))
    }
  }

  // Write abc at /x and def at /x/a/aa, prune /x except a/aa via PruneForest for /x -a/aa, at root
  func test190() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a/aa"), merge: false)
      engine.pruneCache(prune("x", exceptRelative: ["a/aa"]), atPath: PATH(""))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateChild(PATH("a/aa"), withNewChild: DEF_NODE))
    }
  }

  // Write abc at /x and def at /x/a/aa, prune /x except a/aa via PruneForest for / -a/aa, at /x
  func test200() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(DEF_NODE, atPath: PATH("x/a/aa"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["a/aa"]), atPath: PATH("x"))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateChild(PATH("a/aa"), withNewChild: DEF_NODE))
    }
  }

  // Write large node at /x, prune x via PruneForest for x at root
  func test210() {
    runWithDb { engine in
      engine.updateServerCache(LARGE_NODE, atPath: PATH("x"), merge: false)
      engine.pruneCache(prune("x"), atPath: PATH(""))
      XCTAssertEqual(engine.serverCache(atPath: PATH("x")), FNode.empty)
    }
  }

  // Write abc at x and large node at /x/a, prune x except a via PruneForest for / -a, at x
  func test220() {
    runWithDb { engine in
      engine.updateServerCache(ABC_NODE, atPath: PATH("x"), merge: false)
      engine.updateServerCache(LARGE_NODE, atPath: PATH("x/a"), merge: false)
      engine.pruneCache(prune("", exceptRelative: ["a"]), atPath: PATH("x"))
      XCTAssertEqual(
        engine.serverCache(atPath: PATH("x")),
        FNode.empty.updateImmediateChild("a", withNewChild: LARGE_NODE))
    }
  }
}
