//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 05/03/2022.
//

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
