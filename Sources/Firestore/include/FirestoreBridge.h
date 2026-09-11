// Copyright 2025 Google LLC
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

#ifndef FIRESTORE_BRIDGE_H_
#define FIRESTORE_BRIDGE_H_

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "../core/src/api/source.h"
#include "../core/src/api/snapshot_metadata.h"

// Forward declarations of internal API types (not exposed to Swift).
namespace firebase {
namespace firestore {
namespace api {
class Firestore;
class DocumentReference;
class CollectionReference;
class Query;
class DocumentSnapshot;
class QuerySnapshot;
class WriteBatch;
class ListenerRegistration;
}  // namespace api
}  // namespace firestore
}  // namespace firebase

namespace firebase {
namespace firestore {
namespace swift_bridge {

// Forward declarations within the bridge namespace.
class FirestoreBridge;
class DocumentReferenceBridge;
class CollectionReferenceBridge;
class QueryBridge;
class DocumentSnapshotBridge;
class QuerySnapshotBridge;
class ListenerRegistrationBridge;

// Type aliases for template specializations (required by Swift C++ interop).
using StringVector = std::vector<std::string>;
using DocumentSnapshotBridgeVector = std::vector<DocumentSnapshotBridge>;

// ---------------------------------------------------------------------------
// DocumentSnapshotBridge
// ---------------------------------------------------------------------------
/// Wraps api::DocumentSnapshot. Exposes simple accessors to Swift.
class DocumentSnapshotBridge {
 public:
  DocumentSnapshotBridge() noexcept;
  ~DocumentSnapshotBridge() noexcept;

  // Copy/move
  DocumentSnapshotBridge(const DocumentSnapshotBridge&) noexcept;
  DocumentSnapshotBridge& operator=(const DocumentSnapshotBridge&) noexcept;
  DocumentSnapshotBridge(DocumentSnapshotBridge&&) noexcept;
  DocumentSnapshotBridge& operator=(DocumentSnapshotBridge&&) noexcept;

  /// Whether the document exists.
  bool exists() const noexcept;

  /// The document ID.
  std::string document_id() const noexcept;

  /// The snapshot metadata.
  api::SnapshotMetadata metadata() const noexcept;

  /// Creates a DocumentReferenceBridge for this snapshot's document.
  DocumentReferenceBridge create_reference() const noexcept;

 private:
  friend class DocumentReferenceBridge;
  friend class QuerySnapshotBridge;
  friend class QueryBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// ListenerRegistrationBridge
// ---------------------------------------------------------------------------
/// Wraps api::ListenerRegistration. Allows removing a snapshot listener.
class ListenerRegistrationBridge {
 public:
  ListenerRegistrationBridge() noexcept;
  ~ListenerRegistrationBridge() noexcept;

  // Move only — listener registrations are unique.
  ListenerRegistrationBridge(const ListenerRegistrationBridge&) = delete;
  ListenerRegistrationBridge& operator=(const ListenerRegistrationBridge&) = delete;
  ListenerRegistrationBridge(ListenerRegistrationBridge&&) noexcept;
  ListenerRegistrationBridge& operator=(ListenerRegistrationBridge&&) noexcept;

  /// Removes the listener.
  void Remove() noexcept;

 private:
  friend class DocumentReferenceBridge;
  friend class QueryBridge;
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// QuerySnapshotBridge
// ---------------------------------------------------------------------------
/// Wraps api::QuerySnapshot.
class QuerySnapshotBridge {
 public:
  QuerySnapshotBridge() noexcept;
  ~QuerySnapshotBridge() noexcept;

  QuerySnapshotBridge(const QuerySnapshotBridge&) noexcept;
  QuerySnapshotBridge& operator=(const QuerySnapshotBridge&) noexcept;
  QuerySnapshotBridge(QuerySnapshotBridge&&) noexcept;
  QuerySnapshotBridge& operator=(QuerySnapshotBridge&&) noexcept;

  /// Whether the snapshot is empty.
  bool empty() const noexcept;

  /// Number of documents.
  int64_t size() const noexcept;

  /// Snapshot metadata.
  api::SnapshotMetadata metadata() const noexcept;

  /// Get all document snapshots.
  DocumentSnapshotBridgeVector documents() const noexcept;

 private:
  friend class QueryBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// DocumentReferenceBridge
// ---------------------------------------------------------------------------
/// Wraps api::DocumentReference. Exposes read-only operations to Swift.
class DocumentReferenceBridge {
 public:
  DocumentReferenceBridge() noexcept;
  ~DocumentReferenceBridge() noexcept;

  DocumentReferenceBridge(const DocumentReferenceBridge&) noexcept;
  DocumentReferenceBridge& operator=(const DocumentReferenceBridge&) noexcept;
  DocumentReferenceBridge(DocumentReferenceBridge&&) noexcept;
  DocumentReferenceBridge& operator=(DocumentReferenceBridge&&) noexcept;

  /// The document ID (last path component).
  std::string document_id() const noexcept;

  /// The full path of this document.
  std::string path() const noexcept;

  /// The parent collection.
  CollectionReferenceBridge parent() const noexcept;

  /// Reads the document from the given source.
  /// Calls `callback(snapshot, error_message)`.
  /// If error_message is empty, the read succeeded.
  void GetDocument(
      api::Source source,
      std::function<void(DocumentSnapshotBridge, std::string)> callback
  ) const noexcept;

  /// Deletes this document.
  /// Calls `callback(error_message)` — empty string on success.
  void DeleteDocument(
      std::function<void(std::string)> callback
  ) const noexcept;

 private:
  friend class FirestoreBridge;
  friend class CollectionReferenceBridge;
  friend class DocumentSnapshotBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// QueryBridge
// ---------------------------------------------------------------------------
/// Wraps api::Query. Exposes query modifiers and read operations.
class QueryBridge {
 public:
  QueryBridge() noexcept;
  ~QueryBridge() noexcept;

  QueryBridge(const QueryBridge&) noexcept;
  QueryBridge& operator=(const QueryBridge&) noexcept;
  QueryBridge(QueryBridge&&) noexcept;
  QueryBridge& operator=(QueryBridge&&) noexcept;

  /// Execute the query and get results.
  void GetDocuments(
      api::Source source,
      std::function<void(QuerySnapshotBridge, std::string)> callback
  ) const noexcept;

  // Query modifiers — each returns a new QueryBridge.
  QueryBridge OrderBy(const std::string& field, bool descending) const noexcept;
  QueryBridge LimitToFirst(int32_t limit) const noexcept;
  QueryBridge LimitToLast(int32_t limit) const noexcept;

 protected:
  friend class FirestoreBridge;
  friend class CollectionReferenceBridge;
  friend class DocumentReferenceBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// CollectionReferenceBridge
// ---------------------------------------------------------------------------
/// Wraps api::CollectionReference. Adds collection-specific operations.
class CollectionReferenceBridge : public QueryBridge {
 public:
  CollectionReferenceBridge() noexcept;
  ~CollectionReferenceBridge() noexcept;

  CollectionReferenceBridge(const CollectionReferenceBridge&) noexcept;
  CollectionReferenceBridge& operator=(const CollectionReferenceBridge&) noexcept;
  CollectionReferenceBridge(CollectionReferenceBridge&&) noexcept;
  CollectionReferenceBridge& operator=(CollectionReferenceBridge&&) noexcept;

  /// The collection ID (last path component).
  std::string collection_id() const noexcept;

  /// The full path of this collection.
  std::string path() const noexcept;

  /// Get a document reference within this collection (auto-generated ID).
  DocumentReferenceBridge Document() const noexcept;

  /// Get a document reference by path within this collection.
  DocumentReferenceBridge Document(const std::string& document_path) const noexcept;

 private:
  friend class FirestoreBridge;
  friend class DocumentReferenceBridge;
  struct Impl;
  // Uses QueryBridge::impl_ for storage, plus a helper to downcast.
};

// ---------------------------------------------------------------------------
// FirestoreBridge
// ---------------------------------------------------------------------------
/// Wraps shared_ptr<api::Firestore>. Main entry point.
class FirestoreBridge {
 public:
  FirestoreBridge() noexcept;
  ~FirestoreBridge() noexcept;

  FirestoreBridge(const FirestoreBridge&) noexcept;
  FirestoreBridge& operator=(const FirestoreBridge&) noexcept;
  FirestoreBridge(FirestoreBridge&&) noexcept;
  FirestoreBridge& operator=(FirestoreBridge&&) noexcept;

  /// Get a collection reference by path.
  CollectionReferenceBridge GetCollection(
      const std::string& collection_path) const noexcept;

  /// Get a document reference by path.
  DocumentReferenceBridge GetDocument(
      const std::string& document_path) const noexcept;

  /// The database ID string.
  std::string database_id() const noexcept;

 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_BRIDGE_H_
