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

// XXX: Appears to be legacy - and not in use while we have commented out migration in FLevelDBStorageEngine
class FPendingPut: NSCoding {
    public let path: FPath
    public let priority: Any
    public let data: Any

    init(path: FPath, andData data: Any, andPriority priority: Any) {
        self.path = path
        self.priority = priority
        self.data = data
    }

    func encode(with coder: NSCoder) {
        coder.encode(path.description, forKey: "path")
        coder.encode(priority, forKey: "priority")
        coder.encode(data, forKey: "data")
    }
    public required init?(coder: NSCoder) {
        guard let path = coder.decodeObject(forKey: "path") as? String else {
            return nil
        }
        self.path = FPath(with: path)
        guard let priority = coder.decodeObject(forKey: "priority") else {
            return nil
        }
        self.priority = priority

        guard let data = coder.decodeObject(forKey: "data") else {
            return nil
        }
        self.data = data

    }
}



class FPendingPutPriority: NSCoding {
    public let path: FPath
    public let priority: Any
    init(path: FPath, andPriority priority: Any) {
        self.path = path
        self.priority = priority
    }

    func encode(with coder: NSCoder) {
        coder.encode(path.description, forKey: "path")
        coder.encode(priority, forKey: "priority")
    }
    public required init?(coder: NSCoder) {
        guard let path = coder.decodeObject(forKey: "path") as? String else {
            return nil
        }
        self.path = FPath(with: path)
        guard let priority = coder.decodeObject(forKey: "priority") else {
            return nil
        }
        self.priority = priority
    }
}

class FPendingUpdate: NSCoding {
    public let path: FPath
    public let data: [String: Any]
    init(path: FPath, andData data: [String: Any]) {
        self.path = path
        self.data = data
    }

    func encode(with coder: NSCoder) {
        coder.encode(path.description, forKey: "path")
        coder.encode(data, forKey: "data")
    }
    public required init?(coder: NSCoder) {
        guard let path = coder.decodeObject(forKey: "path") as? String else {
            return nil
        }
        self.path = FPath(with: path)
        guard let data = coder.decodeObject(forKey: "data") as? [String: Any] else {
            return nil
        }
        self.data = data
    }
}
