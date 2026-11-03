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
// pointers. We use void* for the snapshot (caller must cast), and report
// errors as a `firebase::firestore::Error` code (0 means OK) plus a message.

/// Callback for document snapshot results.
/// snapshot: opaque pointer to a heap-allocated DocumentSnapshotBridge (caller
/// owns), or null on error.
typedef void (*DocumentSnapshotCallback)(
    void* context,
    void* snapshot,
    int32_t error_code,
    const char* error_message);

/// Callback for query snapshot results.
typedef void (*QuerySnapshotCallback)(
    void* context,
    void* snapshot,
    int32_t error_code,
    const char* error_message);

/// Callback for aggregation results.
/// results: opaque pointer to a heap-allocated BridgeFieldValueVector (caller
/// owns) with one value per requested field, in order, or null on error.
typedef void (*AggregateCallback)(
    void* context,
    void* results,
    int32_t error_code,
    const char* error_message);

/// Callback for error-only results.
typedef void (*ErrorCallback)(
    void* context,
    int32_t error_code,
    const char* error_message);

/// Asks Swift for an Auth or App Check token. Swift must pass `request` to
/// the matching `Complete…TokenRequest` function exactly once, from any thread.
typedef void (*TokenRequestCallback)(
    void* context,
    bool force_refresh,
    void* request);

/// Releases a `context` that was passed to `FirestoreBridge::Create`.
typedef void (*ContextReleaseCallback)(void* context);

/// Reads up to `max_length` bytes of a bundle into `buffer`. Returns the
/// number of bytes read, 0 at the end, or -1 on an error.
typedef int64_t (*BundleReadCallback)(
    void* context,
    uint8_t* buffer,
    size_t max_length);

/// Reports the progress of loading a bundle. `state`: 0 = error,
/// 1 = in progress, 2 = success (upstream's `LoadBundleTaskState`).
typedef void (*LoadBundleProgressCallback)(
    void* context,
    int32_t state,
    uint32_t documents_loaded,
    uint32_t total_documents,
    uint64_t bytes_loaded,
    uint64_t total_bytes,
    int32_t error_code,
    const char* error_message);

/// Callback for a named query.
/// query: opaque pointer to a heap-allocated QueryBridge (caller owns), or
/// null if there's no query by that name.
typedef void (*NamedQueryCallback)(void* context, void* query);

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
class FilterBridge;

// Type aliases for template specializations (required by Swift C++ interop).
using StringVector = std::vector<std::string>;
using DoubleVector = std::vector<double>;
using DocumentSnapshotBridgeVector = std::vector<DocumentSnapshotBridge>;
using BridgeFieldValueVector = std::vector<BridgeFieldValue>;
using BridgeFieldValueMapEntry = std::pair<std::string, BridgeFieldValue>;
using BridgeFieldValueMap = std::vector<BridgeFieldValueMapEntry>;

/// A field path as its segments, e.g. {"a", "b.c"}. Swift splits dotted
/// strings itself, so a segment may contain dots.
using FieldPathSegments = StringVector;
using FieldPathVector = std::vector<FieldPathSegments>;
/// The data of an `updateData` call: field paths to new values.
using BridgeUpdateEntry = std::pair<FieldPathSegments, BridgeFieldValue>;
using BridgeUpdateData = std::vector<BridgeUpdateEntry>;

/// The local cache in the settings.
enum class CacheKind : int32_t {
  Persistent = 0,
  /// In memory, with eager garbage collection.
  MemoryEager,
  /// In memory, with LRU garbage collection.
  MemoryLru,
};

/// An aggregation of an aggregate query.
enum class AggregateKind : int32_t {
  Count = 0,
  Sum,
  Average,
};

/// An aggregation and its field (empty for `Count`).
using BridgeAggregateField = std::pair<AggregateKind, FieldPathSegments>;
using BridgeAggregateFields = std::vector<BridgeAggregateField>;

/// How `setData` treats fields that aren't in the new data.
enum class SetOption : int32_t {
  Overwrite = 0,
  /// Keep fields that aren't in the new data.
  Merge,
  /// Only write the fields in `merge_fields`.
  MergeFields,
};

/// Query filter operators, as in `core::FieldFilter::Operator`.
enum class FilterOperator : int32_t {
  LessThan = 0,
  LessThanOrEqual,
  Equal,
  NotEqual,
  GreaterThanOrEqual,
  GreaterThan,
  ArrayContains,
  In,
  ArrayContainsAny,
  NotIn,
};

// ---------------------------------------------------------------------------
// BridgeFieldValue — a Swift-constructable value type for document data
// ---------------------------------------------------------------------------
/// Represents a single Firestore value that Swift can construct and pass
/// through the C++ bridge. Uses a tagged-union approach with simple types.
/// Values are validated when they're parsed for a write or query, with the
/// same rules and messages as upstream's FSTUserDataReader.
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
    SentinelIncrement,     // operand in array_value_[0]
    SentinelMinimum,       // operand in array_value_[0]
    SentinelMaximum,       // operand in array_value_[0]

    /// A Swift value Firestore can't store; the string is its type name.
    Unsupported,

    // BSON types (MinKey, RegexValue, ...)
    MinKey,
    MaxKey,
    Regex,           // pattern, options in string2_value_
    Int32,           // in int64_value_
    Decimal128,      // the decimal as a string
    BsonObjectId,    // the object ID as a string
    BsonTimestamp,   // seconds in int64_value_, increment in int64_2_value_
    BsonBinaryData,  // bytes, subtype in int32_value_
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
  /// Builds the blob on the C++ side, so Swift needn't construct a
  /// std::string from raw bytes (whose constructors differ between
  /// libc++ and libstdc++).
  static BridgeFieldValue FromBlob(const uint8_t* bytes, size_t size) noexcept;
  static BridgeFieldValue FromTimestamp(int64_t seconds,
                                        int32_t nanoseconds) noexcept;
  static BridgeFieldValue FromGeoPoint(double latitude,
                                        double longitude) noexcept;
  static BridgeFieldValue FromArray(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue FromMap(
      const BridgeFieldValueMap& entries) noexcept;
  /// A reference to `document`, which may belong to another database (that is
  /// rejected when the value is written).
  static BridgeFieldValue FromReference(
      const DocumentReferenceBridge& document) noexcept;
  /// A reference read from a document, as its path in the same database.
  static BridgeFieldValue FromDocumentPath(
      const std::string& document_path) noexcept;
  static BridgeFieldValue FromVector(
      const DoubleVector& doubles) noexcept;
  static BridgeFieldValue Unsupported(const std::string& type_name) noexcept;

  // BSON factories
  static BridgeFieldValue MinKey() noexcept;
  static BridgeFieldValue MaxKey() noexcept;
  static BridgeFieldValue FromRegex(const std::string& pattern,
                                    const std::string& options) noexcept;
  static BridgeFieldValue FromInt32(int32_t value) noexcept;
  static BridgeFieldValue FromDecimal128(const std::string& value) noexcept;
  static BridgeFieldValue FromBsonObjectId(const std::string& value) noexcept;
  static BridgeFieldValue FromBsonTimestamp(uint32_t seconds,
                                            uint32_t increment) noexcept;
  /// A BSON binary with `subtype`; subtype 0 is stored as plain bytes, as
  /// upstream does.
  static BridgeFieldValue FromBsonBinaryData(const uint8_t* bytes,
                                             size_t size,
                                             uint8_t subtype) noexcept;

  /// Whether two Decimal128 strings are the same number, as upstream's
  /// `FIRDecimal128Value` compares them (+0 equals -0).
  static bool Decimal128Equal(const std::string& lhs,
                              const std::string& rhs) noexcept;
  static size_t Decimal128Hash(const std::string& value) noexcept;

  // Sentinel factories
  static BridgeFieldValue Delete() noexcept;
  static BridgeFieldValue ServerTimestamp() noexcept;
  static BridgeFieldValue ArrayUnion(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue ArrayRemove(
      const BridgeFieldValueVector& elements) noexcept;
  static BridgeFieldValue Increment(const BridgeFieldValue& operand) noexcept;
  static BridgeFieldValue Minimum(const BridgeFieldValue& operand) noexcept;
  static BridgeFieldValue Maximum(const BridgeFieldValue& operand) noexcept;

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
  /// The options of a Regex.
  std::string string2_value() const noexcept { return string2_value_; }
  int32_t int32_value() const noexcept { return int32_value_; }
  uint32_t bson_timestamp_seconds() const noexcept {
    return static_cast<uint32_t>(int64_value_);
  }
  uint32_t bson_timestamp_increment() const noexcept {
    return static_cast<uint32_t>(int64_2_value_);
  }
  uint8_t bson_subtype() const noexcept {
    return static_cast<uint8_t>(int32_value_);
  }

 private:
  friend class UserDataParser;

  Tag tag_ = Tag::Null;
  bool bool_value_ = false;
  int64_t int64_value_ = 0;
  int64_t int64_2_value_ = 0;
  int32_t int32_value_ = 0;
  double double_value_ = 0.0;
  double double2_value_ = 0.0;
  std::string string_value_;
  std::string string2_value_;
  // The database of a Reference.
  std::string project_id_;
  std::string database_id_;
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

  /// Returns the document data. Empty if the document doesn't exist.
  /// server_timestamp_behavior: 0 = none (null), 1 = estimate (local write
  /// time), 2 = previous.
  BridgeFieldValueMap data(int32_t server_timestamp_behavior) const noexcept;

  /// Reads the field at `field_path` into `value`. Returns false if the
  /// document or field doesn't exist.
  bool GetField(const FieldPathSegments& field_path,
                int32_t server_timestamp_behavior,
                BridgeFieldValue& value) const noexcept;

  bool IsEqual(const DocumentSnapshotBridge& other) const noexcept;
  size_t Hash() const noexcept;

 private:
  friend class DocumentReferenceBridge;
  friend class QuerySnapshotBridge;
  friend class QueryBridge;
  friend class DocumentChangeBridge;
  friend class TransactionBridge;
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
  friend class FirestoreBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// PersistentCacheIndexManagerBridge
// ---------------------------------------------------------------------------
/// Wraps api::PersistentCacheIndexManager: the indexes of a persistent cache.
class PersistentCacheIndexManagerBridge {
 public:
  PersistentCacheIndexManagerBridge() noexcept;
  ~PersistentCacheIndexManagerBridge() noexcept;

  PersistentCacheIndexManagerBridge(
      const PersistentCacheIndexManagerBridge&) noexcept;
  PersistentCacheIndexManagerBridge& operator=(
      const PersistentCacheIndexManagerBridge&) noexcept;
  PersistentCacheIndexManagerBridge(
      PersistentCacheIndexManagerBridge&&) noexcept;
  PersistentCacheIndexManagerBridge& operator=(
      PersistentCacheIndexManagerBridge&&) noexcept;

  void EnableIndexAutoCreation() const noexcept;
  void DisableIndexAutoCreation() const noexcept;
  void DeleteAllIndexes() const noexcept;

 private:
  friend class FirestoreBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// LoadBundleTaskBridge
// ---------------------------------------------------------------------------
/// Wraps api::LoadBundleTask: observers of a bundle being loaded.
class LoadBundleTaskBridge {
 public:
  LoadBundleTaskBridge() noexcept;
  ~LoadBundleTaskBridge() noexcept;

  LoadBundleTaskBridge(const LoadBundleTaskBridge&) noexcept;
  LoadBundleTaskBridge& operator=(const LoadBundleTaskBridge&) noexcept;
  LoadBundleTaskBridge(LoadBundleTaskBridge&&) noexcept;
  LoadBundleTaskBridge& operator=(LoadBundleTaskBridge&&) noexcept;

  /// Calls `callback` with each later progress update, until the observer is
  /// removed; `release_context` is called then. Returns a handle for
  /// `RemoveObserver`.
  int64_t Observe(void* context,
                  ContextReleaseCallback release_context,
                  LoadBundleProgressCallback callback) const noexcept;

  void RemoveObserver(int64_t handle) const noexcept;
  void RemoveAllObservers() const noexcept;

 private:
  friend class FirestoreBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// DocumentChangeBridge
// ---------------------------------------------------------------------------
/// Wraps a single document change within a query snapshot.
class DocumentChangeBridge {
 public:
  /// The type of document change.
  enum class Type : int32_t {
    Added = 0,
    Modified = 1,
    Removed = 2
  };

  DocumentChangeBridge() noexcept;
  ~DocumentChangeBridge() noexcept;

  DocumentChangeBridge(const DocumentChangeBridge&) noexcept;
  DocumentChangeBridge& operator=(const DocumentChangeBridge&) noexcept;
  DocumentChangeBridge(DocumentChangeBridge&&) noexcept;
  DocumentChangeBridge& operator=(DocumentChangeBridge&&) noexcept;

  Type type() const noexcept;
  DocumentSnapshotBridge document() const noexcept;
  int64_t old_index() const noexcept;
  int64_t new_index() const noexcept;

 private:
  friend class QuerySnapshotBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

using DocumentChangeBridgeVector = std::vector<DocumentChangeBridge>;

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

  /// Get document changes (optionally including metadata changes).
  DocumentChangeBridgeVector document_changes(
      bool include_metadata_changes) const noexcept;

 private:
  friend class QueryBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// DocumentReferenceBridge
// ---------------------------------------------------------------------------
/// Wraps api::DocumentReference. Exposes read and write operations to Swift.
///
/// Writes take an optional callback (null: fire-and-forget), called once the
/// backend acknowledges the write. Invalid data aborts, as upstream.
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

  /// True if both refer to the same document in the same Firestore instance.
  bool IsEqual(const DocumentReferenceBridge& other) const noexcept;

  /// Hash consistent with IsEqual.
  size_t Hash() const noexcept;

  /// The parent collection.
  CollectionReferenceBridge parent() const noexcept;

  /// A subcollection of this document, at a path relative to it.
  CollectionReferenceBridge Collection(
      const std::string& collection_path) const noexcept;

  /// Writes the document. `merge_fields` is only used with
  /// `SetOption::MergeFields`.
  void SetData(const BridgeFieldValueMap& data,
               SetOption option,
               const FieldPathVector& merge_fields,
               void* context,
               ErrorCallback callback) noexcept;

  /// Updates fields of an existing document.
  void UpdateData(const BridgeUpdateData& data,
                  void* context,
                  ErrorCallback callback) noexcept;

  /// Deletes this document.
  void DeleteDocument(void* context, ErrorCallback callback) const noexcept;

  /// Reads the document from the given source.
  void GetDocument(api::Source source,
                   void* context,
                   DocumentSnapshotCallback callback) const noexcept;

  /// Adds a snapshot listener. `listen_source`: 0 = default, 1 = cache.
  /// `release_context` is called once the listener is gone, after `Remove()`.
  ListenerRegistrationBridge AddSnapshotListener(
      bool include_metadata_changes,
      int32_t listen_source,
      void* context,
      ContextReleaseCallback release_context,
      DocumentSnapshotCallback callback) const noexcept;

 private:
  friend class FirestoreBridge;
  friend class CollectionReferenceBridge;
  friend class DocumentSnapshotBridge;
  friend class WriteBatchBridge;
  friend class TransactionBridge;
  friend class BridgeFieldValue;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// FilterBridge
// ---------------------------------------------------------------------------
/// A query filter as Swift built it. Values are parsed when the filter is
/// added to a query, which is where upstream validates them too.
class FilterBridge {
 public:
  FilterBridge() noexcept;
  ~FilterBridge() noexcept;

  FilterBridge(const FilterBridge&) noexcept;
  FilterBridge& operator=(const FilterBridge&) noexcept;
  FilterBridge(FilterBridge&&) noexcept;
  FilterBridge& operator=(FilterBridge&&) noexcept;

  static FilterBridge Field(const FieldPathSegments& field_path,
                            FilterOperator op,
                            const BridgeFieldValue& value) noexcept;
  static FilterBridge And(const std::vector<FilterBridge>& filters) noexcept;
  static FilterBridge Or(const std::vector<FilterBridge>& filters) noexcept;

 private:
  friend class QueryBridge;
  struct Impl;
  std::shared_ptr<const Impl> impl_;
};

using FilterBridgeVector = std::vector<FilterBridge>;

// ---------------------------------------------------------------------------
// QueryBridge
// ---------------------------------------------------------------------------
/// Wraps api::Query. Exposes query modifiers and read operations. Invalid
/// queries abort with upstream's messages.
class QueryBridge {
 public:
  QueryBridge() noexcept;
  ~QueryBridge() noexcept;

  QueryBridge(const QueryBridge&) noexcept;
  QueryBridge& operator=(const QueryBridge&) noexcept;
  QueryBridge(QueryBridge&&) noexcept;
  QueryBridge& operator=(QueryBridge&&) noexcept;

  bool IsEqual(const QueryBridge& other) const noexcept;
  size_t Hash() const noexcept;

  // Query modifiers — each returns a new QueryBridge.
  QueryBridge Where(const FilterBridge& filter) const noexcept;
  QueryBridge OrderBy(const FieldPathSegments& field_path,
                      bool descending) const noexcept;
  QueryBridge LimitToFirst(int32_t limit) const noexcept;
  QueryBridge LimitToLast(int32_t limit) const noexcept;

  /// Starts at (`inclusive`) or after the given values of the order-by fields.
  QueryBridge StartAt(const BridgeFieldValueVector& values,
                      bool inclusive) const noexcept;
  /// Ends at (`inclusive`) or before the given values of the order-by fields.
  QueryBridge EndAt(const BridgeFieldValueVector& values,
                    bool inclusive) const noexcept;
  QueryBridge StartAtDocument(const DocumentSnapshotBridge& snapshot,
                              bool inclusive) const noexcept;
  QueryBridge EndAtDocument(const DocumentSnapshotBridge& snapshot,
                            bool inclusive) const noexcept;

  /// Executes the query.
  void GetDocuments(api::Source source,
                    void* context,
                    QuerySnapshotCallback callback) const noexcept;

  /// Adds a snapshot listener. `listen_source`: 0 = default, 1 = cache.
  /// `release_context` is called once the listener is gone, after `Remove()`.
  ListenerRegistrationBridge AddSnapshotListener(
      bool include_metadata_changes,
      int32_t listen_source,
      void* context,
      ContextReleaseCallback release_context,
      QuerySnapshotCallback callback) const noexcept;

  /// Runs the aggregations on the server.
  void GetAggregate(const BridgeAggregateFields& fields,
                    void* context,
                    AggregateCallback callback) const noexcept;

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

  /// Writes the parent document to `parent` and returns true, or returns
  /// false for a root collection.
  bool GetParent(DocumentReferenceBridge& parent) const noexcept;

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
// WriteBatchBridge
// ---------------------------------------------------------------------------
/// Wraps api::WriteBatch. Allows batching multiple write operations.
class WriteBatchBridge {
 public:
  WriteBatchBridge() noexcept;
  ~WriteBatchBridge() noexcept;

  WriteBatchBridge(const WriteBatchBridge&) noexcept;
  WriteBatchBridge& operator=(const WriteBatchBridge&) noexcept;
  WriteBatchBridge(WriteBatchBridge&&) noexcept;
  WriteBatchBridge& operator=(WriteBatchBridge&&) noexcept;

  void SetData(const DocumentReferenceBridge& doc,
               const BridgeFieldValueMap& data,
               SetOption option,
               const FieldPathVector& merge_fields) noexcept;
  void UpdateData(const DocumentReferenceBridge& doc,
                  const BridgeUpdateData& data) noexcept;
  void DeleteData(const DocumentReferenceBridge& doc) noexcept;

  /// Commits all batched writes. `callback` may be null.
  void Commit(void* context, ErrorCallback callback) noexcept;

 private:
  friend class FirestoreBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// TransactionBridge
// ---------------------------------------------------------------------------
/// Wraps core::Transaction for use within a RunTransaction callback.
class TransactionBridge {
 public:
  TransactionBridge() noexcept;
  ~TransactionBridge() noexcept;

  /// Reads a document within this transaction (synchronous, blocking). On
  /// failure, sets `error_code` (non-zero) and `error_message`.
  DocumentSnapshotBridge GetDocument(const DocumentReferenceBridge& doc,
                                     int32_t& error_code,
                                     std::string& error_message) const noexcept;

  void SetData(const DocumentReferenceBridge& doc,
               const BridgeFieldValueMap& data,
               SetOption option,
               const FieldPathVector& merge_fields) noexcept;
  void UpdateData(const DocumentReferenceBridge& doc,
                  const BridgeUpdateData& data) noexcept;
  void DeleteData(const DocumentReferenceBridge& doc) noexcept;

 private:
  friend class FirestoreBridge;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

/// C-style callback for transaction update blocks.
/// The transaction_ptr is an opaque pointer to a TransactionBridge on the heap.
/// The update block should call methods on it, then call
/// completion(completion_context, code, message): code 0 to commit, anything
/// else to abort the transaction without retrying.
typedef void (*TransactionUpdateCallback)(
    void* context,
    void* transaction_ptr,
    ErrorCallback completion,
    void* completion_context);

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

  /// Creates a FirestoreBridge with a real api::Firestore instance and no-op
  /// metadata.
  /// @param project_id The Firebase project ID.
  /// @param database_id The database name (usually "(default)").
  /// @param persistence_key A key for local persistence (usually the app name).
  /// @param auth_context, request_auth_token Where Auth tokens come from. With
  ///     a null callback, Firestore is unauthenticated.
  /// @param initial_uid The signed-in user's UID; empty when signed out.
  /// @param app_check_context, request_app_check_token Where App Check tokens
  ///     come from. With a null callback, no App Check token is sent.
  /// @param release_context Called once for each non-null context when the
  ///     Firestore instance no longer needs it.
  static FirestoreBridge Create(
      const std::string& project_id,
      const std::string& database_id,
      const std::string& persistence_key,
      void* auth_context,
      TokenRequestCallback request_auth_token,
      const std::string& initial_uid,
      void* app_check_context,
      TokenRequestCallback request_app_check_token,
      ContextReleaseCallback release_context) noexcept;

  /// Tells Firestore that the signed-in user or their token changed. `uid` is
  /// empty when signed out.
  void SetAuthUser(const std::string& uid) const noexcept;

  /// Get a collection reference by path.
  CollectionReferenceBridge GetCollection(
      const std::string& collection_path) const noexcept;

  /// Get a document reference by path.
  DocumentReferenceBridge GetDocument(
      const std::string& document_path) const noexcept;

  /// Create a new write batch.
  WriteBatchBridge GetBatch() const noexcept;

  /// Runs a transaction. `result_callback` gets the outcome once.
  void RunTransaction(
      void* context,
      TransactionUpdateCallback update_callback,
      void* result_context,
      ErrorCallback result_callback,
      int32_t max_attempts) const noexcept;

  /// Get a collection group query.
  QueryBridge GetCollectionGroup(
      const std::string& collection_id) const noexcept;

  /// Calls `callback` (with code 0) whenever all active listeners are in sync.
  /// `release_context` is called once the listener is gone, after `Remove()`.
  ListenerRegistrationBridge AddSnapshotsInSyncListener(
      void* context,
      ContextReleaseCallback release_context,
      ErrorCallback callback) const noexcept;

  /// Loads a bundle from a stream that `read` reads; `release_stream` is
  /// called when the stream is no longer needed. If `completion` is given, it
  /// is the task's last observer, registered before the stream is first read,
  /// so it sees the final progress.
  LoadBundleTaskBridge LoadBundle(
      void* stream_context,
      BundleReadCallback read,
      ContextReleaseCallback release_stream,
      void* completion_context,
      ContextReleaseCallback release_completion,
      LoadBundleProgressCallback completion) const noexcept;

  /// Writes the index manager to `manager` and returns true, or returns false
  /// if the cache isn't persistent.
  bool GetPersistentCacheIndexManager(
      PersistentCacheIndexManagerBridge& manager) const noexcept;

  /// Logs debug messages (true) or only notices and above (false).
  static void EnableLogging(bool enabled) noexcept;

  /// Looks up a query that a loaded bundle named.
  void GetNamedQuery(const std::string& name,
                     void* context,
                     NamedQueryCallback callback) const noexcept;

  /// Terminates the Firestore instance.
  void Terminate(void* context, ErrorCallback callback) const noexcept;

  /// Clears all local persistent storage.
  void ClearPersistence(void* context, ErrorCallback callback) const noexcept;

  /// Waits for all pending writes to be acknowledged.
  void WaitForPendingWrites(void* context, ErrorCallback callback) const noexcept;

  /// Enables the network.
  void EnableNetwork(void* context, ErrorCallback callback) const noexcept;

  /// Disables the network.
  void DisableNetwork(void* context, ErrorCallback callback) const noexcept;

  // --- Settings ---

  /// Applies settings, as upstream's `Firestore.settings` setter does. Stops
  /// the process if the instance has already started. `cache_size_bytes` is
  /// used by `CacheKind::Persistent` and `CacheKind::MemoryLru`.
  void SetSettings(const std::string& host,
                   bool ssl_enabled,
                   CacheKind cache_kind,
                   int64_t cache_size_bytes) noexcept;

  /// The project ID.
  std::string project_id() const noexcept;

  /// The database ID string.
  std::string database_id() const noexcept;

 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

/// Completes a request from `TokenRequestCallback` for an Auth token. An empty
/// `token` with an empty `error` means no user is signed in; a non-empty
/// `error` fails the request.
void CompleteAuthTokenRequest(void* request,
                              const std::string& token,
                              const std::string& error) noexcept;

/// Completes a request from `TokenRequestCallback` for an App Check token.
/// Like upstream, App Check failures don't fail Firestore requests: a non-empty
/// `error` is logged and `token` (possibly empty) is still used.
void CompleteAppCheckTokenRequest(void* request,
                                  const std::string& token,
                                  const std::string& error) noexcept;

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_BRIDGE_H_
