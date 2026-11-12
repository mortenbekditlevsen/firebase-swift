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

// NOTE: If deployment target moved to iOS 13 or above, CommonCrypto could be skipped entirely
#if canImport(CommonCrypto)
import CommonCrypto

/// The SHA-1 digest of `bytes`.
private func sha1(_ bytes: UnsafeBufferPointer<UInt8>) -> SHA1Digest {
    var digest = SHA1Digest()
    withUnsafeMutableBytes(of: &digest.bytes) { output in
        _ = CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count),
                    output.baseAddress!.assumingMemoryBound(to: UInt8.self))
    }
    return digest
}
#elseif os(Linux) || os(Windows) || os(Android) || os(FreeBSD)
import Crypto

/// The SHA-1 digest of `bytes`.
private func sha1(_ bytes: UnsafeBufferPointer<UInt8>) -> SHA1Digest {
    var digest = SHA1Digest()
    Insecure.SHA1.hash(data: UnsafeRawBufferPointer(bytes)).withUnsafeBytes { hash in
        withUnsafeMutableBytes(of: &digest.bytes) { $0.copyMemory(from: hash) }
    }
    return digest
}
#endif

import Foundation

/// A SHA-1 digest, inline: data hashes are cached in nodes as these.
struct SHA1Digest: Sendable, Equatable {
    static func == (lhs: SHA1Digest, rhs: SHA1Digest) -> Bool {
        lhs.bytes == rhs.bytes
    }

    fileprivate(set) var bytes: (UInt64, UInt64, UInt32) = (0, 0, 0)

    /// In base 64, as data hashes are sent.
    var base64: String {
        var output: [UInt8] = []
        appendBase64(to: &output)
        return String(decoding: output, as: UTF8.self)
    }

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    /// Appends the digest in base 64 (with padding, as Foundation encodes it).
    func appendBase64(to output: inout [UInt8]) {
        withUnsafeBytes(of: bytes) { raw in
            let digest = raw.prefix(20)
            var index = digest.startIndex
            while index < digest.endIndex {
                let remaining = digest.endIndex - index
                let b0 = digest[index]
                let b1 = remaining > 1 ? digest[index + 1] : 0
                let b2 = remaining > 2 ? digest[index + 2] : 0
                output.append(Self.alphabet[Int(b0 >> 2)])
                output.append(Self.alphabet[Int((b0 & 0x03) << 4 | b1 >> 4)])
                output.append(remaining > 1 ? Self.alphabet[Int((b1 & 0x0f) << 2 | b2 >> 6)] : UInt8(ascii: "="))
                output.append(remaining > 2 ? Self.alphabet[Int(b2 & 0x3f)] : UInt8(ascii: "="))
                index += 3
            }
        }
    }
}

enum FStringUtilities {
    /// The SHA-1 of the string's UTF-8, in base 64 (data hashes). Hashes the
    /// string's bytes in place: listens hash every node of their cached data.
    static func base64EncodedSha1(_ input: String) -> String  {
        sha1(input).base64
    }

    static func sha1(_ input: String) -> SHA1Digest {
        var input = input
        return input.withUTF8(FirebaseDatabase.sha1)
    }

    static func sha1(_ bytes: [UInt8]) -> SHA1Digest {
        bytes.withUnsafeBufferPointer(FirebaseDatabase.sha1)
    }

    static func urlDecoded(_ url: String) -> String {
        let replaced = url.replacingOccurrences(of: "+", with: " ")
        // This is kind of a hack, but is generally how the js client works. We
        // could run into trouble if some piece is a correctly escaped %-sequence,
        // and another isn't. But, that's bad input anyways...
        if let decoded = replaced.removingPercentEncoding {
            return decoded
        } else {
            return replaced
        }
    }

    static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")
    static func urlEncoded(_ url: String) -> String {
        // Didn't seem like there was an Apple NSCharacterSet that had our version
        // of the encoding So I made my own, following RFC 2396
        // https://www.ietf.org/rfc/rfc2396.txt allowedCharacters = alphanum | "-" |
        // "_" | "~"
        url.addingPercentEncoding(withAllowedCharacters: allowedCharacters)!
    }

    static func sanitizedForUserAgent(_ str: String) -> String {
        str.replacingOccurrences(of: "/|_",
                                 with: "|",
                                 options: .regularExpression,
                                 range: str.startIndex..<str.endIndex)
    }
}
