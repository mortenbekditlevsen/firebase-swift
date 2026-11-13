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

import Foundation
import PinboardKit
import SwiftCrossUI

/// The board: writing a note, the notes, and who's here.
struct BoardView: View {
    let board: Board

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Signed in as \(board.userName)")
                        .font(.headline)
                    Spacer()
                    Button("Sign out") { board.signOut() }
                }
                ComposeView(board: board)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if board.notes.isEmpty {
                            Text("No notes yet. Pin the first one!")
                                .foregroundColor(.gray)
                        }
                        ForEach(board.notes) { note in
                            NoteView(board: board, note: note)
                        }
                    }
                }
            }
            Divider()
            PeopleView(board: board)
                .frame(width: 200)
        }
        .padding(16)
    }
}

/// The draft, its attachment, and the Pin button.
struct ComposeView: View {
    @Bindable var board: Board
    @Environment(\.chooseFile) var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What's on your mind?", text: $board.draft)
            HStack {
                Button(board.attachment == nil ? "Attach a file…" : "Change file…") {
                    Task {
                        if let file = await chooseFile(title: "Attach a file") {
                            board.attachment = file
                        }
                    }
                }
                if let attachment = board.attachment {
                    Text(attachment.lastPathComponent)
                    Button("Remove") { board.attachment = nil }
                }
                Spacer()
                Button("Pin") {
                    Task { await board.pin() }
                }
                .disabled(board.isBusy || board.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let progress = board.uploadProgress {
                ProgressView("Uploading…", value: progress)
            }
        }
    }
}

/// One note, with its attachment.
struct NoteView: View {
    let board: Board
    let note: Note
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.authorName)
                    .font(.headline)
                if let date = note.createdAt?.dateValue() {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if note.authorID == board.user?.uid {
                    Button("Delete") {
                        Task { await board.delete(note) }
                    }
                }
            }
            Text(note.text)
            if let attachment = note.attachment {
                HStack {
                    Text("📎 \(attachment.name) (\(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)))")
                        .font(.caption)
                    if attachment.isImage, board.previews[note.id] == nil {
                        Button("Show") {
                            Task { await board.preview(note) }
                        }
                    }
                    Button("Save…") {
                        Task {
                            if let file = await chooseFileSaveDestination(defaultFileName: attachment.name) {
                                await board.download(note, to: file)
                            }
                        }
                    }
                }
                if let image = board.previews[note.id] {
                    Image(image)
                        .resizable()
                        .frame(width: 320, height: 240)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(8)
    }
}

/// Who's on the board (the Realtime Database's `presence`).
struct PeopleView: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Here now")
                .font(.headline)
            ForEach(board.people) { person in
                HStack {
                    Text("● \(person.name)")
                        .foregroundColor(.green)
                    if person.typing {
                        Text("typing…")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
        }
    }
}
