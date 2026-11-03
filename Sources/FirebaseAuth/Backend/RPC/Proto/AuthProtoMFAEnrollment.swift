// Copyright 2023 Google LLC
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

struct AuthProtoMFAEnrollment: Codable, Equatable, Sendable {
    var phoneInfo: String?

    /// Whether this is a TOTP enrollment. The backend sends `totpInfo` as an empty object.
    var isTOTP: Bool = false
    
    var mfaEnrollmentID: String?
    
    public var displayName: String?
    
    var enrolledAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case phoneInfo
        case totpInfo
        case mfaEnrollmentID = "mfaEnrollmentId"
        case displayName
        case enrolledAt
    }
    
    /// The backend's format for `enrolledAt`. Encoding uses it too, so a user saved with its
    /// enrollments decodes the same way.
    private static func dateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return dateFormatter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.phoneInfo = try container.decodeIfPresent(String.self, forKey: .phoneInfo)
        self.isTOTP = container.contains(.totpInfo)
        self.mfaEnrollmentID = try container.decodeIfPresent(String.self, forKey: .mfaEnrollmentID)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        if let enrolledAtString = try container.decodeIfPresent(String.self, forKey: .enrolledAt) {
            self.enrolledAt = Self.dateFormatter().date(from: enrolledAtString)
        } else {
            self.enrolledAt = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(phoneInfo, forKey: .phoneInfo)
        if isTOTP {
            try container.encode([String: String](), forKey: .totpInfo)
        }
        try container.encodeIfPresent(mfaEnrollmentID, forKey: .mfaEnrollmentID)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(enrolledAt.map { Self.dateFormatter().string(from: $0) },
                                      forKey: .enrolledAt)
    }
}
