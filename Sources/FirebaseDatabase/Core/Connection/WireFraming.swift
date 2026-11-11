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

import NIOCore

/// The protocol's framing over WebSocket messages: a JSON message longer
/// than a frame is sent as its number of frames, then the frames.
struct FrameAssembler {
    private var remaining = 0
    private var buffer = ByteBuffer()

    /// The complete message, if `frame` completes one.
    mutating func receive(_ frame: DatabaseFrame) -> ByteBuffer? {
        guard remaining > 0 else {
            if frame.count <= 4, let count = Int(frame.string), count > 0 {
                remaining = count
                buffer.clear()
                FFLog("I-RDB083006", "handleNewFrameCount: \(count)")
                return nil
            }
            return frame.byteBuffer
        }
        frame.withUnsafeBytes { buffer.writeBytes($0) }
        remaining -= 1
        guard remaining == 0 else { return nil }
        defer { buffer = ByteBuffer() }
        return buffer
    }

    /// The frames to send `message` in, preceded by their count if there's
    /// more than one. Frames end at character boundaries, so each is valid
    /// UTF-8.
    static func frames(for message: ByteBuffer) -> [DatabaseFrame] {
        guard message.readableBytes > kWebsocketMaxFrameSize else { return [DatabaseFrame(message)] }
        var message = message
        var frames: [DatabaseFrame] = []
        while message.readableBytes > 0 {
            var length = min(kWebsocketMaxFrameSize, message.readableBytes)
            // Not before a continuation byte (10xxxxxx).
            while length < message.readableBytes,
                  let byte = message.getInteger(at: message.readerIndex + length, as: UInt8.self),
                  byte & 0xC0 == 0x80 {
                length -= 1
            }
            frames.append(DatabaseFrame(message.readSlice(length: length)!))
        }
        frames.insert(DatabaseFrame("\(frames.count)"), at: 0)
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
