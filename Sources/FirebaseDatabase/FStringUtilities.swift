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
private func sha1(_ bytes: UnsafeBufferPointer<UInt8>) -> Data {
    var digest = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
    digest.withUnsafeMutableBytes { output in
        _ = CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count),
                    output.baseAddress!.assumingMemoryBound(to: UInt8.self))
    }
    return digest
}
#elseif os(Linux) || os(Windows) || os(Android) || os(FreeBSD)
import Crypto

/// The SHA-1 digest of `bytes`.
private func sha1(_ bytes: UnsafeBufferPointer<UInt8>) -> Data {
    Data(Insecure.SHA1.hash(data: UnsafeRawBufferPointer(bytes)))
}
#endif

import Foundation

enum FStringUtilities {
    /// The SHA-1 of the string's UTF-8, in base 64 (data hashes). Hashes the
    /// string's bytes in place: listens hash every node of their cached data.
    static func base64EncodedSha1(_ input: String) -> String  {
        var input = input
        return input.withUTF8(sha1).base64EncodedString()
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
