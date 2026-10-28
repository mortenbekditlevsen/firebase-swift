/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#if SWIFT_PACKAGE
  @_exported import FirebaseFirestoreInternalWrapper
#else
  @_exported import FirebaseFirestoreInternal
#endif // SWIFT_PACKAGE
import Foundation

// PORTING NOTE: Upstream Swift gets these from the ObjC completion-handler
// methods automatically; here they're written out.
public extension DocumentReference {
  /// Overwrites the document, creating it if it doesn't exist.
  func setData(_ documentData: [String: Any]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      setData(documentData) { error in
        continuation.resume(with: error.map { .failure($0) } ?? .success(()))
      }
    }
  }

  /// Writes to the document, merging `documentData` into any existing data if
  /// `merge` is true.
  func setData(_ documentData: [String: Any], merge: Bool) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      setData(documentData, merge: merge) { error in
        continuation.resume(with: error.map { .failure($0) } ?? .success(()))
      }
    }
  }

  /// Updates fields of an existing document. Fails if the document doesn't exist.
  func updateData(_ fields: [String: Any]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      updateData(fields) { error in
        continuation.resume(with: error.map { .failure($0) } ?? .success(()))
      }
    }
  }

  /// Deletes the document.
  func delete() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      delete { error in
        continuation.resume(with: error.map { .failure($0) } ?? .success(()))
      }
    }
  }
}
