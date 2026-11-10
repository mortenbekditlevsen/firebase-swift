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

/// The protocol's framing over WebSocket messages: a JSON message longer
/// than a frame is sent as its number of frames, then the frames.
struct FrameAssembler {
    private var remaining = 0
    private var buffer = ""

    /// The complete message, if `frame` completes one.
    mutating func receive(_ frame: String) -> String? {
        guard remaining > 0 else {
            if frame.utf8.count <= 4, let count = Int(frame), count > 0 {
                remaining = count
                buffer = ""
                FFLog("I-RDB083006", "handleNewFrameCount: \(count)")
                return nil
            }
            return frame
        }
        buffer += frame
        remaining -= 1
        guard remaining == 0 else { return nil }
        defer { buffer = "" }
        return buffer
    }

    /// The frames to send `message` in, preceded by their count if there's
    /// more than one.
    static func frames(for message: String) -> [String] {
        var frames: [String] = []
        var start = message.startIndex
        while start < message.endIndex {
            let end = message.index(start, offsetBy: kWebsocketMaxFrameSize, limitedBy: message.endIndex)
                ?? message.endIndex
            frames.append(String(message[start ..< end]))
            start = end
        }
        if frames.count > 1 {
            frames.insert("\(frames.count)", at: 0)
        }
        return frames
    }
}

private let kAppCheckTokenHeader = "X-Firebase-AppCheck"
private let kUserAgentHeader = "User-Agent"
private let kGoogleAppIDHeader = "X-Firebase-GMPID"

/// The headers of the WebSocket upgrade request.
func connectionHeaders(userAgent: String, googleAppID: String, appCheckToken: String?) -> [String: String] {
    var headers = [
        kUserAgentHeader: userAgent,
        kGoogleAppIDHeader: googleAppID,
    ]
    if let appCheckToken {
        headers[kAppCheckTokenHeader] = appCheckToken
    }
    return headers
}
