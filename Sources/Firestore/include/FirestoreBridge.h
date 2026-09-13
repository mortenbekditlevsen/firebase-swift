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
#include <utility>
#include <vector>

#include "../core/src/api/source.h"
#include "../core/src/api/snapshot_metadata.h"

// C-style callback typedefs for Swift interop.
// Swift C++ interop cannot pass C++ types through @convention(c) function
// pointers. We use void* for the snapshot (caller must cast) and const char*
// for the error string.

/// Callback for document snapshot results.
/// snapshot: opaque pointer to a heap-allocated DocumentSnapshotBridge (caller owns).
/// error: null-terminated C string, empty string "" means no error.
typedef void (*DocumentSnapshotCallback)(
    void* context,
    void* snapshot,
    const char* error);

/// Callback for query snapshot results.
typedef void (*QuerySnapshotCallback)(
    void* context,
    void* snapshot,
    const char* error);

/// Callback for error-only results.
typedef void (*ErrorCallback)(
    void* context,
    const char* error);

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
class BridgeFieldValue;

// Type aliases for template specializations (required by Swift C++ interop).
using StringVector = std::vector<std::string>;
using DoubleVector = std::vector<double>;
using DocumentSnapshotBridgeVector = std::vector<DocumentSnapshotBridge>;
using BridgeFieldValueVector = std::vector<BridgeFieldValue>;
using BridgeFieldValueMapEntry = std::pair<std::string, BridgeFieldValue>;
using BridgeFieldValueMap = std::vector<BridgeFieldValueMapEntry>;

// ---------------------------------------------------------------------------
// BridgeFieldValue — a Swift-constructable value type for document data
// ---------------------------------------------------------------------------
/// Represents a single Firestore value that Swift can construct and pass
/// through the C++ bridge. Uses a tagged-union approach with simple types.
class BridgeFieldValue {
 public:
  enum class Tag : int32_t {
    Null = 0,
    Boolean,
    Integer,     // int64_t
    Double,
    String,
    Blob,        // raw bytes as std::string
    Timestamp,   // seconds + nanoseconds
    GeoPoint,    // latitude + longitude
    Array,
    Map,
    Reference,   // document path string
    Vector,      // array of doubles for vector search

    // Sentinel field values (transforms)
    SentinelDelete,
    SentinelServerTimestamp,
    SentinelArrayUnion,    // elements stored in array_value_
    SentinelArrayRemove,   // elements stored in array_value_
    SentinelIncrement,     // operand in int64_value_ or double_value_
  };

  // Default constructor creates a Null value.
  BridgeFieldValue() noexcept;
  ~BridgeFieldValue() noexcept;
  BridgeFieldValue(const BridgeFieldValue&);
  BridgeFieldValue& operator=(const BridgeFieldValue&);
  BridgeFieldValue(BridgeFieldValue&&) noexcept;
  BridgeFieldValue& operator=(BridgeFieldValue&&) noexcept;

  // --- Factory methods for Swift to call ---
  static BridgeFieldValue Null() noexcept;
  static BridgeFieldValue FromBool(bool value) noexcept;
  static BridgeFieldValue FromInt64(int64_t value) noexcept;
  static BridgeFieldValue FromDouble(double value) noexcept;
  static BridgeFieldValue FromString(const std::string& value) noexcept;
  static BridgeFieldValue FromBlob(const std::string& bytes) noexcept;
  static BridgeFieldValue FromTimestamp(int64_t seconds,
                                        int32_t nanoseconds) noexcept;
  static BridgeFieldValue FromGeoPoint(double latitude,
                                        double longitude) noexcept;
  static BridgeFieldValue FromArray(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue FromMap(
      const BridgeFieldValueMap& entries) noexcept;
  static BridgeFieldValue FromReference(
      const std::string& document_path) noexcept;
  static BridgeFieldValue FromVector(
      const DoubleVector& doubles) noexcept;

  // Sentinel factories
  static BridgeFieldValue Delete() noexcept;
  static BridgeFieldValue ServerTimestamp() noexcept;
  static BridgeFieldValue ArrayUnion(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue ArrayRemove(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue IncrementInt(int64_t operand) noexcept;
  static BridgeFieldValue IncrementDouble(double operand) noexcept;

  // Accessors
  Tag tag() const noexcept { return tag_; }
  bool bool_value() const noexcept { return bool_value_; }
  int64_t int64_value() const noexcept { return int64_value_; }
  double double_value() const noexcept { return double_value_; }
  std::string string_value() const noexcept { return string_value_; }
  /// Returns blob data as a vector of bytes (for Swift interop).
  std::vector<uint8_t> blob_bytes() const noexcept {
    return std::vector<uint8_t>(string_value_.begin(), string_value_.end());
  }
  int64_t timestamp_seconds() const noexcept { return int64_value_; }
  int32_t timestamp_nanos() const noexcept { return int32_value_; }
  double geo_latitude() const noexcept { return double_value_; }
  double geo_longitude() const noexcept { return double2_value_; }
  BridgeFieldValueVector array_value() const noexcept {
    return array_value_;
  }
  BridgeFieldValueMap map_value() const noexcept {
    return map_value_;
  }
  DoubleVector vector_value() const noexcept {
    return vector_value_;
  }

 private:
  Tag tag_ = Tag::Null;
  bool bool_value_ = false;
  int64_t int64_value_ = 0;
  int32_t int32_value_ = 0;
  double double_value_ = 0.0;
  double double2_value_ = 0.0;
  std::string string_value_;
  BridgeFieldValueVector array_value_;
  BridgeFieldValueMap map_value_;
  DoubleVector vector_value_;
};

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

  /// Returns the document data as a BridgeFieldValueMap.
  /// Returns empty map if document doesn't exist.
  BridgeFieldValueMap data() const noexcept;

  /// Returns document data with server timestamp behavior.
  /// behavior: 0 = none (null), 1 = estimate (local write time), 2 = previous
  BridgeFieldValueMap data_with_server_timestamps(int32_t behavior) const noexcept;

  /// Gets a single field value by dot-separated path.
  /// Returns a Null BridgeFieldValue if the field doesn't exist.
  BridgeFieldValue get_field(const std::string& field_path) const noexcept;

  /// Gets a single field value with server timestamp behavior.
  BridgeFieldValue get_field_with_server_timestamps(
      const std::string& field_path, int32_t behavior) const noexcept;

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
/// Uses shared_ptr internally so it can be copied in Swift.
class ListenerRegistrationBridge {
 public:
  ListenerRegistrationBridge() noexcept;
  ~ListenerRegistrationBridge() noexcept;

  // Copyable via shared_ptr.
  ListenerRegistrationBridge(const ListenerRegistrationBridge&) noexcept;
  ListenerRegistrationBridge& operator=(const ListenerRegistrationBridge&) noexcept;
  ListenerRegistrationBridge(ListenerRegistrationBridge&&) noexcept;
  ListenerRegistrationBridge& operator=(ListenerRegistrationBridge&&) noexcept;

  /// Removes the listener.
  void Remove() noexcept;

 private:
  friend class DocumentReferenceBridge;
  friend class QueryBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
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
/// Wraps api::DocumentReference. Exposes read and write operations to Swift.
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

  // --- Write operations ---
  // These accept BridgeFieldValueMap and do the conversion internally.
  // They return an error string (empty on success, synchronous parsing
  // errors reported immediately; async write errors via callback).

  /// Set document data (overwrite).
  /// Returns error string for parse errors; empty string means parse OK
  /// and the write has been submitted (completion comes via callback).
  std::string SetData(
      const BridgeFieldValueMap& data,
      std::function<void(std::string)> callback) noexcept;

  /// Set document data with merge.
  std::string SetDataMerge(
      const BridgeFieldValueMap& data,
      std::function<void(std::string)> callback) noexcept;

  /// Set document data with explicit merge field list.
  std::string SetDataMergeFields(
      const BridgeFieldValueMap& data,
      const StringVector& merge_fields,
      std::function<void(std::string)> callback) noexcept;

  /// Update document fields.
  std::string UpdateData(
      const BridgeFieldValueMap& data,
      std::function<void(std::string)> callback) noexcept;

  // --- Fire-and-forget write overloads (callable from Swift) ---

  /// Set document data (overwrite), fire-and-forget.
  std::string SetData(const BridgeFieldValueMap& data) noexcept;

  /// Set document data with merge, fire-and-forget.
  std::string SetDataMerge(const BridgeFieldValueMap& data) noexcept;

  /// Set document data with explicit merge fields, fire-and-forget.
  std::string SetDataMergeFields(
      const BridgeFieldValueMap& data,
      const StringVector& merge_fields) noexcept;

  /// Update document fields, fire-and-forget.
  std::string UpdateData(const BridgeFieldValueMap& data) noexcept;

  /// Delete this document, fire-and-forget.
  void DeleteDocumentNoCallback() const noexcept;

  // --- C-callback-based async overloads (callable from Swift) ---

  /// Reads the document. Calls callback with context, snapshot, error.
  void GetDocumentC(
      api::Source source,
      void* context,
      DocumentSnapshotCallback callback) const noexcept;

  /// Adds a snapshot listener. Returns a ListenerRegistrationBridge.
  ListenerRegistrationBridge AddSnapshotListener(
      bool include_metadata_changes,
      void* context,
      DocumentSnapshotCallback callback) const noexcept;

  /// Deletes this document with C callback.
  void DeleteDocumentC(
      void* context,
      ErrorCallback callback) const noexcept;

  /// Set document data with C callback.
  std::string SetDataC(
      const BridgeFieldValueMap& data,
      void* context,
      ErrorCallback callback) noexcept;

  /// Set document data with merge, C callback.
  std::string SetDataMergeC(
      const BridgeFieldValueMap& data,
      void* context,
      ErrorCallback callback) noexcept;

  /// Update document fields with C callback.
  std::string UpdateDataC(
      const BridgeFieldValueMap& data,
      void* context,
      ErrorCallback callback) noexcept;

 private:
  friend class FirestoreBridge;
  friend class CollectionReferenceBridge;
  friend class DocumentSnapshotBridge;
  friend class UserDataReaderBridge;
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

  // --- C-callback-based async overloads (callable from Swift) ---

  /// Execute the query with C callback.
  void GetDocumentsC(
      api::Source source,
      void* context,
      QuerySnapshotCallback callback) const noexcept;

  /// Adds a snapshot listener. Returns a ListenerRegistrationBridge.
  ListenerRegistrationBridge AddSnapshotListener(
      bool include_metadata_changes,
      void* context,
      QuerySnapshotCallback callback) const noexcept;

  // --- Query filter operations ---
  QueryBridge WhereEqualTo(const std::string& field,
                           const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereNotEqualTo(const std::string& field,
                              const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereLessThan(const std::string& field,
                            const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereGreaterThan(const std::string& field,
                               const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereLessThanOrEqual(const std::string& field,
                                   const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereGreaterThanOrEqual(const std::string& field,
                                      const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereArrayContains(const std::string& field,
                                 const BridgeFieldValue& value) const noexcept;
  QueryBridge WhereIn(const std::string& field,
                      const BridgeFieldValueVector& values) const noexcept;
  QueryBridge WhereNotIn(const std::string& field,
                         const BridgeFieldValueVector& values) const noexcept;
  QueryBridge WhereArrayContainsAny(const std::string& field,
                                    const BridgeFieldValueVector& values) const noexcept;

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

  /// Returns the underlying QueryBridge for this collection.
  /// Swift C++ interop doesn't always expose base class members,
  /// so this provides explicit access to the query functionality.
  QueryBridge as_query() const noexcept;

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

  /// Creates a FirestoreBridge with a real api::Firestore instance.
  /// Uses empty credentials providers (unauthenticated) and no-op metadata.
  /// @param project_id The Firebase project ID.
  /// @param database_id The database name (usually "(default)").
  /// @param persistence_key A key for local persistence (usually the app name).
  static FirestoreBridge Create(
      const std::string& project_id,
      const std::string& database_id,
      const std::string& persistence_key) noexcept;

  /// Whether this bridge holds a valid Firestore instance.
  bool is_valid() const noexcept;

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
