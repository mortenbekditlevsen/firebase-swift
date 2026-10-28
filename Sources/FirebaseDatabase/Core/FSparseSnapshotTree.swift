// Copyright 2017 Google LLC
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

import Foundation

struct FSparseSnapshotTree {
    var value: FNode?
    var children: [String: FSparseSnapshotTree] = [:]

    func findPath(_ path: FPath) -> FNode? {
        if let value = value {
            return value.getChild(path)
        } else if let childKey = path.getFront(), !children.isEmpty {
            if let childTree = children[childKey] {
                return childTree.findPath(path.popFront())
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    mutating func rememberData(_ data: FNode, onPath path: FPath) {
        if path.isEmpty {
            value = data
            children = [:]
        } else if let value = value {
            self.value = value.updateChild(path, withNewChild: data)
        } else {
            guard let childKey = path.getFront() else {
                return
            }
            var child = children[childKey, default: FSparseSnapshotTree()]
            child.rememberData(data, onPath: path.popFront())
            children[childKey] = child
        }
    }

    mutating func forgetPath(_ path: FPath) -> Bool {
        guard let childKey = path.getFront() else {
            value = nil
            children = [:]
            return true
        }
        if let value {
            switch value.type {
            case .leaf:
                return false
            case .children(let children):
                for child in children {
                    self.rememberData(child.value, onPath: FPath(with: child.key.key))
                }
                // we've cleared out the value and set children. Call ourself
                // again to hit the next case
                return self.forgetPath(path)

            case .empty:
                // we've cleared out the value and set children. Call ourself
                // again to hit the next case
                return self.forgetPath(path)
            }
        } else if !children.isEmpty {
            let p = path.popFront()
            if var child = children[childKey] {
                let safeToRemove = child.forgetPath(p)
                if safeToRemove {
                    children.removeValue(forKey: childKey)
                }
            }
            if children.isEmpty {
                return true
            } else {
                return false
            }
        } else {
            return true
        }
    }

    func forEachTreeAtPath(_ prefixPath: FPath, do closure: (FPath, FNode) -> Void) {
        if let value = value {
            closure(prefixPath, value)
        } else {
            forEachChild { key, tree in
                let path = prefixPath.child(fromString: key)
                tree.forEachTreeAtPath(path, do: closure)
            }
        }
    }

    func forEachChild(_ closure: (String, FSparseSnapshotTree) -> Void) {
        for (key, tree) in children {
            closure(key, tree)
        }
    }
}
