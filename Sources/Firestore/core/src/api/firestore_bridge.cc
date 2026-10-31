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

#include <future>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "Firestore/core/src/api/collection_reference.h"
#include "Firestore/core/src/api/document_change.h"
#include "Firestore/core/src/api/document_reference.h"
#include "Firestore/core/src/api/document_snapshot.h"
#include "Firestore/core/src/api/firestore.h"
#include "Firestore/core/src/api/listener_registration.h"
#include "Firestore/core/src/api/query_core.h"
#include "Firestore/core/src/api/query_snapshot.h"
#include "Firestore/core/src/api/source.h"
#include "Firestore/core/src/api/write_batch.h"
#include "Firestore/core/src/core/event_listener.h"
#include "Firestore/core/src/core/bound.h"
#include "Firestore/core/src/core/field_filter.h"
#include "Firestore/core/src/core/listen_options.h"
#include "Firestore/core/src/core/order_by.h"
#include "Firestore/core/src/core/transaction.h"
#include "Firestore/core/src/core/user_data.h"
#include "Firestore/core/src/api/settings.h"
#include "Firestore/core/src/credentials/auth_token.h"
#include "Firestore/core/src/credentials/credentials_provider.h"
#include "Firestore/core/src/credentials/user.h"
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
#include "Firestore/core/src/remote/firebase_metadata_provider_noop.h"
#include "Firestore/core/src/util/async_queue.h"
#include "Firestore/core/src/util/executor.h"
#include "Firestore/core/src/util/hard_assert.h"
#include "Firestore/core/src/util/log.h"
#include "Firestore/core/src/util/status.h"
#include "Firestore/core/src/util/statusor.h"

#include "absl/types/optional.h"

namespace firebase {
namespace firestore {
namespace swift_bridge {

using api::CollectionReference;
using api::DocumentChange;
using api::DocumentReference;
using api::DocumentSnapshot;
using api::Firestore;
using api::Query;
using api::QuerySnapshot;
using api::Source;
using api::WriteBatch;
using api::Settings;
using core::Bound;
using core::EventListener;
using core::FieldFilter;
using core::OrderBy;
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

bool DocumentReferenceBridge::IsEqual(
    const DocumentReferenceBridge& other) const noexcept {
  if (!impl_ || !other.impl_) return impl_ == other.impl_;
  return impl_->ref_ == other.impl_->ref_;
}

size_t DocumentReferenceBridge::Hash() const noexcept {
  return impl_ ? impl_->ref_.Hash() : 0;
}

CollectionReferenceBridge DocumentReferenceBridge::parent() const noexcept {
  if (!impl_) return CollectionReferenceBridge{};
  CollectionReferenceBridge result;
  auto parent_ref = impl_->ref_.Parent();
  result.impl_ = std::make_shared<QueryBridge::Impl>(
      Query{parent_ref.query(), parent_ref.firestore()});
  return result;
}

CollectionReferenceBridge DocumentReferenceBridge::Collection(
    const std::string& collection_path) const noexcept {
  if (!impl_) return CollectionReferenceBridge{};
  auto collection = impl_->ref_.GetCollectionReference(collection_path);
  CollectionReferenceBridge result;
  result.impl_ = std::make_shared<QueryBridge::Impl>(
      Query{collection.query(), collection.firestore()});
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
// QueryBridge — Cursor methods
// ===========================================================================

namespace {

// Helper to create a Bound from a DocumentSnapshot.
// Mirrors the ObjC++ FIRQuery boundFromSnapshot:isInclusive: logic.
Bound BoundFromSnapshot(const api::DocumentSnapshot& snapshot,
                        bool is_inclusive,
                        const core::Query& query) {
  if (!snapshot.exists()) {
    // Invalid — return an empty bound. In production this would throw.
    return Bound::FromValue(nanopb::SharedMessage<google_firestore_v1_ArrayValue>{{}},
                            is_inclusive);
  }

  const auto& document = *snapshot.internal_document();
  const auto& database_id = snapshot.firestore()->database_id();
  const auto& order_bys = query.normalized_order_bys();

  nanopb::SharedMessage<google_firestore_v1_ArrayValue> components{{}};
  components->values_count = static_cast<pb_size_t>(order_bys.size());
  components->values = nanopb::MakeArray<google_firestore_v1_Value>(
      components->values_count);

  for (size_t i = 0; i < order_bys.size(); ++i) {
    if (order_bys[i].field() == FieldPath::KeyFieldPath()) {
      components->values[i] =
          *model::RefValue(database_id, document->key()).release();
    } else {
      auto value = document->field(order_bys[i].field());
      if (value) {
        components->values[i] = *model::DeepClone(*value).release();
      }
    }
  }
  return Bound::FromValue(std::move(components), is_inclusive);
}

}  // namespace

QueryBridge QueryBridge::StartAtDocument(
    const DocumentSnapshotBridge& snapshot) const noexcept {
  if (!impl_ || !snapshot.impl_) return QueryBridge{};
  auto bound = BoundFromSnapshot(
      snapshot.impl_->snapshot_, /*is_inclusive=*/true, impl_->query_.query());
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.StartAt(std::move(bound)));
  return result;
}

QueryBridge QueryBridge::StartAfterDocument(
    const DocumentSnapshotBridge& snapshot) const noexcept {
  if (!impl_ || !snapshot.impl_) return QueryBridge{};
  auto bound = BoundFromSnapshot(
      snapshot.impl_->snapshot_, /*is_inclusive=*/false, impl_->query_.query());
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.StartAt(std::move(bound)));
  return result;
}

QueryBridge QueryBridge::EndAtDocument(
    const DocumentSnapshotBridge& snapshot) const noexcept {
  if (!impl_ || !snapshot.impl_) return QueryBridge{};
  auto bound = BoundFromSnapshot(
      snapshot.impl_->snapshot_, /*is_inclusive=*/true, impl_->query_.query());
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.EndAt(std::move(bound)));
  return result;
}

QueryBridge QueryBridge::EndBeforeDocument(
    const DocumentSnapshotBridge& snapshot) const noexcept {
  if (!impl_ || !snapshot.impl_) return QueryBridge{};
  auto bound = BoundFromSnapshot(
      snapshot.impl_->snapshot_, /*is_inclusive=*/false, impl_->query_.query());
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(
      impl_->query_.EndAt(std::move(bound)));
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

QueryBridge CollectionReferenceBridge::as_query() const noexcept {
  // Return a QueryBridge that shares the same impl_.
  QueryBridge result;
  result.impl_ = impl_;
  return result;
}

// ===========================================================================
// FirestoreBridge::Impl
// ===========================================================================
// MARK: - Credentials

namespace {

using credentials::AuthToken;
using credentials::CredentialChangeListener;
using credentials::TokenListener;
using credentials::User;

/// A Swift object that supplies tokens. The Swift side retains it for us;
/// it's released when the last provider using it goes away.
class TokenSource {
 public:
  TokenSource(void* context,
              TokenRequestCallback request_token,
              ContextReleaseCallback release_context)
      : context_(context),
        request_token_(request_token),
        release_context_(release_context) {}

  ~TokenSource() {
    if (context_ && release_context_) release_context_(context_);
  }

  TokenSource(const TokenSource&) = delete;
  TokenSource& operator=(const TokenSource&) = delete;

  bool available() const {
    return request_token_ != nullptr;
  }

  /// `done` receives (token, error) exactly once, on any thread.
  void RequestToken(bool force_refresh,
                    std::function<void(std::string, std::string)> done) const;

 private:
  void* context_;
  TokenRequestCallback request_token_;
  ContextReleaseCallback release_context_;
};

/// The pending request handed to Swift as an opaque pointer.
struct TokenRequest {
  std::function<void(std::string, std::string)> done;
};

void TokenSource::RequestToken(
    bool force_refresh,
    std::function<void(std::string, std::string)> done) const {
  auto* request = new TokenRequest{std::move(done)};
  request_token_(context_, force_refresh, request);
}

User UserFromUid(const std::string& uid) {
  return uid.empty() ? User::Unauthenticated() : User(uid);
}

/// Auth credentials backed by Swift's `AuthInterop`. Mirrors
/// firebase_auth_credentials_provider_apple.mm: user changes are pushed in via
/// `UserChanged`, and a token request that is outstanding while the user
/// changes is retried, since its token may belong to the previous user.
class SwiftAuthCredentialsProvider
    : public credentials::AuthCredentialsProvider,
      public std::enable_shared_from_this<SwiftAuthCredentialsProvider> {
 public:
  SwiftAuthCredentialsProvider(std::shared_ptr<TokenSource> source,
                               const std::string& initial_uid)
      : source_(std::move(source)), current_user_(UserFromUid(initial_uid)) {}

  void GetToken(TokenListener<AuthToken> completion) override {
    int initial_token_counter;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      initial_token_counter = token_counter_;
    }
    bool force_refresh = force_refresh_.exchange(false);

    if (!source_ || !source_->available()) {
      completion(AuthToken::Unauthenticated());
      return;
    }

    // Keep the provider alive while the request is outstanding.
    std::shared_ptr<SwiftAuthCredentialsProvider> self = shared_from_this();
    source_->RequestToken(
        force_refresh, [self, initial_token_counter, completion](
                           std::string token, std::string error) {
          std::unique_lock<std::mutex> lock(self->mutex_);
          if (initial_token_counter != self->token_counter_) {
            lock.unlock();
            LOG_DEBUG("GetToken aborted due to token change.");
            self->GetToken(completion);
            return;
          }
          User user = self->current_user_;
          lock.unlock();

          if (!error.empty()) {
            completion(util::Status(Error::kErrorUnknown, error));
          } else if (token.empty()) {
            completion(AuthToken::Unauthenticated());
          } else {
            completion(AuthToken{std::move(token), std::move(user)});
          }
        });
  }

  void SetCredentialChangeListener(
      CredentialChangeListener<User> change_listener) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (change_listener) {
      HARD_ASSERT(!change_listener_, "set change_listener twice!");
      // Fire initial event.
      change_listener(current_user_);
    } else {
      HARD_ASSERT(change_listener_,
                  "change_listener removed without being set!");
    }
    change_listener_ = std::move(change_listener);
  }

  void UserChanged(const std::string& uid) {
    std::lock_guard<std::mutex> lock(mutex_);
    current_user_ = UserFromUid(uid);
    token_counter_++;
    if (change_listener_) {
      change_listener_(current_user_);
    }
  }

 private:
  std::shared_ptr<TokenSource> source_;
  std::mutex mutex_;
  User current_user_;
  int token_counter_ = 0;
};

/// App Check credentials backed by Swift's `AppCheckInterop`. Mirrors
/// firebase_app_check_credentials_provider_apple.mm, except that token-change
/// notifications aren't wired up yet (AppCheckInterop has none).
class SwiftAppCheckCredentialsProvider
    : public credentials::AppCheckCredentialsProvider,
      public std::enable_shared_from_this<SwiftAppCheckCredentialsProvider> {
 public:
  explicit SwiftAppCheckCredentialsProvider(std::shared_ptr<TokenSource> source)
      : source_(std::move(source)) {}

  void GetToken(TokenListener<std::string> completion) override {
    bool force_refresh = force_refresh_.exchange(false);
    if (!source_ || !source_->available()) {
      // Without App Check, send no token.
      completion(std::string{});
      return;
    }
    std::shared_ptr<SwiftAppCheckCredentialsProvider> self = shared_from_this();
    source_->RequestToken(force_refresh, [self, completion](std::string token,
                                                            std::string error) {
      if (!error.empty()) {
        LOG_WARN("AppCheck failed: '%s'", error);
      }
      completion(std::move(token));  // Always return token
    });
  }

  void SetCredentialChangeListener(
      CredentialChangeListener<std::string> change_listener) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (change_listener) {
      HARD_ASSERT(!change_listener_, "set change_listener twice!");
      // Fire initial event.
      change_listener(std::string{});
    } else {
      HARD_ASSERT(change_listener_,
                  "change_listener removed without being set!");
    }
    change_listener_ = std::move(change_listener);
  }

 private:
  std::shared_ptr<TokenSource> source_;
  std::mutex mutex_;
};

void CompleteTokenRequest(void* request,
                          const std::string& token,
                          const std::string& error) {
  HARD_ASSERT(request, "Completing a null token request");
  std::unique_ptr<TokenRequest> owned(static_cast<TokenRequest*>(request));
  owned->done(token, error);
}

}  // namespace

void CompleteAuthTokenRequest(void* request,
                              const std::string& token,
                              const std::string& error) noexcept {
  CompleteTokenRequest(request, token, error);
}

void CompleteAppCheckTokenRequest(void* request,
                                  const std::string& token,
                                  const std::string& error) noexcept {
  CompleteTokenRequest(request, token, error);
}

// MARK: - FirestoreBridge

struct FirestoreBridge::Impl {
  Impl(std::shared_ptr<Firestore> firestore,
       std::shared_ptr<SwiftAuthCredentialsProvider> auth_provider)
      : firestore_(std::move(firestore)),
        auth_provider_(std::move(auth_provider)) {}
  std::shared_ptr<Firestore> firestore_;
  std::shared_ptr<SwiftAuthCredentialsProvider> auth_provider_;
};

FirestoreBridge::FirestoreBridge() noexcept = default;
FirestoreBridge::~FirestoreBridge() noexcept = default;
FirestoreBridge::FirestoreBridge(const FirestoreBridge&) noexcept = default;
FirestoreBridge& FirestoreBridge::operator=(
    const FirestoreBridge&) noexcept = default;
FirestoreBridge::FirestoreBridge(FirestoreBridge&&) noexcept = default;
FirestoreBridge& FirestoreBridge::operator=(FirestoreBridge&&) noexcept =
    default;

FirestoreBridge FirestoreBridge::Create(
    const std::string& project_id,
    const std::string& database_id,
    const std::string& persistence_key,
    void* auth_context,
    TokenRequestCallback request_auth_token,
    const std::string& initial_uid,
    void* app_check_context,
    TokenRequestCallback request_app_check_token,
    ContextReleaseCallback release_context) noexcept {
  auto auth_credentials = std::make_shared<SwiftAuthCredentialsProvider>(
      std::make_shared<TokenSource>(auth_context, request_auth_token,
                                    release_context),
      initial_uid);
  auto app_check_credentials =
      std::make_shared<SwiftAppCheckCredentialsProvider>(
          std::make_shared<TokenSource>(app_check_context,
                                        request_app_check_token,
                                        release_context));
  auto worker_queue = util::AsyncQueue::Create(
      util::Executor::CreateSerial("com.google.firebase.firestore.worker"));
  auto metadata_provider = remote::CreateFirebaseMetadataProviderNoOp();

  auto firestore = std::make_shared<Firestore>(
      DatabaseId{project_id, database_id},
      persistence_key,
      auth_credentials,
      std::move(app_check_credentials),
      std::move(worker_queue),
      std::move(metadata_provider),
      /*extension=*/nullptr);

  // Set a user executor for callbacks.
  firestore->set_user_executor(
      util::Executor::CreateSerial("com.google.firebase.firestore.callback"));

  FirestoreBridge result;
  result.impl_ =
      std::make_shared<Impl>(std::move(firestore), std::move(auth_credentials));
  return result;
}

void FirestoreBridge::SetAuthUser(const std::string& uid) const noexcept {
  if (impl_ && impl_->auth_provider_) {
    impl_->auth_provider_->UserChanged(uid);
  }
}

bool FirestoreBridge::is_valid() const noexcept {
  return impl_ != nullptr;
}

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

QueryBridge FirestoreBridge::GetCollectionGroup(
    const std::string& collection_id) const noexcept {
  if (!impl_) return QueryBridge{};
  auto core_query = impl_->firestore_->GetCollectionGroup(collection_id);
  Query api_query(std::move(core_query), impl_->firestore_);
  QueryBridge result;
  result.impl_ = std::make_shared<QueryBridge::Impl>(std::move(api_query));
  return result;
}

void FirestoreBridge::Terminate(
    void* context, ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "Firestore is not initialized");
    return;
  }
  impl_->firestore_->Terminate([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

void FirestoreBridge::ClearPersistence(
    void* context, ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "Firestore is not initialized");
    return;
  }
  impl_->firestore_->ClearPersistence([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

void FirestoreBridge::WaitForPendingWrites(
    void* context, ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "Firestore is not initialized");
    return;
  }
  impl_->firestore_->WaitForPendingWrites([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

void FirestoreBridge::EnableNetwork(
    void* context, ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "Firestore is not initialized");
    return;
  }
  impl_->firestore_->EnableNetwork([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

void FirestoreBridge::DisableNetwork(
    void* context, ErrorCallback callback) const noexcept {
  if (!impl_) {
    callback(context, "Firestore is not initialized");
    return;
  }
  impl_->firestore_->DisableNetwork([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

// ===========================================================================
// FirestoreBridge — Settings
// ===========================================================================

std::string FirestoreBridge::settings_host() const noexcept {
  if (!impl_) return Settings::DefaultHost;
  return impl_->firestore_->settings().host();
}

bool FirestoreBridge::settings_persistence_enabled() const noexcept {
  if (!impl_) return Settings::DefaultPersistenceEnabled;
  return impl_->firestore_->settings().persistence_enabled();
}

bool FirestoreBridge::settings_ssl_enabled() const noexcept {
  if (!impl_) return Settings::DefaultSslEnabled;
  return impl_->firestore_->settings().ssl_enabled();
}

int64_t FirestoreBridge::settings_cache_size_bytes() const noexcept {
  if (!impl_) return Settings::DefaultCacheSizeBytes;
  return impl_->firestore_->settings().cache_size_bytes();
}

void FirestoreBridge::set_settings_host(const std::string& host) noexcept {
  if (!impl_) return;
  Settings settings = impl_->firestore_->settings();
  settings.set_host(host);
  impl_->firestore_->set_settings(settings);
}

void FirestoreBridge::set_settings_persistence_enabled(bool enabled) noexcept {
  if (!impl_) return;
  Settings settings = impl_->firestore_->settings();
  settings.set_persistence_enabled(enabled);
  impl_->firestore_->set_settings(settings);
}

void FirestoreBridge::set_settings_ssl_enabled(bool enabled) noexcept {
  if (!impl_) return;
  Settings settings = impl_->firestore_->settings();
  settings.set_ssl_enabled(enabled);
  impl_->firestore_->set_settings(settings);
}

void FirestoreBridge::set_settings_cache_size_bytes(int64_t bytes) noexcept {
  if (!impl_) return;
  Settings settings = impl_->firestore_->settings();
  settings.set_cache_size_bytes(bytes);
  impl_->firestore_->set_settings(settings);
}

void FirestoreBridge::apply_settings() noexcept {
  // Settings are already applied immediately in the set_settings_* methods.
  // This is a no-op placeholder for future use.
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

BridgeFieldValue BridgeFieldValue::FromBlob(const uint8_t* bytes,
                                            size_t size) noexcept {
  // Empty Data has no base address, and std::string(nullptr, 0) is undefined.
  if (!bytes || size == 0) return FromBlob(std::string());
  return FromBlob(std::string(reinterpret_cast<const char*>(bytes), size));
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
      } else if (value.which_value_type ==
                 google_firestore_v1_Value_double_value_tag) {
        return BridgeFieldValue::FromDouble(value.double_value);
      } else if (model::IsInt32Value(value)) {
        // An Int32Value is the map {"__int__": <integer>}.
        return BridgeFieldValue::FromInt64(
            value.map_value.fields[0].value.integer_value);
      }
      // A Decimal128Value has no Swift counterpart yet; pass its map along.
      return BridgeFieldValue::FromMap(
          ConvertProtoMap(value.map_value, firestore, server_ts_behavior));

    // The BSON types are maps with a special key. Until the bridge has Swift
    // types for them, they reach Swift as those maps rather than as null.
    case model::TypeOrder::kMinKey:
    case model::TypeOrder::kBsonTimestamp:
    case model::TypeOrder::kBsonObjectId:
    case model::TypeOrder::kRegex:
    case model::TypeOrder::kMaxKey:
      return BridgeFieldValue::FromMap(
          ConvertProtoMap(value.map_value, firestore, server_ts_behavior));

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

    case model::TypeOrder::kInternalMaxValue:
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

// ===========================================================================
// DocumentChangeBridge
// ===========================================================================
struct DocumentChangeBridge::Impl {
  Impl(DocumentChange change) : change_(std::move(change)) {}
  DocumentChange change_;
};

DocumentChangeBridge::DocumentChangeBridge() noexcept = default;
DocumentChangeBridge::~DocumentChangeBridge() noexcept = default;
DocumentChangeBridge::DocumentChangeBridge(
    const DocumentChangeBridge&) noexcept = default;
DocumentChangeBridge& DocumentChangeBridge::operator=(
    const DocumentChangeBridge&) noexcept = default;
DocumentChangeBridge::DocumentChangeBridge(
    DocumentChangeBridge&&) noexcept = default;
DocumentChangeBridge& DocumentChangeBridge::operator=(
    DocumentChangeBridge&&) noexcept = default;

DocumentChangeBridge::Type DocumentChangeBridge::type() const noexcept {
  if (!impl_) return Type::Added;
  switch (impl_->change_.type()) {
    case DocumentChange::Type::Added: return Type::Added;
    case DocumentChange::Type::Modified: return Type::Modified;
    case DocumentChange::Type::Removed: return Type::Removed;
  }
  return Type::Added;
}

DocumentSnapshotBridge DocumentChangeBridge::document() const noexcept {
  if (!impl_) return DocumentSnapshotBridge{};
  DocumentSnapshotBridge result;
  result.impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
      impl_->change_.document());
  return result;
}

int64_t DocumentChangeBridge::old_index() const noexcept {
  if (!impl_) return -1;
  auto idx = impl_->change_.old_index();
  return idx == DocumentChange::npos ? -1 : static_cast<int64_t>(idx);
}

int64_t DocumentChangeBridge::new_index() const noexcept {
  if (!impl_) return -1;
  auto idx = impl_->change_.new_index();
  return idx == DocumentChange::npos ? -1 : static_cast<int64_t>(idx);
}

// ===========================================================================
// QuerySnapshotBridge — document_changes
// ===========================================================================
DocumentChangeBridgeVector QuerySnapshotBridge::document_changes(
    bool include_metadata_changes) const noexcept {
  DocumentChangeBridgeVector result;
  if (!impl_) return result;
  impl_->snapshot_.ForEachChange(
      include_metadata_changes,
      [&result](DocumentChange change) {
        DocumentChangeBridge bridge;
        bridge.impl_ = std::make_shared<DocumentChangeBridge::Impl>(
            std::move(change));
        result.push_back(std::move(bridge));
      });
  return result;
}

// ===========================================================================
// WriteBatchBridge
// ===========================================================================
struct WriteBatchBridge::Impl {
  explicit Impl(WriteBatch batch) : batch_(std::move(batch)) {}
  WriteBatch batch_;
};

WriteBatchBridge::WriteBatchBridge() noexcept = default;
WriteBatchBridge::~WriteBatchBridge() noexcept = default;
WriteBatchBridge::WriteBatchBridge(
    const WriteBatchBridge&) noexcept = default;
WriteBatchBridge& WriteBatchBridge::operator=(
    const WriteBatchBridge&) noexcept = default;
WriteBatchBridge::WriteBatchBridge(
    WriteBatchBridge&&) noexcept = default;
WriteBatchBridge& WriteBatchBridge::operator=(
    WriteBatchBridge&&) noexcept = default;

std::string WriteBatchBridge::SetData(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "WriteBatch or DocumentReference not initialized";

  const auto& db_id = impl_->batch_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Set};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).SetData(std::move(obj));

  impl_->batch_.SetData(doc.impl_->ref_, std::move(parsed));
  return "";
}

std::string WriteBatchBridge::SetDataMerge(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "WriteBatch or DocumentReference not initialized";

  const auto& db_id = impl_->batch_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::MergeSet};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).MergeData(std::move(obj));

  impl_->batch_.SetData(doc.impl_->ref_, std::move(parsed));
  return "";
}

std::string WriteBatchBridge::UpdateData(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "WriteBatch or DocumentReference not initialized";

  const auto& db_id = impl_->batch_.firestore()->database_id();
  ParseAccumulator accumulator{UserDataSource::Update};
  ParseContext context = accumulator.RootContext();
  ObjectValue update_data;

  for (const auto& entry : data) {
    auto path = FieldPath::FromDotSeparatedString(entry.first);

    if (entry.second.tag() == BridgeFieldValue::Tag::SentinelDelete) {
      context.AddToFieldMask(std::move(path));
    } else {
      auto parsed = ConvertValue(entry.second, context.ChildContext(path), db_id);
      if (parsed) {
        context.AddToFieldMask(path);
        update_data.Set(path, std::move(*parsed));
      }
    }
  }

  auto parsed = std::move(accumulator).UpdateData(std::move(update_data));
  impl_->batch_.UpdateData(doc.impl_->ref_, std::move(parsed));
  return "";
}

void WriteBatchBridge::DeleteData(
    const DocumentReferenceBridge& doc) noexcept {
  if (!impl_ || !doc.impl_) return;
  impl_->batch_.DeleteData(doc.impl_->ref_);
}

void WriteBatchBridge::Commit(void* context, ErrorCallback callback) noexcept {
  if (!impl_) {
    callback(context, "WriteBatch is not initialized");
    return;
  }

  impl_->batch_.Commit([context, callback](Status status) {
    if (status.ok()) {
      callback(context, "");
    } else {
      std::string msg = status.error_message();
      callback(context, msg.c_str());
    }
  });
}

// ===========================================================================
// TransactionBridge
// ===========================================================================
struct TransactionBridge::Impl {
  explicit Impl(std::shared_ptr<core::Transaction> txn,
                std::shared_ptr<Firestore> firestore)
      : txn_(std::move(txn)), firestore_(std::move(firestore)) {}
  std::shared_ptr<core::Transaction> txn_;
  std::shared_ptr<Firestore> firestore_;
};

TransactionBridge::TransactionBridge() noexcept = default;
TransactionBridge::~TransactionBridge() noexcept = default;

DocumentSnapshotBridge TransactionBridge::GetDocument(
    const DocumentReferenceBridge& doc,
    std::string& out_error) const noexcept {
  if (!impl_ || !doc.impl_) {
    out_error = "Transaction or DocumentReference not initialized";
    return DocumentSnapshotBridge{};
  }

  // Block until the async Lookup completes, as FIRTransaction does upstream.
  std::promise<void> lookup_done;

  DocumentSnapshotBridge result;
  std::string error_msg;

  auto key = doc.impl_->ref_.key();
  api::SnapshotMetadata meta(/*has_pending_writes=*/false, /*from_cache=*/false);
  impl_->txn_->Lookup(
      {key},
      [&result, &error_msg, &lookup_done, this, key, meta](
          const StatusOr<std::vector<model::Document>>& maybe_docs) {
        if (!maybe_docs.ok()) {
          error_msg = maybe_docs.status().error_message();
        } else {
          const auto& docs = maybe_docs.ValueOrDie();
          if (!docs.empty()) {
            const auto& internal_doc = docs.front();
            DocumentSnapshot snapshot;
            if (internal_doc->is_found_document()) {
              snapshot = DocumentSnapshot::FromDocument(
                  impl_->firestore_, internal_doc, meta);
            } else {
              snapshot = DocumentSnapshot::FromNoDocument(
                  impl_->firestore_, key, meta);
            }
            result.impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
                std::move(snapshot));
          }
        }
        lookup_done.set_value();
      });

  lookup_done.get_future().wait();
  out_error = error_msg;
  return result;
}

std::string TransactionBridge::SetData(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "Transaction or DocumentReference not initialized";

  const auto& db_id = impl_->firestore_->database_id();
  ParseAccumulator accumulator{UserDataSource::Set};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).SetData(std::move(obj));

  impl_->txn_->Set(doc.impl_->ref_.key(), std::move(parsed));
  return "";
}

std::string TransactionBridge::SetDataMerge(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "Transaction or DocumentReference not initialized";

  const auto& db_id = impl_->firestore_->database_id();
  ParseAccumulator accumulator{UserDataSource::MergeSet};
  auto result_value = ConvertMap(data, accumulator.RootContext(), db_id);
  ObjectValue obj{std::move(result_value)};
  auto parsed = std::move(accumulator).MergeData(std::move(obj));

  impl_->txn_->Set(doc.impl_->ref_.key(), std::move(parsed));
  return "";
}

std::string TransactionBridge::UpdateData(
    const DocumentReferenceBridge& doc,
    const BridgeFieldValueMap& data) noexcept {
  if (!impl_ || !doc.impl_) return "Transaction or DocumentReference not initialized";

  const auto& db_id = impl_->firestore_->database_id();
  ParseAccumulator accumulator{UserDataSource::Update};
  ParseContext context = accumulator.RootContext();
  ObjectValue update_data;

  for (const auto& entry : data) {
    auto path = FieldPath::FromDotSeparatedString(entry.first);

    if (entry.second.tag() == BridgeFieldValue::Tag::SentinelDelete) {
      context.AddToFieldMask(std::move(path));
    } else {
      auto parsed = ConvertValue(entry.second, context.ChildContext(path), db_id);
      if (parsed) {
        context.AddToFieldMask(path);
        update_data.Set(path, std::move(*parsed));
      }
    }
  }

  auto parsed = std::move(accumulator).UpdateData(std::move(update_data));
  impl_->txn_->Update(doc.impl_->ref_.key(), std::move(parsed));
  return "";
}

void TransactionBridge::DeleteData(
    const DocumentReferenceBridge& doc) noexcept {
  if (!impl_ || !doc.impl_) return;
  impl_->txn_->Delete(doc.impl_->ref_.key());
}

// ===========================================================================
// FirestoreBridge — GetBatch / RunTransaction
// ===========================================================================
namespace {

/// Runs transaction update blocks off the Firestore worker queue. Never
/// destroyed, so blocks still running at exit don't outlive their executor.
util::Executor& TransactionUserExecutor() {
  static util::Executor* executor =
      util::Executor::CreateConcurrent(
          "com.google.firebase.firestore.transaction", 4)
          .release();
  return *executor;
}

}  // namespace

WriteBatchBridge FirestoreBridge::GetBatch() const noexcept {
  if (!impl_) return WriteBatchBridge{};
  WriteBatchBridge result;
  result.impl_ = std::make_shared<WriteBatchBridge::Impl>(
      impl_->firestore_->GetBatch());
  return result;
}

void FirestoreBridge::RunTransaction(
    void* context,
    TransactionUpdateCallback update_callback,
    void* result_context,
    TransactionResultCallback result_callback,
    int max_attempts) const noexcept {
  if (!impl_) {
    result_callback(result_context, "Firestore is not initialized");
    return;
  }

  // Capture the Firestore instance, not `this`: Swift calls this method on a
  // temporary copy of the bridge, which is gone before the transaction runs.
  auto update_fn = [context, update_callback, firestore = impl_->firestore_](
      std::shared_ptr<core::Transaction> txn,
      core::TransactionResultCallback done) {
    // Create a TransactionBridge on the heap for Swift to use.
    auto* bridge = new TransactionBridge();
    bridge->impl_ = std::make_shared<TransactionBridge::Impl>(txn, firestore);

    // The completion callback that Swift will call when done.
    auto completion_fn = [txn, done = std::move(done)](
        void* /*completion_context*/, const char* error) mutable {
      std::string err(error);
      if (err.empty()) {
        done(Status::OK());
      } else {
        // The update block threw. That is final, so don't retry (kAborted
        // alone counts as retryable).
        txn->MarkPermanentlyFailed();
        done(Status(Error::kErrorAborted, err));
      }
    };

    // Store the completion in a shared_ptr so the C callback can use it.
    auto shared_completion = std::make_shared<decltype(completion_fn)>(
        std::move(completion_fn));

    // C-compatible trampoline for the completion callback.
    ErrorCallback c_completion = [](void* ctx, const char* error) {
      auto* fn = static_cast<decltype(shared_completion.get())>(ctx);
      (*fn)(nullptr, error);
    };

    // This runs on the Firestore worker queue, but the update block calls
    // TransactionBridge::GetDocument, which blocks until a lookup completes
    // on that same queue. Run the block elsewhere, as FIRFirestore does with
    // a global dispatch queue upstream.
    TransactionUserExecutor().Execute(
        [context, update_callback, bridge, c_completion, shared_completion] {
          update_callback(context, static_cast<void*>(bridge), c_completion,
                          static_cast<void*>(shared_completion.get()));
        });
  };

  auto result_fn = [result_context, result_callback](Status status) {
    if (status.ok()) {
      result_callback(result_context, "");
    } else {
      std::string msg = status.error_message();
      result_callback(result_context, msg.c_str());
    }
  };

  impl_->firestore_->RunTransaction(
      std::move(update_fn), std::move(result_fn), max_attempts);
}

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

