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
#include "Firestore/core/src/core/listen_options.h"
#include "Firestore/core/src/model/field_path.h"
#include "Firestore/core/src/model/resource_path.h"
#include "Firestore/core/src/util/status.h"
#include "Firestore/core/src/util/statusor.h"

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

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase
