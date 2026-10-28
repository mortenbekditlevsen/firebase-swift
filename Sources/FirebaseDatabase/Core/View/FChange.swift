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

struct FChange {
    public let type: DataEventType
    public let indexedNode: FIndexedNode
    public let childKey: String?
    public let prevKey: String?
    public let oldIndexedNode: FIndexedNode?

    init(type: DataEventType, indexedNode: FIndexedNode) {
        self.type = type
        self.indexedNode = indexedNode
        self.childKey = nil
        self.oldIndexedNode = nil
        self.prevKey = nil
    }

    init(type: DataEventType, indexedNode: FIndexedNode, childKey: String?) {
        self.type = type
        self.indexedNode = indexedNode
        self.childKey = childKey
        self.oldIndexedNode = nil
        self.prevKey = nil
    }

    init(type: DataEventType, indexedNode: FIndexedNode, childKey: String?, oldIndexedNode: FIndexedNode?) {
        self.type = type
        self.indexedNode = indexedNode
        self.childKey = childKey
        self.oldIndexedNode = oldIndexedNode
        self.prevKey = nil
    }

    private init(type: DataEventType, indexedNode: FIndexedNode, childKey: String?, oldIndexedNode: FIndexedNode?, prevKey: String?) {
        self.type = type
        self.indexedNode = indexedNode
        self.childKey = childKey
        self.oldIndexedNode = oldIndexedNode
        self.prevKey = prevKey
    }

    func change(prevKey: String?) -> FChange {
        FChange(type: type,
                indexedNode: indexedNode,
                childKey: childKey,
                oldIndexedNode: oldIndexedNode,
                prevKey: prevKey)
    }

    var description: String {
        "event: \(type.rawValue), data: \(indexedNode.node.val())"
    }
    
    var debugDescription: String {
        "event: \(type.rawValue), data: \(indexedNode.node.val())"
    }
}

/*


 */
