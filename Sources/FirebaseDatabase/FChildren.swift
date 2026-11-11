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

import SortedCollections

/// A node's children, in key order.
///
/// Up to `FChildren.arrayLimit` children are a sorted array, sized to fit;
/// more are a B-tree. As upstream's FImmutableSortedDictionary (and
/// Android's ArraySortedMap) do: most nodes have a few children, and a B-tree
/// node reserves room for 16 (in three allocations), so for 10k small objects
/// the arrays take about a tenth of the memory. Large children lists stay
/// trees, so changing one child doesn't copy the others.
/// A child: its key and node. (A struct, not a tuple: arrays of tuples are
/// copied and destroyed through the runtime's generic code.)
struct FChild: Sendable {
    var key: KeyIndex
    var value: FNode
}

struct FChildren: RandomAccessCollection, Hashable, Sendable, ExpressibleByDictionaryLiteral {
    typealias Element = (key: KeyIndex, value: FNode)
    typealias Index = Int

    /// The most children kept in an array.
    static let arrayLimit = 32

    private enum Storage: Sendable {
        case array([FChild])
        case tree(SortedDictionary<KeyIndex, FNode>)
    }

    private var storage: Storage

    init() {
        storage = .array([])
    }

    init(dictionaryLiteral elements: (KeyIndex, FNode)...) {
        self.init(keysWithValues: elements)
    }

    /// Children already in key order, without duplicate keys.
    init(sortedChildren children: [FChild]) {
        if children.count <= Self.arrayLimit {
            // Builders append, so the array may have twice the room it needs.
            storage = .array(children.capacity > children.count ? Array(unsafeUninitializedCapacity: children.count) {
                buffer, count in
                for (index, child) in children.enumerated() {
                    (buffer.baseAddress! + index).initialize(to: child)
                }
                count = children.count
            } : children)
        } else {
            storage = .tree(SortedDictionary(sortedKeysWithValues: children.lazy.map { ($0.key, $0.value) }))
        }
    }

    /// Children already in key order, without duplicate keys.
    init(sortedKeysWithValues elements: [Element]) {
        self.init(sortedChildren: elements.map { FChild(key: $0.key, value: $0.value) })
    }

    /// Children in any order, without duplicate keys.
    init(keysWithValues elements: some Sequence<(KeyIndex, FNode)>) {
        self.init(sortedKeysWithValues: elements.map { (key: $0.0, value: $0.1) }.sorted { $0.key < $1.key })
    }

    // MARK: Collection

    var startIndex: Int { 0 }

    var endIndex: Int { count }

    var count: Int {
        switch storage {
        case .array(let array): array.count
        case .tree(let tree): tree.count
        }
    }

    var isEmpty: Bool { count == 0 }

    subscript(position: Int) -> Element {
        switch storage {
        case .array(let array):
            return (array[position].key, array[position].value)
        case .tree(let tree):
            let element = tree[tree.index(tree.startIndex, offsetBy: position)]
            return (element.key, element.value)
        }
    }

    func makeIterator() -> Iterator {
        switch storage {
        case .array(let array): Iterator(storage: .array(array.makeIterator()))
        case .tree(let tree): Iterator(storage: .tree(tree.makeIterator()))
        }
    }

    struct Iterator: IteratorProtocol {
        fileprivate enum Storage {
            case array(IndexingIterator<[FChild]>)
            case tree(SortedDictionary<KeyIndex, FNode>.Iterator)
        }

        fileprivate var storage: Storage

        mutating func next() -> Element? {
            switch storage {
            case .array(var iterator):
                defer { storage = .array(iterator) }
                return iterator.next().map { ($0.key, $0.value) }
            case .tree(var iterator):
                defer { storage = .tree(iterator) }
                return iterator.next().map { ($0.key, $0.value) }
            }
        }
    }

    var keys: LazyMapCollection<FChildren, KeyIndex> { lazy.map(\.key) }

    var values: LazyMapCollection<FChildren, FNode> { lazy.map(\.value) }

    // MARK: Keys

    /// The position of `key`, if it's there.
    func index(forKey key: KeyIndex) -> Int? {
        switch storage {
        case .array(let array):
            let index = Self.insertionIndex(of: key, in: array)
            return index < array.count && array[index].key == key ? index : nil
        case .tree(let tree):
            return tree.index(forKey: key).map { tree.distance(from: tree.startIndex, to: $0) }
        }
    }

    subscript(key: KeyIndex) -> FNode? {
        get {
            switch storage {
            case .array(let array):
                let index = Self.insertionIndex(of: key, in: array)
                return index < array.count && array[index].key == key ? array[index].value : nil
            case .tree(let tree):
                return tree[key]
            }
        }
        set {
            if let newValue {
                updateValue(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    @discardableResult
    mutating func updateValue(_ value: FNode, forKey key: KeyIndex) -> FNode? {
        switch storage {
        case .array(var array):
            let index = Self.insertionIndex(of: key, in: array)
            if index < array.count && array[index].key == key {
                let old = array[index].value
                storage = .array([]) // Uniquely referenced, so it changes in place.
                array[index].value = value
                storage = .array(array)
                return old
            }
            if array.count == Self.arrayLimit {
                var tree = SortedDictionary(sortedKeysWithValues: array.lazy.map { ($0.key, $0.value) })
                tree[key] = value
                storage = .tree(tree)
            } else {
                storage = .array([])
                array.insert(FChild(key: key, value: value), at: index)
                storage = .array(array)
            }
            return nil
        case .tree(var tree):
            storage = .array([])
            defer { storage = .tree(tree) }
            return tree.updateValue(value, forKey: key)
        }
    }

    @discardableResult
    mutating func removeValue(forKey key: KeyIndex) -> FNode? {
        switch storage {
        case .array(var array):
            let index = Self.insertionIndex(of: key, in: array)
            guard index < array.count && array[index].key == key else { return nil }
            storage = .array([])
            let old = array.remove(at: index).value
            storage = .array(array)
            return old
        case .tree(var tree):
            storage = .array([])
            let old = tree.removeValue(forKey: key)
            // Back to an array when it's well below the limit (not at it, so
            // adding and removing one child doesn't convert each time).
            storage = tree.count <= Self.arrayLimit / 2 ? .array(tree.map { FChild(key: $0.key, value: $0.value) }) : .tree(tree)
            return old
        }
    }

    /// The first index whose key isn't less than `key`.
    private static func insertionIndex(of key: KeyIndex, in array: [FChild]) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let middle = (low + high) / 2
            if array[middle].key < key {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    // MARK: Equality

    static func == (lhs: FChildren, rhs: FChildren) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.elementsEqual(rhs) { $0.key == $1.key && $0.value == $1.value }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for (key, value) in self {
            hasher.combine(key)
            hasher.combine(value)
        }
    }
}
