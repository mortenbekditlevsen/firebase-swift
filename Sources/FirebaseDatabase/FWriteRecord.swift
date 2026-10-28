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

struct FWriteRecord: Hashable, Equatable, Sendable {
    enum Record: Hashable, Equatable {
        case overwrite(FNode)
        case merge(FCompoundWrite)
    }
    let record: Record
    let writeId: Int
    let path: FPath
    let visible: Bool
    init(path: FPath, overwrite: FNode, writeId: Int, visible: Bool) {
        self.path = path
        self.record = .overwrite(overwrite)
        self.writeId = writeId
        self.visible = visible
    }

    init(path: FPath, merge: FCompoundWrite, writeId: Int) {
        self.path = path
        self.record = .merge(merge)
        self.writeId = writeId
        self.visible = true
    }

    var debugDescription: String {
        switch record {
        case .overwrite(let overwrite):
            return "FWriteRecord { writeId = \(writeId), path = \(path), overwrite = \(overwrite), visible = \(visible) }"
        case .merge(let merge):
            return "FWriteRecord { writeId = \(writeId), path = \(path), merge = \(merge) }"
        }
    }
}
