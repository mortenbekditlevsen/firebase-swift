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

public struct AuthProtoMFAEnrollment: Decodable, Sendable {
    public var phoneInfo: String?
    
    public var mfaEnrollmentID: String?
    
    public var displayName: String?
    
    public var enrolledAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case phoneInfo
        case mfaEnrollmentID = "mfaEnrollmentId"
        case displayName
        case enrolledAt
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.phoneInfo = try container.decodeIfPresent(String.self, forKey: .phoneInfo)
        self.mfaEnrollmentID = try container.decodeIfPresent(String.self, forKey: .mfaEnrollmentID)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        if let enrolledAtString = try container.decodeIfPresent(String.self, forKey: .enrolledAt) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            self.enrolledAt = dateFormatter.date(from: enrolledAtString)
        } else {
            self.enrolledAt = nil
        }
    }
}
