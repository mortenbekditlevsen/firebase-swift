//
//  File.swift
//  File
//
//  Created by Morten Bek Ditlevsen on 14/09/2021.
//

import Foundation

private let emptyPath = FPath(with: "")

public struct FPath: Hashable {
    let pieceNum: Int
    let pieces: [String]

    static func relativePath(from outer: FPath, to inner: FPath) -> FPath {
        guard let outerFront = outer.getFront() else {
            return inner
        }
        let innerFront = inner.getFront()
        if outerFront == innerFront {
            return relativePath(from: outer.popFront(), to: inner.popFront())
        } else {
            fatalError("innerPath (\(inner)) is not within outerPath (\(outer))")
        }
    }

    public static var empty: FPath { emptyPath }

    static func path(string: String) -> FPath {
        FPath(with: string)
    }

    init(with path: String) {
        let pathPieces = path.components(separatedBy: "/")
        self.pieces = pathPieces.filter {
            !$0.isEmpty
        }
        self.pieceNum = 0
    }

    init(pieces: [String], andPieceNum pieceNum: Int) {
        self.pieces = pieces
        self.pieceNum = pieceNum
    }

    var components: [String] {
        Array(pieces[pieceNum...])
    }

    func getFront() -> String? {
        guard pieceNum < pieces.count else {
            return nil
        }
        return pieces[pieceNum]
    }

    func length() -> Int {
        pieces.count - pieceNum
    }

    func popFront() -> FPath {
        var newPieceNum = pieceNum
        if newPieceNum < pieces.count {
            newPieceNum += 1
        }
        return FPath(pieces: pieces, andPieceNum: newPieceNum)
    }

    func getBack() -> String? {
        pieces.last
    }

    func toString() -> String {
        toString(withTrailingSlash: false)
    }

    var description: String {
        toString()
    }

    func toStringWithTrailingSlash() -> String {
        toString(withTrailingSlash: true)
    }

    private func toString(withTrailingSlash trailingSlash: Bool) -> String {
        var pathString = ""
        for piece in pieces[pieceNum...] {
            pathString += "/\(piece)"
        }

        if pathString.isEmpty {
            return "/"
        } else {
            if trailingSlash {
                return pathString + "/"
            }
            return pathString
        }
    }

    func wireFormat() -> String {
        isEmpty ? "/" : pieces[pieceNum...].joined(separator: "/")
    }

    func parent() -> FPath? {
        guard pieceNum < pieces.count else {
            return nil
        }
        
        return FPath(pieces: Array(pieces[pieceNum..<(pieces.count - 1)]), andPieceNum: 0)
    }

    func child(_ childPathObj: FPath) -> FPath {
        var newPieces = Array(pieces[pieceNum...])
        newPieces.append(contentsOf: childPathObj.pieces[childPathObj.pieceNum...])
        return FPath(pieces: newPieces, andPieceNum: 0)
    }

    func child(fromString childPath: String) -> FPath {
        var newPieces = Array(pieces[pieceNum...])

        let pathPieces = childPath.components(separatedBy: "/")
        newPieces.append(contentsOf: pathPieces.filter {
            !$0.isEmpty
        })

        return FPath(pieces: newPieces, andPieceNum: 0)
    }

    var isEmpty: Bool {
        pieceNum >= pieces.count
    }

    func contains(_ other: FPath) -> Bool {
        guard self.length() <= other.length() else {
            return false
        }

        for (a, b) in zip(pieces[pieceNum...], other.pieces[other.pieceNum...]) {
            if a != b {
                return false
            }
        }
        return true
    }

    func compare(_ other: FPath) -> ComparisonResult {
        for (a, b) in zip(pieces[pieceNum...], other.pieces[other.pieceNum...]) {
            let comparison = FUtilities.compareKey(a, b)
            if comparison != .orderedSame {
                return comparison;
            }
        }
        if (self.length() < other.length()) {
            return .orderedAscending
        } else if other.length() < self.length() {
            return .orderedDescending
        } else {
            assert(self.length() == other.length(),
                     "Paths must be the same lengths")
            return .orderedSame
        }

    }
}
