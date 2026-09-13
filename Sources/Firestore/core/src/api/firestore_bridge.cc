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

#include "Firestore/include/FirestoreBridge.h"

#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "Firestore/core/src/api/collection_reference.h"
#include "Firestore/core/src/api/document_reference.h"
#include "Firestore/core/src/api/document_snapshot.h"
#include "Firestore/core/src/api/firestore.h"
#include "Firestore/core/src/api/listener_registration.h"
#include "Firestore/core/src/api/query_core.h"
#include "Firestore/core/src/api/query_snapshot.h"
#include "Firestore/core/src/api/source.h"
#include "Firestore/core/src/core/event_listener.h"
#include "Firestore/core/src/core/field_filter.h"
#include "Firestore/core/src/core/listen_options.h"
#include "Firestore/core/src/core/user_data.h"
#include "Firestore/core/src/model/database_id.h"
#include "Firestore/core/src/model/document.h"
#include "Firestore/core/src/model/document_key.h"
#include "Firestore/core/src/model/field_mask.h"
#include "Firestore/core/src/model/field_path.h"
#include "Firestore/core/src/model/field_transform.h"
#include "Firestore/core/src/model/object_value.h"
#include "Firestore/core/src/model/resource_path.h"
#include "Firestore/core/src/model/server_timestamp_util.h"
#include "Firestore/core/src/model/transform_operation.h"
#include "Firestore/core/src/model/value_util.h"
#include "Firestore/core/src/nanopb/nanopb_util.h"
#include "Firestore/core/src/util/status.h"
#include "Firestore/core/src/util/statusor.h"

#include "absl/types/optional.h"

namespace firebase {
namespace firestore {
namespace swift_bridge {

using api::CollectionReference;
using api::DocumentReference;
using api::DocumentSnapshot;
using api::Firestore;
using api::Query;
using api::QuerySnapshot;
using api::Source;
using core::EventListener;
using core::FieldFilter;
using core::ParseAccumulator;
using core::ParseContext;
using core::ParsedSetData;
using core::ParsedUpdateData;
using core::UserDataSource;
using model::ArrayTransform;
using model::DatabaseId;
using model::DocumentKey;
using model::FieldMask;
using model::FieldPath;
using model::FieldTransform;
using model::NumericIncrementTransform;
using model::ObjectValue;
using model::ResourcePath;
using model::ServerTimestampTransform;
using model::TransformOperation;
using nanopb::Message;
using util::Status;
using util::StatusOr;

// ===========================================================================
// DocumentSnapshotBridge::Impl
// ===========================================================================
struct DocumentSnapshotBridge::Impl {
  explicit Impl(DocumentSnapshot snapshot)
      : snapshot_(std::move(snapshot)) {}
  DocumentSnapshot snapshot_;
};

DocumentSnapshotBridge::DocumentSnapshotBridge() noexcept = default;
DocumentSnapshotBridge::~DocumentSnapshotBridge() noexcept = default;
DocumentSnapshotBridge::DocumentSnapshotBridge(
    const DocumentSnapshotBridge&) noexcept = default;
DocumentSnapshotBridge& DocumentSnapshotBridge::operator=(
    const DocumentSnapshotBridge&) noexcept = default;
DocumentSnapshotBridge::DocumentSnapshotBridge(
    DocumentSnapshotBridge&&) noexcept = default;
DocumentSnapshotBridge& DocumentSnapshotBridge::operator=(
    DocumentSnapshotBridge&&) noexcept = default;

bool DocumentSnapshotBridge::exists() const noexcept {
  if (!impl_) return false;
  return impl_->snapshot_.exists();
}

std::string DocumentSnapshotBridge::document_id() const noexcept {
  if (!impl_) return "";
  return impl_->snapshot_.document_id();
}

api::SnapshotMetadata DocumentSnapshotBridge::metadata() const noexcept {
  if (!impl_) return api::SnapshotMetadata{};
  return impl_->snapshot_.metadata();
}

DocumentReferenceBridge DocumentSnapshotBridge::create_reference()
    const noexcept {
  if (!impl_) return DocumentReferenceBridge{};
  DocumentReferenceBridge result;
  result.impl_ = std::make_shared<DocumentReferenceBridge::Impl>(
      impl_->snapshot_.CreateReference());
  return result;
}

// ===========================================================================
// ListenerRegistrationBridge::Impl
// ===========================================================================
struct ListenerRegistrationBridge::Impl {
  explicit Impl(std::unique_ptr<api::ListenerRegistration> registration)
      : registration_(std::move(registration)) {}
  std::unique_ptr<api::ListenerRegistration> registration_;
};

ListenerRegistrationBridge::ListenerRegistrationBridge() noexcept = default;
ListenerRegistrationBridge::~ListenerRegistrationBridge() noexcept = default;
ListenerRegistrationBridge::ListenerRegistrationBridge(
    const ListenerRegistrationBridge&) noexcept = default;
ListenerRegistrationBridge& ListenerRegistrationBridge::operator=(
    const ListenerRegistrationBridge&) noexcept = default;
ListenerRegistrationBridge::ListenerRegistrationBridge(
    ListenerRegistrationBridge&&) noexcept = default;
ListenerRegistrationBridge& ListenerRegistrationBridge::operator=(
    ListenerRegistrationBridge&&) noexcept = default;

void ListenerRegistrationBridge::Remove() noexcept {
  if (impl_ && impl_->registration_) {
    impl_->registration_->Remove();
    impl_->registration_.reset();
  }
}

// ===========================================================================
// QuerySnapshotBridge::Impl
// ===========================================================================
struct QuerySnapshotBridge::Impl {
  explicit Impl(QuerySnapshot snapshot)
      : snapshot_(std::move(snapshot)) {}
  QuerySnapshot snapshot_;
};

QuerySnapshotBridge::QuerySnapshotBridge() noexcept = default;
QuerySnapshotBridge::~QuerySnapshotBridge() noexcept = default;
QuerySnapshotBridge::QuerySnapshotBridge(
    const QuerySnapshotBridge&) noexcept = default;
QuerySnapshotBridge& QuerySnapshotBridge::operator=(
    const QuerySnapshotBridge&) noexcept = default;
QuerySnapshotBridge::QuerySnapshotBridge(
    QuerySnapshotBridge&&) noexcept = default;
QuerySnapshotBridge& QuerySnapshotBridge::operator=(
    QuerySnapshotBridge&&) noexcept = default;

bool QuerySnapshotBridge::empty() const noexcept {
  if (!impl_) return true;
  return impl_->snapshot_.empty();
}

int64_t QuerySnapshotBridge::size() const noexcept {
  if (!impl_) return 0;
  return static_cast<int64_t>(impl_->snapshot_.size());
}

api::SnapshotMetadata QuerySnapshotBridge::metadata() const noexcept {
  if (!impl_) return api::SnapshotMetadata{};
  return impl_->snapshot_.metadata();
}

DocumentSnapshotBridgeVector QuerySnapshotBridge::documents() const noexcept {
  DocumentSnapshotBridgeVector result;
  if (!impl_) return result;
  impl_->snapshot_.ForEachDocument([&](DocumentSnapshot doc) {
    DocumentSnapshotBridge bridge;
    bridge.impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
        std::move(doc));
    result.push_back(std::move(bridge));
  });
  return result;
}

// ===========================================================================
// DocumentReferenceBridge::Impl
// ===========================================================================
struct DocumentReferenceBridge::Impl {
  explicit Impl(DocumentReference ref) : ref_(std::move(ref)) {}
  DocumentReference ref_;
};

DocumentReferenceBridge::DocumentReferenceBridge() noexcept = default;
DocumentReferenceBridge::~DocumentReferenceBridge() noexcept = default;
DocumentReferenceBridge::DocumentReferenceBridge(
    const DocumentReferenceBridge&) noexcept = default;
DocumentReferenceBridge& DocumentReferenceBridge::operator=(
    const DocumentReferenceBridge&) noexcept = default;
DocumentReferenceBridge::DocumentReferenceBridge(
    DocumentReferenceBridge&&) noexcept = default;
DocumentReferenceBridge& DocumentReferenceBridge::operator=(
    DocumentReferenceBridge&&) noexcept = default;

std::string DocumentReferenceBridge::document_id() const noexcept {
  if (!impl_) return "";
  return impl_->ref_.document_id();
}

std::string DocumentReferenceBridge::path() const noexcept {
  if (!impl_) return "";
  return impl_->ref_.Path();
}

CollectionReferenceBridge DocumentReferenceBridge::parent() const noexcept {
  if (!impl_) return CollectionReferenceBridge{};
  CollectionReferenceBridge result;
  auto parent_ref = impl_->ref_.Parent();
  result.impl_ = std::make_shared<QueryBridge::Impl>(
      Query{parent_ref.query(), parent_ref.firestore()});
  return result;
}

void DocumentReferenceBridge::GetDocument(
    Source source,
    std::function<void(DocumentSnapshotBridge, std::string)> callback
) const noexcept {
  if (!impl_) {
    callback(DocumentSnapshotBridge{}, "DocumentReference is not initialized");
    return;
  }

  auto listener = EventListener<DocumentSnapshot>::Create(
      [callback = std::move(callback)](StatusOr<DocumentSnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          DocumentSnapshotBridge bridge;
          bridge.impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(std::move(bridge), "");
        } else {
          callback(DocumentSnapshotBridge{},
                   maybe_snapshot.status().error_message());
        }
      });

  impl_->ref_.GetDocument(source, std::move(listener));
}

void DocumentReferenceBridge::DeleteDocument(
    std::function<void(std::string)> callback) const noexcept {
  if (!impl_) {
    callback("DocumentReference is not initialized");
    return;
  }

  impl_->ref_.DeleteDocument([callback = std::move(callback)](Status status) {
    if (status.ok()) {
      callback("");
    } else {
      callback(status.error_message());
    }
  });
}

// ===========================================================================
// DocumentReferenceBridge — C-callback async methods
// ===========================================================================

void DocumentReferenceBridge::GetDocumentC(
    Source source,
    void* context,
    DocumentSnapshotCallback callback) const noexcept {
  if (!impl_) {
    callback(context, nullptr, "DocumentReference is not initialized");
    return;
  }

  auto listener = EventListener<DocumentSnapshot>::Create(
      [context, callback](StatusOr<DocumentSnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          auto* bridge = new DocumentSnapshotBridge();
          bridge->impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(context, static_cast<void*>(bridge), "");
        } else {
          callback(context, nullptr,
                   maybe_snapshot.status().error_message().c_str());
        }
      });

  impl_->ref_.GetDocument(source, std::move(listener));
}

ListenerRegistrationBridge DocumentReferenceBridge::AddSnapshotListener(
    bool include_metadata_changes,
    void* context,
    DocumentSnapshotCallback callback) const noexcept {
  ListenerRegistrationBridge result;
  if (!impl_) return result;

  auto options = core::ListenOptions::FromIncludeMetadataChanges(
      include_metadata_changes);

  auto listener = EventListener<DocumentSnapshot>::Create(
      [context, callback](StatusOr<DocumentSnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          auto* bridge = new DocumentSnapshotBridge();
          bridge->impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(context, static_cast<void*>(bridge), "");
        } else {
          std::string msg = maybe_snapshot.status().error_message();
          callback(context, nullptr, msg.c_str());
        }
      });

  auto registration = impl_->ref_.AddSnapshotListener(
      options, std::move(listener));
  result.impl_ = std::make_shared<ListenerRegistrationBridge::Impl>(
      std::move(registration));
  return result;
}

void DocumentReferenceBridge::DeleteDocumentC(
    void* context,
    ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "DocumentReference is not initialized");
    return;
  }

  impl_->ref_.DeleteDocument([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

// NOTE: SetDataC, SetDataMergeC, UpdateDataC are defined further below,
// after the ConvertMap/ConvertValue anonymous namespace.

// ===========================================================================
// QueryBridge::Impl
// ===========================================================================
struct QueryBridge::Impl {
  explicit Impl(Query query) : query_(std::move(query)) {}
  Query query_;
};

QueryBridge::QueryBridge() noexcept = default;
QueryBridge::~QueryBridge() noexcept = default;
QueryBridge::QueryBridge(const QueryBridge&) noexcept = default;
QueryBridge& QueryBridge::operator=(const QueryBridge&) noexcept = default;
QueryBridge::QueryBridge(QueryBridge&&) noexcept = default;
QueryBridge& QueryBridge::operator=(QueryBridge&&) noexcept = default;

void QueryBridge::GetDocuments(
    Source source,
    std::function<void(QuerySnapshotBridge, std::string)> callback
) const noexcept {
  if (!impl_) {
    callback(QuerySnapshotBridge{}, "Query is not initialized");
    return;
  }

  auto listener = EventListener<QuerySnapshot>::Create(
      [callback = std::move(callback)](StatusOr<QuerySnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          QuerySnapshotBridge bridge;
          bridge.impl_ = std::make_shared<QuerySnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(std::move(bridge), "");
        } else {
          callback(QuerySnapshotBridge{},
                   maybe_snapshot.status().error_message());
        }
      });

  // Use a const_cast because GetDocuments on the C++ side is non-const
  // but logically it doesn't modify the query.
  const_cast<Query&>(impl_->query_).GetDocuments(source, std::move(listener));
}

QueryBridge QueryBridge::OrderBy(const std::string& field,
                                 bool descending) const noexcept {
  if (!impl_) return QueryBridge{};
  auto field_path = model::FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.OrderBy(std::move(field_path).ValueOrDie(), descending));
  return result;
}

QueryBridge QueryBridge::LimitToFirst(int32_t limit) const noexcept {
  if (!impl_) return QueryBridge{};
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.LimitToFirst(limit));
  return result;
}

QueryBridge QueryBridge::LimitToLast(int32_t limit) const noexcept {
  if (!impl_) return QueryBridge{};
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.LimitToLast(limit));
  return result;
}

// ===========================================================================
// QueryBridge — C-callback async methods
// ===========================================================================

void QueryBridge::GetDocumentsC(
    Source source,
    void* context,
    QuerySnapshotCallback callback) const noexcept {
  if (!impl_) {
    callback(context, nullptr, "Query is not initialized");
    return;
  }

  auto listener = EventListener<QuerySnapshot>::Create(
      [context, callback](StatusOr<QuerySnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          auto* bridge = new QuerySnapshotBridge();
          bridge->impl_ = std::make_shared<QuerySnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(context, static_cast<void*>(bridge), "");
        } else {
          std::string msg = maybe_snapshot.status().error_message();
          callback(context, nullptr, msg.c_str());
        }
      });

  const_cast<Query&>(impl_->query_).GetDocuments(source, std::move(listener));
}

ListenerRegistrationBridge QueryBridge::AddSnapshotListener(
    bool include_metadata_changes,
    void* context,
    QuerySnapshotCallback callback) const noexcept {
  ListenerRegistrationBridge result;
  if (!impl_) return result;

  auto options = core::ListenOptions::FromIncludeMetadataChanges(
      include_metadata_changes);

  auto listener = EventListener<QuerySnapshot>::Create(
      [context, callback](StatusOr<QuerySnapshot> maybe_snapshot) {
        if (maybe_snapshot.ok()) {
          auto* bridge = new QuerySnapshotBridge();
          bridge->impl_ = std::make_shared<QuerySnapshotBridge::Impl>(
              std::move(maybe_snapshot).ValueOrDie());
          callback(context, static_cast<void*>(bridge), "");
        } else {
          std::string msg = maybe_snapshot.status().error_message();
          callback(context, nullptr, msg.c_str());
        }
      });

  auto registration = const_cast<Query&>(impl_->query_).AddSnapshotListener(
      options, std::move(listener));
  result.impl_ = std::make_shared<ListenerRegistrationBridge::Impl>(
      std::move(registration));
  return result;
}

// NOTE: QueryBridge Where filter operations are defined further below,
// after the ConvertMap/ConvertValue anonymous namespace.

// ===========================================================================
// CollectionReferenceBridge
// ===========================================================================
CollectionReferenceBridge::CollectionReferenceBridge() noexcept = default;
CollectionReferenceBridge::~CollectionReferenceBridge() noexcept = default;
CollectionReferenceBridge::CollectionReferenceBridge(
    const CollectionReferenceBridge&) noexcept = default;
CollectionReferenceBridge& CollectionReferenceBridge::operator=(
    const CollectionReferenceBridge&) noexcept = default;
CollectionReferenceBridge::CollectionReferenceBridge(
    CollectionReferenceBridge&&) noexcept = default;
CollectionReferenceBridge& CollectionReferenceBridge::operator=(
    CollectionReferenceBridge&&) noexcept = default;

std::string CollectionReferenceBridge::collection_id() const noexcept {
  if (!impl_) return "";
  // The CollectionReference is stored as a Query in impl_.
  // We can access the collection_id via the query's path.
  return impl_->query_.query().path().last_segment();
}

std::string CollectionReferenceBridge::path() const noexcept {
  if (!impl_) return "";
  return impl_->query_.query().path().CanonicalString();
}

DocumentReferenceBridge CollectionReferenceBridge::Document() const noexcept {
  if (!impl_) return DocumentReferenceBridge{};
  // Construct a CollectionReference from our query data, then call Document().
  auto collection = CollectionReference{
      impl_->query_.query().path(),
      impl_->query_.firestore()};
  DocumentReferenceBridge result;
  result.impl_ = std::make_shared<DocumentReferenceBridge::Impl>(
      collection.Document());
  return result;
}

DocumentReferenceBridge CollectionReferenceBridge::Document(
    const std::string& document_path) const noexcept {
  if (!impl_) return DocumentReferenceBridge{};
  auto collection = CollectionReference{
      impl_->query_.query().path(),
      impl_->query_.firestore()};
  DocumentReferenceBridge result;
  result.impl_ = std::make_shared<DocumentReferenceBridge::Impl>(
      collection.Document(document_path));
  return result;
}

// ===========================================================================
// FirestoreBridge::Impl
// ===========================================================================
struct FirestoreBridge::Impl {
  explicit Impl(std::shared_ptr<Firestore> firestore)
      : firestore_(std::move(firestore)) {}
  std::shared_ptr<Firestore> firestore_;
};

FirestoreBridge::FirestoreBridge() noexcept = default;
FirestoreBridge::~FirestoreBridge() noexcept = default;
FirestoreBridge::FirestoreBridge(const FirestoreBridge&) noexcept = default;
FirestoreBridge& FirestoreBridge::operator=(
    const FirestoreBridge&) noexcept = default;
FirestoreBridge::FirestoreBridge(FirestoreBridge&&) noexcept = default;
FirestoreBridge& FirestoreBridge::operator=(FirestoreBridge&&) noexcept =
    default;

CollectionReferenceBridge FirestoreBridge::GetCollection(
    const std::string& collection_path) const noexcept {
  if (!impl_) return CollectionReferenceBridge{};
  auto collection = impl_->firestore_->GetCollection(collection_path);
  CollectionReferenceBridge result;
  result.impl_ = std::make_shared<QueryBridge::Impl>(
      Query{collection.query(), collection.firestore()});
  return result;
}

DocumentReferenceBridge FirestoreBridge::GetDocument(
    const std::string& document_path) const noexcept {
  if (!impl_) return DocumentReferenceBridge{};
  DocumentReferenceBridge result;
  result.impl_ = std::make_shared<DocumentReferenceBridge::Impl>(
      impl_->firestore_->GetDocument(document_path));
  return result;
}

std::string FirestoreBridge::database_id() const noexcept {
  if (!impl_) return "";
  return impl_->firestore_->database_id().database_id();
}

// ===========================================================================
// BridgeFieldValue
// ===========================================================================

BridgeFieldValue::BridgeFieldValue() noexcept = default;
BridgeFieldValue::~BridgeFieldValue() noexcept = default;
BridgeFieldValue::BridgeFieldValue(const BridgeFieldValue&) = default;
BridgeFieldValue& BridgeFieldValue::operator=(const BridgeFieldValue&) = default;
BridgeFieldValue::BridgeFieldValue(BridgeFieldValue&&) noexcept = default;
BridgeFieldValue& BridgeFieldValue::operator=(BridgeFieldValue&&) noexcept = default;

BridgeFieldValue BridgeFieldValue::Null() noexcept {
  return BridgeFieldValue{};
}

BridgeFieldValue BridgeFieldValue::FromBool(bool value) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Boolean;
  v.bool_value_ = value;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromInt64(int64_t value) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Integer;
  v.int64_value_ = value;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromDouble(double value) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Double;
  v.double_value_ = value;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromString(
    const std::string& value) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::String;
  v.string_value_ = value;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromBlob(
    const std::string& bytes) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Blob;
  v.string_value_ = bytes;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromTimestamp(
    int64_t seconds, int32_t nanoseconds) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Timestamp;
  v.int64_value_ = seconds;
  v.int32_value_ = nanoseconds;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromGeoPoint(
    double latitude, double longitude) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::GeoPoint;
  v.double_value_ = latitude;
  v.double2_value_ = longitude;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromArray(
    const BridgeFieldValueVector& elements) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Array;
  v.array_value_ = elements;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromMap(
    const BridgeFieldValueMap& entries) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Map;
  v.map_value_ = entries;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromReference(
    const std::string& document_path) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Reference;
  v.string_value_ = document_path;
  return v;
}

BridgeFieldValue BridgeFieldValue::FromVector(
    const DoubleVector& doubles) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Vector;
  v.vector_value_ = doubles;
  return v;
}

BridgeFieldValue BridgeFieldValue::Delete() noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelDelete;
  return v;
}

BridgeFieldValue BridgeFieldValue::ServerTimestamp() noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelServerTimestamp;
  return v;
}

BridgeFieldValue BridgeFieldValue::ArrayUnion(
    const BridgeFieldValueVector& elements) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelArrayUnion;
  v.array_value_ = elements;
  return v;
}

BridgeFieldValue BridgeFieldValue::ArrayRemove(
    const BridgeFieldValueVector& elements) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelArrayRemove;
  v.array_value_ = elements;
  return v;
}

BridgeFieldValue BridgeFieldValue::IncrementInt(int64_t operand) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelIncrement;
  v.bool_value_ = false;  // false = integer increment
  v.int64_value_ = operand;
  return v;
}

BridgeFieldValue BridgeFieldValue::IncrementDouble(double operand) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelIncrement;
  v.bool_value_ = true;  // true = double increment
  v.double_value_ = operand;
  return v;
}

// ===========================================================================
// Internal: UserDataConverter
// ===========================================================================
// Converts BridgeFieldValue trees into nanopb protobuf values, handling
// sentinel field values (transforms) via ParseAccumulator/ParseContext.

namespace {

// Forward declaration
absl::optional<Message<google_firestore_v1_Value>> ConvertValue(
    const BridgeFieldValue& value,
    ParseContext&& context,
    const DatabaseId& database_id);

Message<google_firestore_v1_Value> ConvertMap(
    const BridgeFieldValueMap& entries,
    ParseContext&& context,
    const DatabaseId& database_id) {
  Message<google_firestore_v1_Value> result;
  result->which_value_type = google_firestore_v1_Value_map_value_tag;
  result->map_value = {};

  if (entries.empty()) {
    const FieldPath* path = context.path();
    if (path && !path->empty()) {
      context.AddToFieldMask(*path);
    }
    return result;
  }

  // Count non-sentinel entries for sizing the fields array.
  pb_size_t non_sentinel_count = 0;
  for (const auto& entry : entries) {
    auto tag = entry.second.tag();
    if (tag != BridgeFieldValue::Tag::SentinelDelete &&
        tag != BridgeFieldValue::Tag::SentinelServerTimestamp &&
        tag != BridgeFieldValue::Tag::SentinelArrayUnion &&
        tag != BridgeFieldValue::Tag::SentinelArrayRemove &&
        tag != BridgeFieldValue::Tag::SentinelIncrement) {
      ++non_sentinel_count;
    }
  }

  result->map_value.fields_count = non_sentinel_count;
  result->map_value.fields =
      nanopb::MakeArray<google_firestore_v1_MapValue_FieldsEntry>(
          non_sentinel_count);

  pb_size_t index = 0;
  for (const auto& entry : entries) {
    auto parsed = ConvertValue(entry.second,
                                context.ChildContext(entry.first),
                                database_id);
    if (parsed) {
      result->map_value.fields[index].key =
          nanopb::MakeBytesArray(entry.first);
      result->map_value.fields[index].value = *parsed->release();
      ++index;
    }
  }

  return result;
}

Message<google_firestore_v1_Value> ConvertArray(
    const BridgeFieldValueVector& elements,
    ParseContext&& context,
    const DatabaseId& database_id) {
  Message<google_firestore_v1_Value> result;
  result->which_value_type = google_firestore_v1_Value_array_value_tag;
  result->array_value.values_count =
      static_cast<pb_size_t>(elements.size());
  result->array_value.values =
      nanopb::MakeArray<google_firestore_v1_Value>(
          result->array_value.values_count);

  for (size_t i = 0; i < elements.size(); ++i) {
    auto parsed = ConvertValue(elements[i],
                                context.ChildContext(i),
                                database_id);
    if (!parsed) {
      // Replace sentinels in arrays with null
      parsed.emplace(model::DeepClone(model::NullValue()));
    }
    result->array_value.values[i] = *parsed->release();
  }

  return result;
}

Message<google_firestore_v1_Value> ConvertVector(
    const DoubleVector& doubles) {
  Message<google_firestore_v1_Value> result;
  result->which_value_type = google_firestore_v1_Value_map_value_tag;
  result->map_value = {};

  result->map_value.fields_count = 2;
  result->map_value.fields =
      nanopb::MakeArray<google_firestore_v1_MapValue_FieldsEntry>(2);

  // __type__ = "__vector__"
  result->map_value.fields[0].key =
      nanopb::CopyBytesArray(model::kTypeValueFieldKey);
  auto type_val = model::StringValue(std::string("__vector__"));
  result->map_value.fields[0].value = *type_val.release();

  // value = [doubles...]
  Message<google_firestore_v1_Value> array_msg;
  array_msg->which_value_type = google_firestore_v1_Value_array_value_tag;
  array_msg->array_value.values_count =
      static_cast<pb_size_t>(doubles.size());
  array_msg->array_value.values =
      nanopb::MakeArray<google_firestore_v1_Value>(
          array_msg->array_value.values_count);

  for (size_t i = 0; i < doubles.size(); ++i) {
    Message<google_firestore_v1_Value> dval;
    dval->which_value_type = google_firestore_v1_Value_double_value_tag;
    dval->double_value = doubles[i];
    array_msg->array_value.values[i] = *dval.release();
  }

  result->map_value.fields[1].key =
      nanopb::CopyBytesArray(model::kVectorValueFieldKey);
  result->map_value.fields[1].value = *array_msg.release();

  return result;
}

void HandleSentinel(
    const BridgeFieldValue& value,
    ParseContext&& context,
    const DatabaseId& database_id) {
  auto tag = value.tag();

  if (tag == BridgeFieldValue::Tag::SentinelDelete) {
    if (context.data_source() == UserDataSource::MergeSet) {
      context.AddToFieldMask(*context.path());
    }
    // For Update, delete at top level is handled by the caller
    // by not including the field in the ObjectValue.

  } else if (tag == BridgeFieldValue::Tag::SentinelServerTimestamp) {
    context.AddToFieldTransforms(
        *context.path(), ServerTimestampTransform());

  } else if (tag == BridgeFieldValue::Tag::SentinelArrayUnion) {
    // Convert elements to ArrayValue for the transform
    ParseAccumulator elem_accumulator{UserDataSource::Argument};
    Message<google_firestore_v1_ArrayValue> array_value;
    auto elements = value.array_value();
    array_value->values_count = static_cast<pb_size_t>(elements.size());
    array_value->values = nanopb::MakeArray<google_firestore_v1_Value>(
        array_value->values_count);
    for (size_t i = 0; i < elements.size(); ++i) {
      ParseContext elem_ctx = elem_accumulator.RootContext();
      auto parsed = ConvertValue(
          elements[i],
          elem_ctx.ChildContext(i),
          database_id);
      if (parsed) {
        array_value->values[i] = *parsed->release();
      } else {
        array_value->values[i] = model::NullValue();
      }
    }
    ArrayTransform transform(TransformOperation::Type::ArrayUnion,
                             std::move(array_value));
    context.AddToFieldTransforms(*context.path(), std::move(transform));

  } else if (tag == BridgeFieldValue::Tag::SentinelArrayRemove) {
    ParseAccumulator elem_accumulator{UserDataSource::Argument};
    Message<google_firestore_v1_ArrayValue> array_value;
    auto elements = value.array_value();
    array_value->values_count = static_cast<pb_size_t>(elements.size());
    array_value->values = nanopb::MakeArray<google_firestore_v1_Value>(
        array_value->values_count);
    for (size_t i = 0; i < elements.size(); ++i) {
      ParseContext elem_ctx = elem_accumulator.RootContext();
      auto parsed = ConvertValue(
          elements[i],
          elem_ctx.ChildContext(i),
          database_id);
      if (parsed) {
        array_value->values[i] = *parsed->release();
      } else {
        array_value->values[i] = model::NullValue();
      }
    }
    ArrayTransform transform(TransformOperation::Type::ArrayRemove,
                             std::move(array_value));
    context.AddToFieldTransforms(*context.path(), std::move(transform));

  } else if (tag == BridgeFieldValue::Tag::SentinelIncrement) {
    Message<google_firestore_v1_Value> operand;
    if (value.bool_value()) {
      // Double increment
      operand->which_value_type = google_firestore_v1_Value_double_value_tag;
      operand->double_value = value.double_value();
    } else {
      // Integer increment
      operand->which_value_type = google_firestore_v1_Value_integer_value_tag;
      operand->integer_value = value.int64_value();
    }
    NumericIncrementTransform transform(std::move(operand));
    context.AddToFieldTransforms(*context.path(), std::move(transform));
  }
}

absl::optional<Message<google_firestore_v1_Value>> ConvertValue(
    const BridgeFieldValue& value,
    ParseContext&& context,
    const DatabaseId& database_id) {
  using Tag = BridgeFieldValue::Tag;

  switch (value.tag()) {
    case Tag::SentinelDelete:
    case Tag::SentinelServerTimestamp:
    case Tag::SentinelArrayUnion:
    case Tag::SentinelArrayRemove:
    case Tag::SentinelIncrement:
      HandleSentinel(value, std::move(context), database_id);
      return absl::nullopt;

    case Tag::Map:
      return ConvertMap(value.map_value(), std::move(context), database_id);

    case Tag::Array:
      if (context.path()) {
        context.AddToFieldMask(*context.path());
      }
      return ConvertArray(value.array_value(), std::move(context),
                          database_id);

    default:
      break;
  }

  // Scalar values — add to field mask
  if (context.path()) {
    context.AddToFieldMask(*context.path());
  }

  switch (value.tag()) {
    case Tag::Null:
      return model::DeepClone(model::NullValue());

    case Tag::Boolean: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type = google_firestore_v1_Value_boolean_value_tag;
      result->boolean_value = value.bool_value();
      return result;
    }

    case Tag::Integer: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type = google_firestore_v1_Value_integer_value_tag;
      result->integer_value = value.int64_value();
      return result;
    }

    case Tag::Double: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type = google_firestore_v1_Value_double_value_tag;
      result->double_value = value.double_value();
      return result;
    }

    case Tag::String:
      return model::StringValue(value.string_value());

    case Tag::Blob: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type = google_firestore_v1_Value_bytes_value_tag;
      result->bytes_value = nanopb::MakeBytesArray(
          value.string_value().data(), value.string_value().size());
      return result;
    }

    case Tag::Timestamp: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type =
          google_firestore_v1_Value_timestamp_value_tag;
      result->timestamp_value.seconds = value.timestamp_seconds();
      result->timestamp_value.nanos = value.timestamp_nanos();
      return result;
    }

    case Tag::GeoPoint: {
      Message<google_firestore_v1_Value> result;
      result->which_value_type =
          google_firestore_v1_Value_geo_point_value_tag;
      result->geo_point_value.latitude = value.geo_latitude();
      result->geo_point_value.longitude = value.geo_longitude();
      return result;
    }

    case Tag::Reference: {
      // Build the full reference name from the document path.
      // Format: projects/{project}/databases/{db}/documents/{path}
      std::string ref_name =
          ResourcePath({"projects", database_id.project_id(),
                        "databases", database_id.database_id(),
                        "documents", value.string_value()})
              .CanonicalString();
      Message<google_firestore_v1_Value> result;
      result->which_value_type =
          google_firestore_v1_Value_reference_value_tag;
      result->reference_value = nanopb::MakeBytesArray(ref_name);
      return result;
    }

    case Tag::Vector:
      return ConvertVector(value.vector_value());

    default:
      // Already handled above (Map, Array, sentinels)
      return absl::nullopt;
  }
}

}  // anonymous namespace

// ===========================================================================
// DocumentReferenceBridge — Write Operations
// ===========================================================================

std::string DocumentReferenceBridge::SetData(
    const BridgeFieldValueMap& data,
    std::function<void(std::string)> callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Set};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).SetData(std::move(obj));

  impl_->ref_.SetData(std::move(parsed),
      [callback = std::move(callback)](Status status) {
        callback(status.ok() ? "" : status.error_message());
      });
  return "";
}

std::string DocumentReferenceBridge::SetDataMerge(
    const BridgeFieldValueMap& data,
    std::function<void(std::string)> callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::MergeSet};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).MergeData(std::move(obj));

  impl_->ref_.SetData(std::move(parsed),
      [callback = std::move(callback)](Status status) {
        callback(status.ok() ? "" : status.error_message());
      });
  return "";
}

std::string DocumentReferenceBridge::SetDataMergeFields(
    const BridgeFieldValueMap& data,
    const StringVector& merge_fields,
    std::function<void(std::string)> callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::MergeSet};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};

  std::set<FieldPath> validated_paths;
  for (const auto& field : merge_fields) {
    auto path = FieldPath::FromDotSeparatedString(field);
    if (!accumulator.Contains(path)) {
      return "Field '" + path.CanonicalString() +
             "' is specified in your field mask but missing from your input "
             "data.";
    }
    validated_paths.insert(std::move(path));
  }

  auto parsed = std::move(accumulator)
      .MergeData(std::move(obj), FieldMask{std::move(validated_paths)});

  impl_->ref_.SetData(std::move(parsed),
      [callback = std::move(callback)](Status status) {
        callback(status.ok() ? "" : status.error_message());
      });
  return "";
}

std::string DocumentReferenceBridge::UpdateData(
    const BridgeFieldValueMap& data,
    std::function<void(std::string)> callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Update};
  ParseContext context = accumulator.RootContext();
  ObjectValue update_data;

  for (const auto& entry : data) {
    auto path = FieldPath::FromDotSeparatedString(entry.first);

    if (entry.second.tag() == BridgeFieldValue::Tag::SentinelDelete) {
      // Add to field mask but don't add to updateData.
      context.AddToFieldMask(std::move(path));
    } else {
      auto parsed = ConvertValue(entry.second,
                                  context.ChildContext(path),
                                  db_id);
      if (parsed) {
        context.AddToFieldMask(path);
        update_data.Set(path, std::move(*parsed));
      }
    }
  }

  auto parsed = std::move(accumulator).UpdateData(std::move(update_data));

  impl_->ref_.UpdateData(std::move(parsed),
      [callback = std::move(callback)](Status status) {
        callback(status.ok() ? "" : status.error_message());
      });
  return "";
}

// --- Fire-and-forget write overloads (no callback) ---

std::string DocumentReferenceBridge::SetData(
    const BridgeFieldValueMap& data) noexcept {
  return SetData(data, [](std::string) {});
}

std::string DocumentReferenceBridge::SetDataMerge(
    const BridgeFieldValueMap& data) noexcept {
  return SetDataMerge(data, [](std::string) {});
}

std::string DocumentReferenceBridge::SetDataMergeFields(
    const BridgeFieldValueMap& data,
    const StringVector& merge_fields) noexcept {
  return SetDataMergeFields(data, merge_fields, [](std::string) {});
}

std::string DocumentReferenceBridge::UpdateData(
    const BridgeFieldValueMap& data) noexcept {
  return UpdateData(data, [](std::string) {});
}

void DocumentReferenceBridge::DeleteDocumentNoCallback() const noexcept {
  DeleteDocument([](std::string) {});
}

// --- C-callback write overloads ---

std::string DocumentReferenceBridge::SetDataC(
    const BridgeFieldValueMap& data,
    void* context,
    ErrorCallback callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Set};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).SetData(std::move(obj));

  impl_->ref_.SetData(std::move(parsed),
      [context, callback](Status status) {
        if (status.ok()) {
          callback(context, "");
        } else {
          std::string msg = status.error_message();
          callback(context, msg.c_str());
        }
      });
  return "";
}

std::string DocumentReferenceBridge::SetDataMergeC(
    const BridgeFieldValueMap& data,
    void* context,
    ErrorCallback callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::MergeSet};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).MergeData(std::move(obj));

  impl_->ref_.SetData(std::move(parsed),
      [context, callback](Status status) {
        if (status.ok()) {
          callback(context, "");
        } else {
          std::string msg = status.error_message();
          callback(context, msg.c_str());
        }
      });
  return "";
}

std::string DocumentReferenceBridge::UpdateDataC(
    const BridgeFieldValueMap& data,
    void* context,
    ErrorCallback callback) noexcept {
  if (!impl_) {
    return "DocumentReference is not initialized";
  }

  const auto& db_id = impl_->ref_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Update};
  ParseContext parse_context = accumulator.RootContext();
  ObjectValue update_data;

  for (const auto& entry : data) {
    auto path = FieldPath::FromDotSeparatedString(entry.first);

    if (entry.second.tag() == BridgeFieldValue::Tag::SentinelDelete) {
      parse_context.AddToFieldMask(std::move(path));
    } else {
      auto parsed_val = ConvertValue(entry.second,
                                      parse_context.ChildContext(path),
                                      db_id);
      if (parsed_val) {
        parse_context.AddToFieldMask(path);
        update_data.Set(path, std::move(*parsed_val));
      }
    }
  }

  auto parsed = std::move(accumulator).UpdateData(std::move(update_data));

  impl_->ref_.UpdateData(std::move(parsed),
      [context, callback](Status status) {
        if (status.ok()) {
          callback(context, "");
        } else {
          std::string msg = status.error_message();
          callback(context, msg.c_str());
        }
      });
  return "";
}

// ===========================================================================
// DocumentSnapshotBridge — data() (UserDataWriter equivalent)
// ===========================================================================
// Converts the internal protobuf document data to BridgeFieldValueMap.
// server_ts_behavior: 0 = none (null), 1 = estimate, 2 = previous

namespace {

// Forward declarations with server_ts_behavior parameter.
BridgeFieldValue ConvertProtoValue(
    const google_firestore_v1_Value& value,
    const std::shared_ptr<Firestore>& firestore,
    int32_t server_ts_behavior);

BridgeFieldValueMap ConvertProtoMap(
    const google_firestore_v1_MapValue& map_value,
    const std::shared_ptr<Firestore>& firestore,
    int32_t server_ts_behavior) {
  BridgeFieldValueMap result;
  for (pb_size_t i = 0; i < map_value.fields_count; ++i) {
    std::string key = nanopb::MakeString(map_value.fields[i].key);
    result.push_back({std::move(key),
                      ConvertProtoValue(map_value.fields[i].value, firestore,
                                        server_ts_behavior)});
  }
  return result;
}

BridgeFieldValueVector ConvertProtoArray(
    const google_firestore_v1_ArrayValue& array_value,
    const std::shared_ptr<Firestore>& firestore,
    int32_t server_ts_behavior) {
  BridgeFieldValueVector result;
  for (pb_size_t i = 0; i < array_value.values_count; ++i) {
    result.push_back(ConvertProtoValue(array_value.values[i], firestore,
                                       server_ts_behavior));
  }
  return result;
}

BridgeFieldValue ConvertProtoValue(
    const google_firestore_v1_Value& value,
    const std::shared_ptr<Firestore>& firestore,
    int32_t server_ts_behavior) {
  switch (model::GetTypeOrder(value)) {
    case model::TypeOrder::kNull:
      return BridgeFieldValue::Null();

    case model::TypeOrder::kBoolean:
      return BridgeFieldValue::FromBool(value.boolean_value);

    case model::TypeOrder::kNumber:
      if (value.which_value_type ==
          google_firestore_v1_Value_integer_value_tag) {
        return BridgeFieldValue::FromInt64(value.integer_value);
      } else {
        return BridgeFieldValue::FromDouble(value.double_value);
      }

    case model::TypeOrder::kString: {
      std::string str = nanopb::MakeString(value.string_value);
      return BridgeFieldValue::FromString(str);
    }

    case model::TypeOrder::kBlob: {
      std::string bytes(
          reinterpret_cast<const char*>(value.bytes_value->bytes),
          value.bytes_value->size);
      return BridgeFieldValue::FromBlob(bytes);
    }

    case model::TypeOrder::kTimestamp:
      return BridgeFieldValue::FromTimestamp(
          value.timestamp_value.seconds,
          value.timestamp_value.nanos);

    case model::TypeOrder::kGeoPoint:
      return BridgeFieldValue::FromGeoPoint(
          value.geo_point_value.latitude,
          value.geo_point_value.longitude);

    case model::TypeOrder::kReference: {
      std::string ref = nanopb::MakeString(value.reference_value);
      DocumentKey key = DocumentKey::FromName(ref);
      return BridgeFieldValue::FromReference(key.ToString());
    }

    case model::TypeOrder::kArray:
      return BridgeFieldValue::FromArray(
          ConvertProtoArray(value.array_value, firestore,
                            server_ts_behavior));

    case model::TypeOrder::kMap:
      return BridgeFieldValue::FromMap(
          ConvertProtoMap(value.map_value, firestore,
                          server_ts_behavior));

    case model::TypeOrder::kVector: {
      DoubleVector doubles;
      for (pb_size_t i = 0; i < value.map_value.fields_count; ++i) {
        std::string key = nanopb::MakeString(value.map_value.fields[i].key);
        if (key == "value" &&
            value.map_value.fields[i].value.which_value_type ==
                google_firestore_v1_Value_array_value_tag) {
          const auto& arr = value.map_value.fields[i].value.array_value;
          for (pb_size_t j = 0; j < arr.values_count; ++j) {
            doubles.push_back(arr.values[j].double_value);
          }
        }
      }
      return BridgeFieldValue::FromVector(doubles);
    }

    case model::TypeOrder::kServerTimestamp: {
      if (server_ts_behavior == 1) {
        // Estimate: return local write time as a Timestamp
        auto ts = model::GetLocalWriteTime(value);
        return BridgeFieldValue::FromTimestamp(ts.seconds, ts.nanos);
      } else if (server_ts_behavior == 2) {
        // Previous: return the previous value, or null
        auto prev = model::GetPreviousValue(value);
        if (prev.has_value()) {
          return ConvertProtoValue(*prev, firestore, server_ts_behavior);
        }
        return BridgeFieldValue::Null();
      }
      // None (0): return null
      return BridgeFieldValue::Null();
    }

    case model::TypeOrder::kMaxValue:
      return BridgeFieldValue::Null();
  }

  return BridgeFieldValue::Null();
}

}  // anonymous namespace

BridgeFieldValueMap DocumentSnapshotBridge::data() const noexcept {
  return data_with_server_timestamps(0);
}

BridgeFieldValueMap DocumentSnapshotBridge::data_with_server_timestamps(
    int32_t behavior) const noexcept {
  if (!impl_) return BridgeFieldValueMap{};
  if (!impl_->snapshot_.exists()) return BridgeFieldValueMap{};

  const auto& doc = impl_->snapshot_.internal_document();
  if (!doc.has_value()) return BridgeFieldValueMap{};

  const auto& value = doc->get().value();
  if (value.which_value_type != google_firestore_v1_Value_map_value_tag) {
    return BridgeFieldValueMap{};
  }

  auto firestore = impl_->snapshot_.firestore();
  return ConvertProtoMap(value.map_value, firestore, behavior);
}

BridgeFieldValue DocumentSnapshotBridge::get_field(
    const std::string& field_path) const noexcept {
  return get_field_with_server_timestamps(field_path, 0);
}

BridgeFieldValue DocumentSnapshotBridge::get_field_with_server_timestamps(
    const std::string& field_path, int32_t behavior) const noexcept {
  if (!impl_) return BridgeFieldValue::Null();
  if (!impl_->snapshot_.exists()) return BridgeFieldValue::Null();

  auto path = FieldPath::FromDotSeparatedString(field_path);
  auto value = impl_->snapshot_.GetValue(path);
  if (!value.has_value()) return BridgeFieldValue::Null();

  auto firestore = impl_->snapshot_.firestore();
  return ConvertProtoValue(*value, firestore, behavior);
}

// ===========================================================================
// QueryBridge — Where filter operations
// ===========================================================================
// These are defined here (after ConvertMap/ConvertValue) so they can use them.

namespace {

nanopb::SharedMessage<google_firestore_v1_Value> BridgeValueToProto(
    const BridgeFieldValue& value,
    const DatabaseId& database_id) {
  ParseAccumulator accumulator{UserDataSource::Argument};
  auto converted = ConvertValue(value, accumulator.RootContext(), database_id);
  if (converted) {
    return nanopb::SharedMessage<google_firestore_v1_Value>(
        std::move(*converted));
  }
  return nanopb::SharedMessage<google_firestore_v1_Value>(
      model::DeepClone(model::NullValue()));
}

nanopb::SharedMessage<google_firestore_v1_Value> BridgeValuesToArrayProto(
    const BridgeFieldValueVector& values,
    const DatabaseId& database_id) {
  Message<google_firestore_v1_Value> array_val;
  array_val->which_value_type = google_firestore_v1_Value_array_value_tag;
  array_val->array_value.values_count =
      static_cast<pb_size_t>(values.size());
  array_val->array_value.values =
      nanopb::MakeArray<google_firestore_v1_Value>(
          array_val->array_value.values_count);

  for (size_t i = 0; i < values.size(); ++i) {
    ParseAccumulator accumulator{UserDataSource::Argument};
    auto converted = ConvertValue(values[i], accumulator.RootContext(),
                                   database_id);
    if (converted) {
      array_val->array_value.values[i] = *converted->release();
    } else {
      array_val->array_value.values[i] = model::NullValue();
    }
  }

  return nanopb::SharedMessage<google_firestore_v1_Value>(
      std::move(array_val));
}

}  // anonymous namespace

QueryBridge QueryBridge::WhereEqualTo(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::Equal,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereNotEqualTo(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::NotEqual,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereLessThan(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::LessThan,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereGreaterThan(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::GreaterThan,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereLessThanOrEqual(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::LessThanOrEqual,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereGreaterThanOrEqual(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(),
      FieldFilter::Operator::GreaterThanOrEqual,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereArrayContains(
    const std::string& field,
    const BridgeFieldValue& value) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::ArrayContains,
      BridgeValueToProto(value, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereIn(
    const std::string& field,
    const BridgeFieldValueVector& values) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::In,
      BridgeValuesToArrayProto(values, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereNotIn(
    const std::string& field,
    const BridgeFieldValueVector& values) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(), FieldFilter::Operator::NotIn,
      BridgeValuesToArrayProto(values, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

QueryBridge QueryBridge::WhereArrayContainsAny(
    const std::string& field,
    const BridgeFieldValueVector& values) const noexcept {
  if (!impl_) return QueryBridge{};
  auto db_id = impl_->query_.firestore()->database_id();
  auto field_path = FieldPath::FromServerFormat(field);
  if (!field_path.ok()) return QueryBridge{};
  auto filter = impl_->query_.ParseFieldFilter(
      std::move(field_path).ValueOrDie(),
      FieldFilter::Operator::ArrayContainsAny,
      BridgeValuesToArrayProto(values, db_id),
      []() -> std::string { return "a value"; });
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.AddNewFilter(std::move(filter)));
  return result;
}

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

