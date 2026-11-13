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

import FirebaseFirestore
import Foundation

/// A note on the board: a Firestore document in `notes`, which the `pinNote`
/// function creates.
package struct Note: Codable, Identifiable, Sendable {
    @DocumentID package var documentID: String?
    package var text: String
    package var authorID: String
    package var authorName: String
    package var createdAt: Timestamp?
    /// Set by the `describeAttachment` function once the file is uploaded.
    package var attachment: Attachment?

    package var id: String { documentID ?? "" }
}

/// A file attached to a note, in Storage at `path`.
package struct Attachment: Codable, Hashable, Sendable {
    package var path: String
    package var name: String
    package var size: Int
    package var contentType: String

    /// Whether the app can show it (SwiftCrossUI's `Image` reads these).
    package var isImage: Bool {
        ["image/png", "image/jpeg", "image/webp"].contains(contentType)
    }
}

/// Someone on the board right now: an entry in the Realtime Database's
/// `presence`, which disappears when they disconnect.
package struct Presence: Codable, Sendable {
    package var name: String
    package var typing: Bool
}

/// The `pinNote` function's request and response.
struct PinRequest: Encodable, Sendable {
    var text: String
    var authorName: String
}

struct PinResponse: Decodable, Sendable {
    var id: String
}

extension Attachment {
    /// The content type for an uploaded file, from its extension.
    static func contentType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "pdf": "application/pdf"
        case "txt", "md": "text/plain"
        default: "application/octet-stream"
        }
    }
}
