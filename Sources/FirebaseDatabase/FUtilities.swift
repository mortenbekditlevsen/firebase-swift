//
//  File.swift
//  File
//
//  Created by Morten Bek Ditlevsen on 14/09/2021.
//

import Foundation
import Logging

nonisolated(unsafe) var logger = Logger(label: "[FirebaseDatabase]")

internal func FFLog(_ id: String, _ log: String) {
    logger.trace("\(id): \(log)")
}

internal func FFInfo(_ id: String, _ log: String) {
    logger.info("\(id): \(log)")
}

internal func FFWarn(_ id: String, _ log: String) {
    logger.warning("\(id): \(log)")
}

internal func FFDebug(_ id: String, _ log: String) {
    logger.debug("\(id): \(log)")
}

func tryParseStringToInt(_ str: String, integer: inout Int) -> Bool {
    // First do some cheap checks (NOTE: The below checks are significantly
    // faster than an equivalent regex :-( ).
    let length = str.count
    if length > 11 || length == 0 {
        return false
    }
    var value: Int64 = 0
    var negative = false
    var i = str.startIndex
    if str[i] == "-" {
        if length == 1 {
            return false
        }
        negative = true
        i = str.index(after: i)
    }
    for c in str[i...] {
        // Must be a digit, or '-' if it's the first char.
        if c < "0" || c > "9" {
            return false
        } else {
            let charValue = c.asciiValue! - ("0" as Character).asciiValue!
            value = value * 10 + Int64(charValue)
        }
    }

    value = (negative) ? -value : value;

    if value < Int32.min || value > Int32.max {
        return false
    } else {
        integer = Int(value)
        return true
    }
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
        if a == b { return .orderedSame }
        else if a == FUtilities.minName || b == FUtilities.maxName { return .orderedAscending }
        else if a == FUtilities.maxName || b == FUtilities.minName { return .orderedDescending }
        else {
            var aAsInt: Int = 0
            var bAsInt: Int = 0
            if tryParseStringToInt(a, integer: &aAsInt) {
                if tryParseStringToInt(b, integer: &bAsInt) {
                    if aAsInt > bAsInt {
                        return .orderedDescending
                    } else if aAsInt < bAsInt {
                        return .orderedAscending
                    } else if a.count > b.count {
                        return .orderedDescending
                    } else if a.count < b.count {
                        return .orderedAscending
                    } else {
                        return .orderedSame
                    }
                } else {
                    return .orderedAscending
                }
            } else if tryParseStringToInt(b, integer: &bAsInt) {
                return .orderedDescending
            } else {
                // Perform literal character by character search to prevent a > b &&
                // b > a issues. Note that calling -(NSString
                // *)decomposedStringWithCanonicalMapping also works.
                if a.utf16.lexicographicallyPrecedes(b.utf16) {
                    return .orderedAscending
                } else if b.utf16.lexicographicallyPrecedes(a.utf16) {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
        }
    }

    static func ieee754String(for number: NSNumber) -> String {
        var d = number.doubleValue
        let capacity = MemoryLayout<Double>.size
        let bytes = withUnsafePointer(to: &d) {
            $0.withMemoryRebound(to: UInt8.self, capacity: capacity) {
                Array(UnsafeBufferPointer(start: $0, count: capacity))
            }
        }

        let output = bytes
            .reversed()
            .map { String(format: "%02x", $0) }
            .joined()
        return output
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

