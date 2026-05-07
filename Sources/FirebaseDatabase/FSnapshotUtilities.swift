//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 11/10/2021.
//

import SortedCollections
import Foundation

public enum FSnapshotUtilities {
    enum FDataHashVersion {
        case v1
        case v2
    }

    static func nodeFrom(_ val: Any?) -> FNode {
        nodeFrom(val, priority: nil)
    }

    static func nodeFrom(_ val: Any?, priority: Any?) -> FNode {
        nodeFrom(val, priority: priority, withValidationFrom: "nodeFrom:priority:")
    }

    static func nodeFrom(_ val: Any?, withValidationFrom fn: String) -> FNode {
        var path: [String] = []
        return nodeFrom(val, priority: nil, withValidationFrom: fn, atDepth: 0, path: &path)
    }

    static func nodeFrom(_ val: Any?, priority: Any?, withValidationFrom fn: String) -> FNode {
        var path: [String] = []
        return nodeFrom(val, priority: priority, withValidationFrom: fn, atDepth: 0, path: &path)
    }

    static func nodeFrom(_ val: Any?, priority: Any?, withValidationFrom fn: String, atDepth depth: Int, path: inout [String]) -> FNode {
        internalNodeFrom(val, priority: priority, withValidationFrom: fn, atDepth: depth, path: &path)
    }

    static func compoundWriteFromDictionary(_ values: [String: Any], withValidationFrom fn: String) -> FCompoundWrite {
        var compoundWrite = FCompoundWrite.emptyWrite
        var updatePaths: [FPath] = []
        for (keyId, value) in values {
            let key = FValidation.validateFrom(fn, validUpdateDictionaryKey: keyId, withValue: value)
            let path = FPath(with: key)
            let node = FSnapshotUtilities.nodeFrom(value, withValidationFrom: fn)
            updatePaths.append(path)
            compoundWrite = compoundWrite.addWrite(node, atPath: path)
        }
        // Check that the update paths are not descendants of each other.
        updatePaths.sort { a, b in
            a.compare(b) == .orderedAscending
        }
        var prevPath: FPath? = nil
        for path in updatePaths {
            if let prev = prevPath, prev.contains(path) {
                fatalError("(\(fn)) Invalid path in object. Path (\(prev)) is an ancestor of (\(path)).")
            }
            prevPath = path
        }
        return compoundWrite
    }

     static func internalNodeFrom(_ val: Any?, priority: Any?, withValidationFrom fn: String, atDepth depth: Int, path: inout [String]) -> FNode {
         guard depth <= kFirebaseMaxObjectDepth else {
             let pathString = path[0..<100].joined(separator: ".")
             fatalError("(\(fn)) Max object depth exceeded: \(pathString)...")
         }
         guard let val else {
             return .empty
         }

         if (val as? NSNull) === NSNull() {
             return .empty
         }
         var value: Any = val
         FValidation.validateFrom(fn, isValidPriorityValue: priority as Any, withPath: path)
         var priority = FSnapshotUtilities.nodeFrom(priority)
         var isLeafNode = false
         if let dict = val as? [String: Any] {
             if let rawPriority = dict[kPayloadPriority] {
                 FValidation.validateFrom(fn, isValidPriorityValue: rawPriority, withPath: path)
                 priority = nodeFrom(rawPriority)
             }
             if let payload = dict[kPayloadValue] {
                 value = payload
                 if FValidation.validateFrom(fn, isValidLeafValue: value, withPath: path) {
                     isLeafNode = true
                 } else {
                     fatalError("(\(fn)) Invalid data type used with .value. Can only use NSString and NSNumber or be null. Found \(type(of: value)) instead.")
                 }
             }
         }
         if !isLeafNode && FValidation.validateFrom(fn, isValidLeafValue: value, withPath: path) {
             isLeafNode = true
         }

         if isLeafNode, let hashable = value as? AnyHashable {
             return FNode.leaf(hashable, priority: priority)
         }

         // Unlike with JS, we have to handle the dictionary and array cases
         // separately.

         if let dval = value as? [String: Any] {
             var children: [String: FNode] = .init(minimumCapacity: dval.count)

             // Avoid creating a million newPaths by appending to old one
             for keyId in dval.keys {
                 let key = FValidation.validateFrom(fn, validDictionaryKey: keyId, withPath: path)
                 if !key.hasPrefix(kPayloadMetadataPrefix) {
                     path.append(key)
                     let childNode = nodeFrom(dval[key], priority: nil, withValidationFrom: fn, atDepth: depth + 1, path: &path)
                     path.removeLast()
                     if !childNode.isEmpty {
                         children[key] = childNode
                     }
                 }
             }
             if children.isEmpty {
                 return .empty
             } else {
                 let dict = SortedDictionary(keysWithValues: children.map { (KeyIndex(key: $0.key), $0.value) })
                 return .children(dict, priority: priority)
             }
         } else if let aval = value as? [Any] {
             var children: [String: FNode] = .init(minimumCapacity: aval.count)

             for i in 0..<aval.count {
                 let key = "\(i)"
                 path.append(key)
                 let childNode = nodeFrom(aval[i], priority: nil, withValidationFrom: fn, atDepth: depth + 1, path: &path)
                 path.removeLast()

                 if !childNode.isEmpty {
                     children[key] = childNode
                 }
             }

             if children.isEmpty {
                 return .empty
             } else {
                 let dict = SortedDictionary(keysWithValues: children.map { (KeyIndex(key: $0.key), $0.value) })

                 return .children(dict, priority: priority)
             }
         } else {
             let pathString = path.prefix(50).joined(separator: ".")
             fatalError("(\(fn)) Cannot store object of type \(type(of: value)) at \(pathString). Can only store objects of type NSNumber, NSString, NSDictionary, and NSArray.")
         }
     }

    static func validatePriorityNode(_ priorityNode: FNode) {
        if priorityNode.isLeafNode() {
            let val = priorityNode.val()
            if let valDict = val as? [String: Any] {
                assert(valDict[kServerValueSubKey] != nil, "Priority can't be object unless it's a deferred value")
            } else {
                let jsType = FUtilities.getJavascriptType(val)
                assert(jsType == .string || jsType == .number, "Priority of unexpected type.")
            }
        } else {
            assert (priorityNode == .max || priorityNode.isEmpty, "Priority of unexpected type.")
        }
        // Don't call getPriority() on MAX_NODE to avoid hitting assertion.
        assert (priorityNode == .max || priorityNode.getPriority().isEmpty, "Priority nodes can't have a priority of their own.")
    }

    static func estimateSerializedNodeSize(_ node: FNode) -> Int {
        switch node.type {
        case .empty:
            return 4 // null keyword
        case let .leaf(value):
            return estimateLeafNodeSize(value, priority: node.getPriority())
        case let .children(children):
            var sum = 1 // opening brackets
            for (key, child) in children {
                sum += key.key.count
                sum += 4 // quotes around key and colon and (comma or closing bracket)
                sum += estimateSerializedNodeSize(child)
            }
            return sum
        }
    }

    static func estimateLeafNodeSize(_ value: Any, priority: FNode) -> Int {
        // These values are somewhat arbitrary, but we don't need an exact value so
        // prefer performance over exact value
        let valueSize: Int
        switch FUtilities.getJavascriptType(value) {
        case .number:
            valueSize = 8 // estimate each float with 8 bytes
        case .boolean:
            valueSize = 4 // true or false need roughly 4 bytes
        case .string:
            // If we are measuring bytes here then we should use the utf8 view here, right?
            valueSize = 2 + ((value as? String)?.utf8.count ?? 0) // add 2 for quotes
        default:
            fatalError("Unknown leaf value type: \(value)")
        }
        if priority.isEmpty {
            return valueSize
        } else {
            // Account for extra overhead due to the extra JSON object and the
            // ".value" and ".priority" keys, colons, comma
            let leafPriorityOverhead = 2 + 8 + 11 + 2 + 1;
            return leafPriorityOverhead + valueSize +
            estimateLeafNodeSize(priority.val(), priority: .empty)
        }
    }


//    static func appendHashRepresentation(for leafNode: FNode, to output: inout String, hashVersion: FDataHashVersion) {
//        if !leafNode.getPriority().isEmpty {
//            output += "priority:"
//            appendHashRepresentation(for: leafNode.getPriority(),
//                                        to: &output,
//                                        hashVersion: hashVersion)
//            output += ":"
//        }
//        let jsType = FUtilities.getJavascriptType(leafNode.val())
//        output += jsType.rawValue + ":"
//        switch jsType {
//        case .object:
//            fatalError("Unknown value for hashing: \(leafNode)")
//
//        case .boolean:
//            let numberVal = (leafNode.val() as? NSNumber) ?? NSNumber(booleanLiteral: false)
//            output += numberVal.boolValue ? "true" : "false"
//        case .number:
//            let numberVal = (leafNode.val() as? NSNumber) ?? NSNumber(integerLiteral: 0)
//
//            output += FUtilities.ieee754String(for: numberVal)
//        case .string:
//            let stringVal = (leafNode.val() as? String) ?? ""
//            switch hashVersion {
//            case .v1:
//                output += stringVal
//            case .v2:
//                appendHashV2Representation(for: stringVal, to: &output)
//            }
//        case .null:
//            ()
//        }
//    }

    static func appendHashRepresentation(for leafNode: FNode, to output: inout String, hashVersion: FDataHashVersion) {
        if !leafNode.getPriority().isEmpty {
            output += "priority:"
            appendHashRepresentation(for: leafNode.getPriority(),
                                        to: &output,
                                        hashVersion: hashVersion)
            output += ":"
        }
        let jsType = FUtilities.getJavascriptType(leafNode.val())
        output += jsType.rawValue + ":"
        switch jsType {
        case .object:
            fatalError("Unknown value for hashing: \(leafNode)")

        case .boolean:
            let numberVal = (leafNode.val() as? NSNumber) ?? NSNumber(booleanLiteral: false)
            output += numberVal.boolValue ? "true" : "false"
        case .number:
            let numberVal = (leafNode.val() as? NSNumber) ?? NSNumber(integerLiteral: 0)

            output += FUtilities.ieee754String(for: numberVal)
        case .string:
            let stringVal = (leafNode.val() as? String) ?? ""
            switch hashVersion {
            case .v1:
                output += stringVal
            case .v2:
                appendHashV2Representation(for: stringVal, to: &output)
            }
        case .null:
            ()
        }
    }


    static func appendHashV2Representation(for string: String, to output: inout String) {
        output += "\""
        output += string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        output += "\""
    }

}
