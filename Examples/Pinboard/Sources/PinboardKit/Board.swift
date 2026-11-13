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

import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
import Observation

/// The app's state, and everything it does with Firebase:
///
/// - Auth: who's signed in (`authStateChanges`).
/// - Firestore: the notes, newest first (a query's `snapshots`).
/// - Functions: `pinNote` checks a note and adds it.
/// - Storage: attachments, uploaded with progress, and downloaded.
/// - Realtime Database: who's here and who's typing, kept right by the
///   server when a client disconnects (`onDisconnect`).
@MainActor
@Observable
package final class Board {
    package struct Person: Identifiable {
        package var id: String
        package var name: String
        package var typing: Bool
    }

    package private(set) var user: User?
    package private(set) var notes: [Note] = []
    package private(set) var people: [Person] = []
    package var draft = "" {
        didSet {
            if draft.isEmpty != oldValue.isEmpty { setTyping(!draft.isEmpty) }
        }
    }
    package var attachment: URL?
    package private(set) var uploadProgress: Double?
    package private(set) var isBusy = false
    /// Shown in an alert, and cleared when it's dismissed.
    package var errorMessage: String?
    /// Downloaded images, by note.
    package private(set) var previews: [String: URL] = [:]

    package var userName: String {
        user?.displayName ?? user?.email ?? "Anonymous"
    }

    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []

    package init() {}

    // MARK: Auth

    /// Follows the signed-in user for the app's lifetime.
    package func run() async {
        for await user in Auth.auth().authStateChanges {
            endSession()
            self.user = user
            if let user { startSession(for: user) }
        }
    }

    package func signIn(email: String, password: String) async {
        await perform { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    package func createAccount(name: String, email: String, password: String) async {
        await perform {
            let user = try await Auth.auth().createUser(withEmail: email, password: password).user
            try await self.setName(name, of: user)
        }
    }

    package func signInAnonymously(name: String) async {
        await perform {
            let user = try await Auth.auth().signInAnonymously().user
            try await self.setName(name, of: user)
        }
    }

    package func signOut() {
        if let user {
            presence(of: user).removeValue()
        }
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setName(_ name: String, of user: User) async throws {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try await change.commitChanges()
        self.user = Auth.auth().currentUser
    }

    // MARK: Notes (Firestore, Functions, Storage)

    /// Pins the draft: `pinNote` adds the note, then the attachment (if any)
    /// goes to Storage, where `describeAttachment` notices it.
    package func pin() async {
        guard let user else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await perform {
            let pinNote = Functions.functions()
                .httpsCallable("pinNote", requestAs: PinRequest.self, responseAs: PinResponse.self)
            let note = try await pinNote(PinRequest(text: text, authorName: self.userName))
            if let file = self.attachment {
                try await self.upload(file, to: "attachments/\(user.uid)/\(note.id)/\(file.lastPathComponent)")
            }
            self.draft = ""
            self.attachment = nil
        }
    }

    package func delete(_ note: Note) async {
        await perform {
            if let attachment = note.attachment {
                try await Storage.storage().reference(withPath: attachment.path).delete()
            }
            try await Firestore.firestore().collection("notes").document(note.id).delete()
        }
    }

    /// Downloads an image attachment to show it.
    package func preview(_ note: Note) async {
        guard let attachment = note.attachment else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinboard-\(note.id)-\(attachment.name)")
        await perform {
            _ = try await Storage.storage().reference(withPath: attachment.path).write(toFile: file)
            self.previews[note.id] = file
        }
    }

    package func download(_ note: Note, to file: URL) async {
        guard let attachment = note.attachment else { return }
        await perform {
            _ = try await Storage.storage().reference(withPath: attachment.path).write(toFile: file)
        }
    }

    private func upload(_ file: URL, to path: String) async throws {
        let task = Self.uploadTask(file, to: path)
        uploadProgress = 0
        defer { uploadProgress = nil }
        let (_, events) = await task.observe()
        for try await event in events {
            switch event.status {
            case .progress:
                uploadProgress = event.progress?.fractionCompleted
            case .failure(let error):
                throw error
            case .success:
                return
            case .resume, .pause:
                break
            }
        }
    }

    /// The upload's task, to follow its progress. (In an async context,
    /// `putFile(from:metadata:)` is the overload that returns the metadata.)
    private nonisolated static func uploadTask(_ file: URL, to path: String) -> StorageUploadTask {
        var metadata = StorageMetadata()
        metadata.contentType = Attachment.contentType(for: file)
        return Storage.storage().reference(withPath: path).putFile(from: file, metadata: metadata)
    }

    // MARK: Listening

    private func startSession(for user: User) {
        sessionTasks = [
            Task { await self.listenToNotes() },
            Task { await self.listenToPeople() },
            Task { await self.keepPresence(of: user) },
        ]
    }

    private func endSession() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        notes = []
        people = []
        previews = [:]
    }

    private func listenToNotes() async {
        let query = Firestore.firestore().collection("notes")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
        do {
            for try await snapshot in query.snapshots {
                notes = snapshot.documents.compactMap { try? $0.data(as: Note.self) }
            }
        } catch {
            report(error)
        }
    }

    private func listenToPeople() async {
        let presence = Database.database().reference(withPath: "presence")
        do {
            for try await everyone in presence.values(as: [String: Presence]?.self) {
                people = (everyone ?? [:])
                    .map { Person(id: $0.key, name: $0.value.name, typing: $0.value.typing) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } catch {
            report(error)
        }
    }

    /// Adds this client to `presence` whenever it's connected, and has the
    /// server remove it again when the connection drops.
    private func keepPresence(of user: User) async {
        let database = Database.database()
        let entry = presence(of: user)
        do {
            for try await connected in database.reference(withPath: ".info/connected").values() {
                guard connected.value as? Bool == true else { continue }
                try await entry.onDisconnect.removeValueAndWait()
                entry.setValue(["name": userName, "typing": !draft.isEmpty])
            }
        } catch {
            report(error)
        }
    }

    private func setTyping(_ typing: Bool) {
        guard let user else { return }
        presence(of: user).child("typing").setValue(typing)
    }

    private func presence(of user: User) -> DatabaseReference {
        Database.database().reference(withPath: "presence/\(user.uid)")
    }

    // MARK: Errors

    private func perform(_ operation: @MainActor () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        let description = error.localizedDescription
        errorMessage = description.isEmpty ? String(describing: error) : description
    }
}
