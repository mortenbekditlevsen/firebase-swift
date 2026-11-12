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
import Logging

nonisolated(unsafe) var logger = Logger(label: "[FirebaseDatabase]")

// The messages are autoclosures, so payloads are only formatted when their
// level is logged.

internal func FFLog(_ id: String, _ log: @autoclosure () -> String) {
    logger.trace("\(id): \(log())")
}

internal func FFInfo(_ id: String, _ log: @autoclosure () -> String) {
    logger.info("\(id): \(log())")
}

internal func FFWarn(_ id: String, _ log: @autoclosure () -> String) {
    logger.warning("\(id): \(log())")
}

internal func FFDebug(_ id: String, _ log: @autoclosure () -> String) {
    logger.debug("\(id): \(log())")
}

func tryParseStringToInt(_ str: String, integer: inout Int) -> Bool {
    // Over the UTF-8 bytes: counting characters would cost more than the
    // parse. A key with anything but ASCII digits isn't an integer anyway.
    let utf8 = str.utf8
    if utf8.count > 11 || utf8.isEmpty {
        return false
    }
    var value: Int64 = 0
    var negative = false
    var digits = utf8[...]
    if digits.first == UInt8(ascii: "-") {
        if utf8.count == 1 {
            return false
        }
        negative = true
        digits = digits.dropFirst()
    }
    for byte in digits {
        // Must be a digit, or '-' if it's the first char.
        guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
            return false
        }
        value = value * 10 + Int64(byte - UInt8(ascii: "0"))
    }

    value = (negative) ? -value : value;

    if value < Int32.min || value > Int32.max {
        return false
    } else {
        integer = Int(value)
        return true
    }
}

/// Orders strings by their UTF-16 code units, as upstream (NSString) does,
/// comparing UTF-8 bytes: the two orders agree except between U+E000–U+FFFF
/// and characters beyond U+FFFF, whose surrogates come first in UTF-16.
func compareUTF16(_ a: String, _ b: String) -> ComparisonResult {
    // The bytes in place (native strings have them contiguous); copying the
    // strings for `withUTF8` would cost a retain and release per comparison.
    if let result = a.utf8.withContiguousStorageIfAvailable({ a in
        b.utf8.withContiguousStorageIfAvailable { b in compareUTF16(a, b) }
    }), let result {
        return result
    }
    var a = a
    var b = b
    return a.withUTF8 { a in b.withUTF8 { b in compareUTF16(a, b) } }
}

private func compareUTF16(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> ComparisonResult {
    for i in 0 ..< min(a.count, b.count) where a[i] != b[i] {
        let x = a[i], y = b[i]
        // Lead bytes EE–EF start U+E000–U+FFFF; F0–F4 start the others.
        if x >= 0xEE, y >= 0xEE, (x >= 0xF0) != (y >= 0xF0) {
            return x >= 0xF0 ? .orderedAscending : .orderedDescending
        }
        return x < y ? .orderedAscending : .orderedDescending
    }
    return a.count == b.count ? .orderedSame : (a.count < b.count ? .orderedAscending : .orderedDescending)
}

func firebaseJobsTroll() {
    FFLog("I-RDB095001", "password super secret; JFK conspiracy; Hello there! Having fun digging through Firebase? We're always hiring! jobs@firebase.com")
}

fileprivate let localUid = FAtomicNumber()

enum FUtilities {
    static func LUIDGenerator() -> Int {
        localUid.getAndIncrement()
    }

    static func setLoggingEnabled(_ enabled: Bool) {
        logger.logLevel = enabled ? .debug : .info
    }

    static func decodePath(_ pathString: String) -> String {
        let pieces = pathString.components(separatedBy: "/")
        var decodedPieces: [String] = []
        for piece in pieces where !piece.isEmpty {
            decodedPieces.append(FStringUtilities.urlDecoded(piece))
        }
        return "/" + decodedPieces.joined(separator: "/")
    }

    static func extractPathFromUrlString(_ url: String) -> String {
        var path: Substring = url[...]
        if let range = path.range(of: "//") {
            path = path[range.upperBound...]
        }
        if let pathIndex = path.range(of: "/")?.lowerBound {
            path = path[path.index(after: pathIndex)...]
        } else {
            path = ""
        }
        if let queryParamIndex = path.range(of: "?")?.lowerBound {
            path = path[..<queryParamIndex]
        }
        return String(path)
    }

    static func parseUrl(_ input: String) -> FParsedUrl {
        var url = input
        // For backwards compatibility, support URLs without schemes on iOS.
        if !url.contains("://") {
            url = "http://" + url
        }
        let originalPathString = self.extractPathFromUrlString(url)
        // Sanitize the database URL by removing the path component, which may
        // contain invalid URL characters.
        let sanitizedUrlWithoutPath: String
        if let lastMatch = url.range(of: originalPathString, options: .backwards) {
            sanitizedUrlWithoutPath = String(url[..<lastMatch.lowerBound])
        } else {
            sanitizedUrlWithoutPath = url
        }
        guard let urlComponents = URLComponents(string: sanitizedUrlWithoutPath) else {
            fatalError("Failed to parse database URL: \(url)")
        }
        var host = (urlComponents.host ?? "").lowercased()
        let namespace: String
        let secure: Bool
        if let port = urlComponents.port {
            secure = urlComponents.scheme == "https" || urlComponents.scheme == "wss"
            host += ":\(port)"
        } else {
            secure = true
        }
        let parts = (urlComponents.host ?? "").components(separatedBy: ".")
        if parts.count == 3 {
            namespace = parts[0].lowercased()
        } else {
            // Attempt to extract namespace from "ns" query param.
            let queryItems = urlComponents.queryItems ?? []
            var ns: String?
            for item in queryItems {
                if item.name == "ns" {
                    ns = item.value
                    break
                }
            }
            if let ns = ns {
                namespace = ns
            } else {
                namespace = parts[0].lowercased()
            }
        }
        let pathString = self.decodePath("/" + originalPathString)
        let path = FPath(with: pathString)
        let repoInfo = FRepoInfo(host: host, isSecure: secure, withNamespace: namespace)

        FFLog("I-RDB095002", "---> Parsed (\(url)) to: (\(repoInfo.description),\(repoInfo.connectionURL); ns=(\(repoInfo.namespace)); path=(\(path.description))")
        let parsedUrl = FParsedUrl(repoInfo: repoInfo, path: path)
        return parsedUrl
    }


    static let maxName = "[MAX_NAME]"
    static let minName = "[MIN_NAME]"

    static let errorMap: [String: String] = [
        "permission_denied" : "Permission Denied",
        "unavailable" : "Service is unavailable",
        kFErrorWriteCanceled : "Write cancelled by user"
    ]

    static let errorCodes: [String: Int] = [
        "permission_denied" : 1,
        "unavailable" : 2,
        kFErrorWriteCanceled : 3
    ]

    static func error(for status: String, reason: String?) -> Error? {
        guard status != kFWPResponseForActionStatusOk else {
            return nil
        }
        let code: Int
        let desc: String
        if let reason = reason {
            desc = reason
        } else if let reason = errorMap[status] {
            desc = reason
        } else {
            desc = status
        }

        // XXX TODO: Is 9999 a good default?
        code = errorCodes[status] ?? 9999
        return NSError(domain: kFErrorDomain,
                       code: code,
                       userInfo: [NSLocalizedDescriptionKey: desc])
    }

    static func randomDouble() -> Double {
        Double.random(in: 0..<1)
    }

    static func intForString(_ string: String) -> Int? {
        var intVal = 0
        if tryParseStringToInt(string, integer: &intVal) {
            return intVal
        }
        return nil
    }
    static func compareKey(_ a: String, _ b: String) -> ComparisonResult {
        KeyIndex.compare(KeyIndex(key: a), KeyIndex(key: b))
    }

    /// The double's IEEE 754 bits as 16 lowercase hex digits, most significant
    /// first (how data hashes represent numbers).
    static func ieee754String(for double: Double) -> String {
        let hex = String(double.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - hex.utf8.count) + hex
    }

    static func getJavascriptType(_ obj: Any) -> JavaScriptType {
        if obj is [String: Any] {
            return .object
        } else if obj is String {
            return .string
        } else if let number = obj as? NSNumber {
            // We used to just compare to @encode(BOOL) as suggested at
            // http://stackoverflow.com/questions/2518761/get-type-of-nsnumber, but
            // on arm64, @encode(BOOL) returns "B" instead of "c" even though
            // objCType still returns 'c' (signed char).  So check both.
            return type(of: number) == type(of: NSNumber(booleanLiteral: true)) ? .boolean : .number
        } else {
            return .null
        }
    }
}

