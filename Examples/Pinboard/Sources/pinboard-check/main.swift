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

// Runs Pinboard's flow without a window, against the emulators or a project:
// sign in, show up as present, pin a note with an attachment (Functions,
// Storage, the Storage trigger), download it again, delete it, sign out.
// Exits with 1 if any step fails.

import Foundation
import PinboardKit

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

@MainActor
func waitFor(_ what: String, in board: Board, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
        if let error = board.errorMessage {
            throw CheckFailure(description: "\(what): \(error)")
        }
        guard ContinuousClock.now < deadline else {
            throw CheckFailure(description: "timed out waiting for \(what)")
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    print("✓ \(what)")
}

@MainActor
func check() async throws {
    FirebaseSetup.configure()
    let board = Board()
    let running = Task { await board.run() }
    defer { running.cancel() }

    let name = "Pinboard check \(Int.random(in: 1000 ..< 10000))"
    await board.signInAnonymously(name: name)
    try await waitFor("signed in (Auth)", in: board) { board.user != nil }
    try await waitFor("present (Realtime Database)", in: board) {
        board.people.contains { $0.name == name }
    }

    board.draft = "x"
    try await waitFor("typing shown (Realtime Database)", in: board) {
        board.people.contains { $0.name == name && $0.typing }
    }

    let contents = Data("Attached by pinboard-check at \(Date())\n".utf8)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("pinboard-check.txt")
    try contents.write(to: file)
    let text = "Hello from \(name)"
    board.draft = text
    board.attachment = file
    await board.pin()
    try await waitFor("note pinned (Functions, Firestore)", in: board) {
        board.notes.contains { $0.text == text }
    }
    try await waitFor("attachment described (Storage, its trigger)", in: board) {
        board.notes.first { $0.text == text }?.attachment != nil
    }
    let note = board.notes.first { $0.text == text }!
    guard note.attachment?.size == contents.count, note.attachment?.contentType == "text/plain" else {
        throw CheckFailure(description: "unexpected attachment \(String(describing: note.attachment))")
    }

    let download = FileManager.default.temporaryDirectory.appendingPathComponent("pinboard-check-download.txt")
    await board.download(note, to: download)
    guard try Data(contentsOf: download) == contents else {
        throw CheckFailure(description: "the downloaded attachment differs")
    }
    print("✓ attachment downloaded (Storage)")

    await board.delete(note)
    try await waitFor("note deleted (Firestore, Storage)", in: board) {
        !board.notes.contains { $0.id == note.id }
    }

    board.signOut()
    try await waitFor("signed out", in: board) { board.user == nil }
}

do {
    try await check()
    print("Pinboard check passed")
} catch {
    print("Pinboard check failed: \(error)")
    exit(1)
}
