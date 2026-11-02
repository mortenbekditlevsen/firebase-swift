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
#include "Firestore/core/src/api/listen_source.h"
#include "Firestore/core/src/core/bound.h"
#include "Firestore/core/src/core/composite_filter.h"
#include "Firestore/core/src/core/filter.h"
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
#include "Firestore/core/src/util/empty.h"
#include "Firestore/core/src/util/exception.h"
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
using model::NumericMaximumTransform;
using model::NumericMinimumTransform;
using model::ObjectValue;
using model::ResourcePath;
using model::ServerTimestampTransform;
using model::TransformOperation;
using nanopb::Message;
using util::Status;
using util::StatusOr;
using util::ThrowInvalidArgument;

namespace {

int32_t ErrorCode(const Status& status) {
  return static_cast<int32_t>(status.code());
}

/// Calls `callback` (if any) with the outcome of an operation.
void Report(ErrorCallback callback, void* context, const Status& status) {
  if (!callback) return;
  if (status.ok()) {
    callback(context, 0, "");
  } else {
    callback(context, ErrorCode(status), status.error_message().c_str());
  }
}

std::function<void(Status)> Reporter(void* context, ErrorCallback callback) {
  return [context, callback](Status status) {
    Report(callback, context, status);
  };
}

/// Hands a snapshot (or the error) to a snapshot callback, which owns the
/// heap-allocated bridge.
template <typename Bridge, typename Snapshot, typename Callback>
void ReportSnapshot(Callback callback, void* context, StatusOr<Snapshot> result,
                    std::function<Bridge*(Snapshot)> make_bridge) {
  if (result.ok()) {
    callback(context, make_bridge(std::move(result).ValueOrDie()), 0, "");
  } else {
    callback(context, nullptr, ErrorCode(result.status()),
             result.status().error_message().c_str());
  }
}

/// Owns a listener's context, releasing it when the last copy of the listener
/// is destroyed.
std::shared_ptr<void> OwnContext(void* context, ContextReleaseCallback release) {
  return std::shared_ptr<void>(context, [release](void* context) {
    if (release && context) release(context);
  });
}

api::ListenSource MakeListenSource(int32_t listen_source) {
  return listen_source == 1 ? api::ListenSource::Cache
                            : api::ListenSource::Default;
}

}  // namespace

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

bool DocumentSnapshotBridge::IsEqual(
    const DocumentSnapshotBridge& other) const noexcept {
  if (!impl_ || !other.impl_) return impl_ == other.impl_;
  return impl_->snapshot_ == other.impl_->snapshot_;
}

size_t DocumentSnapshotBridge::Hash() const noexcept {
  return impl_ ? impl_->snapshot_.Hash() : 0;
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
    void* context,
    DocumentSnapshotCallback callback) const noexcept {
  auto listener = EventListener<DocumentSnapshot>::Create(
      [context, callback](StatusOr<DocumentSnapshot> maybe_snapshot) {
        ReportSnapshot<DocumentSnapshotBridge, DocumentSnapshot>(
            callback, context, std::move(maybe_snapshot),
            [](DocumentSnapshot snapshot) {
              auto* bridge = new DocumentSnapshotBridge();
              bridge->impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
                  std::move(snapshot));
              return bridge;
            });
      });
  impl_->ref_.GetDocument(source, std::move(listener));
}

ListenerRegistrationBridge DocumentReferenceBridge::AddSnapshotListener(
    bool include_metadata_changes,
    int32_t listen_source,
    void* context,
    ContextReleaseCallback release_context,
    DocumentSnapshotCallback callback) const noexcept {
  auto options = core::ListenOptions::FromOptions(
      include_metadata_changes, MakeListenSource(listen_source));
  auto listener = EventListener<DocumentSnapshot>::Create(
      [owned = OwnContext(context, release_context),
       callback](StatusOr<DocumentSnapshot> maybe_snapshot) {
        ReportSnapshot<DocumentSnapshotBridge, DocumentSnapshot>(
            callback, owned.get(), std::move(maybe_snapshot),
            [](DocumentSnapshot snapshot) {
              auto* bridge = new DocumentSnapshotBridge();
              bridge->impl_ = std::make_shared<DocumentSnapshotBridge::Impl>(
                  std::move(snapshot));
              return bridge;
            });
      });

  ListenerRegistrationBridge result;
  result.impl_ = std::make_shared<ListenerRegistrationBridge::Impl>(
      impl_->ref_.AddSnapshotListener(std::move(options), std::move(listener)));
  return result;
}

void DocumentReferenceBridge::DeleteDocument(
    void* context, ErrorCallback callback) const noexcept {
  impl_->ref_.DeleteDocument(Reporter(context, callback));
}

// SetData and UpdateData are defined further below, after UserDataParser.

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

bool QueryBridge::IsEqual(const QueryBridge& other) const noexcept {
  if (!impl_ || !other.impl_) return impl_ == other.impl_;
  return impl_->query_ == other.impl_->query_;
}

size_t QueryBridge::Hash() const noexcept {
  return impl_ ? impl_->query_.Hash() : 0;
}

QueryBridge QueryBridge::OrderBy(const FieldPathSegments& field_path,
                                 bool descending) const noexcept {
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.OrderBy(
      FieldPath(field_path.begin(), field_path.end()), descending));
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
// QueryBridge — reads and listeners
// ===========================================================================

void QueryBridge::GetDocuments(
    Source source,
    void* context,
    QuerySnapshotCallback callback) const noexcept {
  auto listener = EventListener<QuerySnapshot>::Create(
      [context, callback](StatusOr<QuerySnapshot> maybe_snapshot) {
        ReportSnapshot<QuerySnapshotBridge, QuerySnapshot>(
            callback, context, std::move(maybe_snapshot),
            [](QuerySnapshot snapshot) {
              auto* bridge = new QuerySnapshotBridge();
              bridge->impl_ = std::make_shared<QuerySnapshotBridge::Impl>(
                  std::move(snapshot));
              return bridge;
            });
      });
  // GetDocuments is non-const on the C++ side, but doesn't modify the query.
  const_cast<Query&>(impl_->query_).GetDocuments(source, std::move(listener));
}

ListenerRegistrationBridge QueryBridge::AddSnapshotListener(
    bool include_metadata_changes,
    int32_t listen_source,
    void* context,
    ContextReleaseCallback release_context,
    QuerySnapshotCallback callback) const noexcept {
  auto options = core::ListenOptions::FromOptions(
      include_metadata_changes, MakeListenSource(listen_source));
  auto listener = EventListener<QuerySnapshot>::Create(
      [owned = OwnContext(context, release_context),
       callback](StatusOr<QuerySnapshot> maybe_snapshot) {
        ReportSnapshot<QuerySnapshotBridge, QuerySnapshot>(
            callback, owned.get(), std::move(maybe_snapshot),
            [](QuerySnapshot snapshot) {
              auto* bridge = new QuerySnapshotBridge();
              bridge->impl_ = std::make_shared<QuerySnapshotBridge::Impl>(
                  std::move(snapshot));
              return bridge;
            });
      });

  ListenerRegistrationBridge result;
  result.impl_ = std::make_shared<ListenerRegistrationBridge::Impl>(
      const_cast<Query&>(impl_->query_)
          .AddSnapshotListener(std::move(options), std::move(listener)));
  return result;
}

// Filters and cursors are defined further below, after UserDataParser.

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

bool CollectionReferenceBridge::GetParent(
    DocumentReferenceBridge& parent) const noexcept {
  const ResourcePath& path = impl_->query_.query().path();
  if (path.size() <= 1) return false;
  parent.impl_ = std::make_shared<DocumentReferenceBridge::Impl>(
      DocumentReference{path.PopLast(), impl_->query_.firestore()});
  return true;
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

std::string FirestoreBridge::project_id() const noexcept {
  if (!impl_) return "";
  return impl_->firestore_->database_id().project_id();
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
  impl_->firestore_->Terminate(Reporter(context, callback));
}

void FirestoreBridge::ClearPersistence(
    void* context, ErrorCallback callback) const noexcept {
  impl_->firestore_->ClearPersistence(Reporter(context, callback));
}

void FirestoreBridge::WaitForPendingWrites(
    void* context, ErrorCallback callback) const noexcept {
  impl_->firestore_->WaitForPendingWrites(Reporter(context, callback));
}

void FirestoreBridge::EnableNetwork(
    void* context, ErrorCallback callback) const noexcept {
  impl_->firestore_->EnableNetwork(Reporter(context, callback));
}

void FirestoreBridge::DisableNetwork(
    void* context, ErrorCallback callback) const noexcept {
  impl_->firestore_->DisableNetwork(Reporter(context, callback));
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
    const DocumentReferenceBridge& document) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Reference;
  const DocumentReference& ref = document.impl_->ref_;
  v.string_value_ = ref.Path();
  v.project_id_ = ref.firestore()->database_id().project_id();
  v.database_id_ = ref.firestore()->database_id().database_id();
  return v;
}

BridgeFieldValue BridgeFieldValue::FromDocumentPath(
    const std::string& document_path) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Reference;
  v.string_value_ = document_path;
  return v;
}

BridgeFieldValue BridgeFieldValue::Unsupported(
    const std::string& type_name) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::Unsupported;
  v.string_value_ = type_name;
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

BridgeFieldValue BridgeFieldValue::Increment(
    const BridgeFieldValue& operand) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelIncrement;
  v.array_value_ = {operand};
  return v;
}

BridgeFieldValue BridgeFieldValue::Minimum(
    const BridgeFieldValue& operand) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelMinimum;
  v.array_value_ = {operand};
  return v;
}

BridgeFieldValue BridgeFieldValue::Maximum(
    const BridgeFieldValue& operand) noexcept {
  BridgeFieldValue v;
  v.tag_ = Tag::SentinelMaximum;
  v.array_value_ = {operand};
  return v;
}

// ===========================================================================
// UserDataParser
// ===========================================================================
// Converts BridgeFieldValue trees into nanopb protobuf values, handling
// sentinel field values (transforms) via ParseAccumulator/ParseContext. A port
// of upstream's FSTUserDataReader, with the same validation and messages.

class UserDataParser {
 public:
  explicit UserDataParser(DatabaseId database_id)
      : database_id_(std::move(database_id)) {}

  ParsedSetData ParseSetData(const BridgeFieldValueMap& data) const {
    ParseAccumulator accumulator{UserDataSource::Set};
    auto parsed = ParseMap(data, accumulator.RootContext());
    return std::move(accumulator).SetData(ObjectValue{std::move(parsed)});
  }

  ParsedSetData ParseMergeData(const BridgeFieldValueMap& data,
                               const FieldPathVector* field_mask) const {
    ParseAccumulator accumulator{UserDataSource::MergeSet};
    ObjectValue update_object{ParseMap(data, accumulator.RootContext())};

    if (!field_mask) {
      return std::move(accumulator).MergeData(std::move(update_object));
    }
    std::set<FieldPath> validated_paths;
    for (const auto& segments : *field_mask) {
      FieldPath path = MakeFieldPath(segments);
      if (!accumulator.Contains(path)) {
        ThrowInvalidArgument(
            "Field '%s' is specified in your field mask but missing from your "
            "input data.",
            path.CanonicalString());
      }
      validated_paths.insert(std::move(path));
    }
    return std::move(accumulator)
        .MergeData(std::move(update_object),
                   FieldMask{std::move(validated_paths)});
  }

  ParsedSetData ParseSetData(const BridgeFieldValueMap& data,
                             SetOption option,
                             const FieldPathVector& merge_fields) const {
    switch (option) {
      case SetOption::Overwrite:
        return ParseSetData(data);
      case SetOption::Merge:
        return ParseMergeData(data, nullptr);
      case SetOption::MergeFields:
        return ParseMergeData(data, &merge_fields);
    }
    UNREACHABLE();
  }

  ParsedUpdateData ParseUpdateData(const BridgeUpdateData& data) const {
    ParseAccumulator accumulator{UserDataSource::Update};
    ParseContext context = accumulator.RootContext();
    ObjectValue update_data;

    for (const auto& entry : data) {
      FieldPath path = MakeFieldPath(entry.first);
      if (entry.second.tag() == Tag::SentinelDelete) {
        // Add it to the field mask, but don't add anything to update_data.
        context.AddToFieldMask(std::move(path));
      } else {
        auto parsed = ParseData(entry.second, context.ChildContext(path));
        if (parsed) {
          context.AddToFieldMask(path);
          update_data.Set(path, std::move(*parsed));
        }
      }
    }
    return std::move(accumulator).UpdateData(std::move(update_data));
  }

  Message<google_firestore_v1_Value> ParseQueryValue(
      const BridgeFieldValue& value, bool allow_arrays = false) const {
    ParseAccumulator accumulator{allow_arrays ? UserDataSource::ArrayArgument
                                              : UserDataSource::Argument};
    auto parsed = ParseData(value, accumulator.RootContext());
    HARD_ASSERT(parsed, "Parsed data should not be nil.");
    HARD_ASSERT(accumulator.field_transforms().empty(),
                "Field transforms should have been disallowed.");
    return std::move(*parsed);
  }

  static FieldPath MakeFieldPath(const FieldPathSegments& segments) {
    return FieldPath(segments.begin(), segments.end());
  }

 private:
  using Tag = BridgeFieldValue::Tag;

  static bool IsSentinel(const BridgeFieldValue& value) {
    switch (value.tag()) {
      case Tag::SentinelDelete:
      case Tag::SentinelServerTimestamp:
      case Tag::SentinelArrayUnion:
      case Tag::SentinelArrayRemove:
      case Tag::SentinelIncrement:
      case Tag::SentinelMinimum:
      case Tag::SentinelMaximum:
        return true;
      default:
        return false;
    }
  }

  /// The API call that created a sentinel, for error messages.
  static const char* MethodName(const BridgeFieldValue& value) {
    switch (value.tag()) {
      case Tag::SentinelDelete:
        return "FieldValue.delete()";
      case Tag::SentinelServerTimestamp:
        return "FieldValue.serverTimestamp()";
      case Tag::SentinelArrayUnion:
        return "FieldValue.arrayUnion()";
      case Tag::SentinelArrayRemove:
        return "FieldValue.arrayRemove()";
      case Tag::SentinelIncrement:
        return "FieldValue.increment()";
      case Tag::SentinelMinimum:
        return "FieldValue.minimum()";
      case Tag::SentinelMaximum:
        return "FieldValue.maximum()";
      default:
        return "";
    }
  }

  /// Returns the parsed value, or nullopt for a sentinel, which goes into the
  /// context's transforms or field mask instead.
  absl::optional<Message<google_firestore_v1_Value>> ParseData(
      const BridgeFieldValue& value, ParseContext&& context) const {
    if (value.tag() == Tag::Map) {
      return ParseMap(value.map_value_, std::move(context));
    }
    if (IsSentinel(value)) {
      ParseSentinel(value, std::move(context));
      return absl::nullopt;
    }

    if (context.path()) {
      context.AddToFieldMask(*context.path());
    }
    if (value.tag() == Tag::Array) {
      if (context.array_element() &&
          context.data_source() != UserDataSource::ArrayArgument) {
        ThrowInvalidArgument("Nested arrays are not supported");
      }
      return ParseArray(value.array_value_, std::move(context));
    }
    return ParseScalar(value, std::move(context));
  }

  Message<google_firestore_v1_Value> ParseMap(const BridgeFieldValueMap& entries,
                                              ParseContext&& context) const {
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

    pb_size_t count = 0;
    for (const auto& entry : entries) {
      if (!IsSentinel(entry.second)) ++count;
    }
    result->map_value.fields_count = count;
    result->map_value.fields =
        nanopb::MakeArray<google_firestore_v1_MapValue_FieldsEntry>(count);

    pb_size_t index = 0;
    for (const auto& entry : entries) {
      auto parsed = ParseData(entry.second, context.ChildContext(entry.first));
      if (parsed) {
        result->map_value.fields[index].key = nanopb::MakeBytesArray(entry.first);
        result->map_value.fields[index].value = *parsed->release();
        ++index;
      }
    }
    return result;
  }

  Message<google_firestore_v1_Value> ParseArray(
      const BridgeFieldValueVector& elements, ParseContext&& context) const {
    Message<google_firestore_v1_Value> result;
    result->which_value_type = google_firestore_v1_Value_array_value_tag;
    result->array_value.values_count = static_cast<pb_size_t>(elements.size());
    result->array_value.values = nanopb::MakeArray<google_firestore_v1_Value>(
        result->array_value.values_count);

    for (size_t i = 0; i < elements.size(); ++i) {
      auto parsed = ParseData(elements[i], context.ChildContext(i));
      if (!parsed) {
        parsed.emplace(model::DeepClone(model::NullValue()));
      }
      result->array_value.values[i] = *parsed->release();
    }
    return result;
  }

  void ParseSentinel(const BridgeFieldValue& value,
                     ParseContext&& context) const {
    // Sentinels are only supported with writes, and not within arrays.
    if (!context.write()) {
      ThrowInvalidArgument("%s can only be used with updateData() and setData()%s",
                           MethodName(value), context.FieldDescription());
    }
    if (!context.path()) {
      ThrowInvalidArgument("%s is not currently supported inside arrays",
                           MethodName(value));
    }

    switch (value.tag()) {
      case Tag::SentinelDelete:
        if (context.data_source() == UserDataSource::MergeSet) {
          // No transform to add for a delete, but we need to add it to our
          // field mask so it gets deleted.
          context.AddToFieldMask(*context.path());
        } else if (context.data_source() == UserDataSource::Update) {
          HARD_ASSERT(!context.path()->empty(),
                      "FieldValue.delete() at the top level should have "
                      "already been handled.");
          ThrowInvalidArgument(
              "FieldValue.delete() can only appear at the top level of your "
              "update data%s",
              context.FieldDescription());
        } else {
          // We shouldn't encounter delete sentinels for queries or non-merge
          // setData calls.
          ThrowInvalidArgument(
              "FieldValue.delete() can only be used with updateData() and "
              "setData() with merge:true%s",
              context.FieldDescription());
        }
        break;

      case Tag::SentinelServerTimestamp:
        context.AddToFieldTransforms(*context.path(), ServerTimestampTransform());
        break;

      case Tag::SentinelArrayUnion:
        context.AddToFieldTransforms(
            *context.path(),
            ArrayTransform(TransformOperation::Type::ArrayUnion,
                           ParseArrayTransformElements(value.array_value_)));
        break;

      case Tag::SentinelArrayRemove:
        context.AddToFieldTransforms(
            *context.path(),
            ArrayTransform(TransformOperation::Type::ArrayRemove,
                           ParseArrayTransformElements(value.array_value_)));
        break;

      case Tag::SentinelIncrement:
        context.AddToFieldTransforms(
            *context.path(),
            NumericIncrementTransform(ParseQueryValue(value.array_value_[0])));
        break;

      case Tag::SentinelMinimum:
        context.AddToFieldTransforms(
            *context.path(),
            NumericMinimumTransform(ParseQueryValue(value.array_value_[0])));
        break;

      case Tag::SentinelMaximum:
        context.AddToFieldTransforms(
            *context.path(),
            NumericMaximumTransform(ParseQueryValue(value.array_value_[0])));
        break;

      default:
        HARD_FAIL("Unknown FieldValue type: %s", static_cast<int>(value.tag()));
    }
  }

  Message<google_firestore_v1_Value> ParseScalar(const BridgeFieldValue& value,
                                                 ParseContext&& context) const {
    Message<google_firestore_v1_Value> result;
    switch (value.tag()) {
      case Tag::Null:
        return model::DeepClone(model::NullValue());

      case Tag::Boolean:
        result->which_value_type = google_firestore_v1_Value_boolean_value_tag;
        result->boolean_value = value.bool_value_;
        return result;

      case Tag::Integer:
        result->which_value_type = google_firestore_v1_Value_integer_value_tag;
        result->integer_value = value.int64_value_;
        return result;

      case Tag::Double:
        result->which_value_type = google_firestore_v1_Value_double_value_tag;
        result->double_value = value.double_value_;
        return result;

      case Tag::String:
        return model::StringValue(value.string_value_);

      case Tag::Blob:
        result->which_value_type = google_firestore_v1_Value_bytes_value_tag;
        result->bytes_value = nanopb::MakeBytesArray(value.string_value_.data(),
                                                     value.string_value_.size());
        return result;

      case Tag::Timestamp:
        // Firestore stores microseconds; truncate as upstream does.
        result->which_value_type = google_firestore_v1_Value_timestamp_value_tag;
        result->timestamp_value.seconds = value.int64_value_;
        result->timestamp_value.nanos = value.int32_value_ / 1000 * 1000;
        return result;

      case Tag::GeoPoint:
        result->which_value_type = google_firestore_v1_Value_geo_point_value_tag;
        result->geo_point_value.latitude = value.double_value_;
        result->geo_point_value.longitude = value.double2_value_;
        return result;

      case Tag::Reference: {
        if (value.project_id_ != database_id_.project_id() ||
            value.database_id_ != database_id_.database_id()) {
          ThrowInvalidArgument(
              "Document Reference is for database %s/%s but should be for "
              "database %s/%s%s",
              value.project_id_, value.database_id_,
              database_id_.project_id(), database_id_.database_id(),
              context.FieldDescription());
        }
        return model::RefValue(database_id_,
                               DocumentKey::FromPathString(value.string_value_));
      }

      case Tag::Vector:
        return ParseVector(value.vector_value_);

      case Tag::Unsupported:
        ThrowInvalidArgument("Unsupported type: %s%s", value.string_value_,
                             context.FieldDescription());

      default:
        HARD_FAIL("Unexpected value type: %s", static_cast<int>(value.tag()));
    }
  }

  static Message<google_firestore_v1_Value> ParseVector(
      const DoubleVector& doubles) {
    Message<google_firestore_v1_Value> result;
    result->which_value_type = google_firestore_v1_Value_map_value_tag;
    result->map_value = {};
    result->map_value.fields_count = 2;
    result->map_value.fields =
        nanopb::MakeArray<google_firestore_v1_MapValue_FieldsEntry>(2);

    result->map_value.fields[0].key =
        nanopb::CopyBytesArray(model::kTypeValueFieldKey);
    result->map_value.fields[0].value =
        *model::StringValue(std::string("__vector__")).release();

    Message<google_firestore_v1_Value> array;
    array->which_value_type = google_firestore_v1_Value_array_value_tag;
    array->array_value.values_count = static_cast<pb_size_t>(doubles.size());
    array->array_value.values = nanopb::MakeArray<google_firestore_v1_Value>(
        array->array_value.values_count);
    for (size_t i = 0; i < doubles.size(); ++i) {
      array->array_value.values[i].which_value_type =
          google_firestore_v1_Value_double_value_tag;
      array->array_value.values[i].double_value = doubles[i];
    }

    result->map_value.fields[1].key =
        nanopb::CopyBytesArray(model::kVectorValueFieldKey);
    result->map_value.fields[1].value = *array.release();
    return result;
  }

  Message<google_firestore_v1_ArrayValue> ParseArrayTransformElements(
      const BridgeFieldValueVector& elements) const {
    ParseAccumulator accumulator{UserDataSource::Argument};

    Message<google_firestore_v1_ArrayValue> array_value;
    array_value->values_count = static_cast<pb_size_t>(elements.size());
    array_value->values =
        nanopb::MakeArray<google_firestore_v1_Value>(array_value->values_count);

    for (size_t i = 0; i < elements.size(); ++i) {
      ParseContext context = accumulator.RootContext();
      auto parsed = ParseData(elements[i], context.ChildContext(i));
      HARD_ASSERT(parsed && accumulator.field_transforms().empty(),
                  "Failed to properly parse array transform element");
      array_value->values[i] = *parsed->release();
    }
    return array_value;
  }

  DatabaseId database_id_;
};

namespace {

UserDataParser ParserFor(const std::shared_ptr<Firestore>& firestore) {
  return UserDataParser(firestore->database_id());
}

}  // namespace

// ===========================================================================
// DocumentReferenceBridge — Write Operations
// ===========================================================================

void DocumentReferenceBridge::SetData(const BridgeFieldValueMap& data,
                                      SetOption option,
                                      const FieldPathVector& merge_fields,
                                      void* context,
                                      ErrorCallback callback) noexcept {
  auto parsed = ParserFor(impl_->ref_.firestore())
                    .ParseSetData(data, option, merge_fields);
  impl_->ref_.SetData(std::move(parsed), Reporter(context, callback));
}

void DocumentReferenceBridge::UpdateData(const BridgeUpdateData& data,
                                         void* context,
                                         ErrorCallback callback) noexcept {
  auto parsed = ParserFor(impl_->ref_.firestore()).ParseUpdateData(data);
  impl_->ref_.UpdateData(std::move(parsed), Reporter(context, callback));
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
      return BridgeFieldValue::FromDocumentPath(key.ToString());
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

BridgeFieldValueMap DocumentSnapshotBridge::data(
    int32_t server_timestamp_behavior) const noexcept {
  if (!impl_) return BridgeFieldValueMap{};
  const auto& doc = impl_->snapshot_.internal_document();
  if (!doc.has_value()) return BridgeFieldValueMap{};

  const auto& value = doc->get().value();
  if (value.which_value_type != google_firestore_v1_Value_map_value_tag) {
    return BridgeFieldValueMap{};
  }
  return ConvertProtoMap(value.map_value, impl_->snapshot_.firestore(),
                         server_timestamp_behavior);
}

bool DocumentSnapshotBridge::GetField(const FieldPathSegments& field_path,
                                      int32_t server_timestamp_behavior,
                                      BridgeFieldValue& value) const noexcept {
  if (!impl_) return false;
  auto field = impl_->snapshot_.GetValue(UserDataParser::MakeFieldPath(field_path));
  if (!field.has_value()) return false;
  value = ConvertProtoValue(*field, impl_->snapshot_.firestore(),
                            server_timestamp_behavior);
  return true;
}

// ===========================================================================
// FilterBridge
// ===========================================================================

struct FilterBridge::Impl {
  // A field filter, unless `filters` is set.
  FieldPathSegments field_path;
  FilterOperator op = FilterOperator::Equal;
  BridgeFieldValue value;

  bool is_composite = false;
  core::CompositeFilter::Operator composite_op =
      core::CompositeFilter::Operator::And;
  std::vector<FilterBridge> filters;
};

FilterBridge::FilterBridge() noexcept = default;
FilterBridge::~FilterBridge() noexcept = default;
FilterBridge::FilterBridge(const FilterBridge&) noexcept = default;
FilterBridge& FilterBridge::operator=(const FilterBridge&) noexcept = default;
FilterBridge::FilterBridge(FilterBridge&&) noexcept = default;
FilterBridge& FilterBridge::operator=(FilterBridge&&) noexcept = default;

FilterBridge FilterBridge::Field(const FieldPathSegments& field_path,
                                 FilterOperator op,
                                 const BridgeFieldValue& value) noexcept {
  auto impl = std::make_shared<Impl>();
  impl->field_path = field_path;
  impl->op = op;
  impl->value = value;
  FilterBridge result;
  result.impl_ = std::move(impl);
  return result;
}

FilterBridge FilterBridge::And(const std::vector<FilterBridge>& filters) noexcept {
  auto impl = std::make_shared<Impl>();
  impl->is_composite = true;
  impl->composite_op = core::CompositeFilter::Operator::And;
  impl->filters = filters;
  FilterBridge result;
  result.impl_ = std::move(impl);
  return result;
}

FilterBridge FilterBridge::Or(const std::vector<FilterBridge>& filters) noexcept {
  auto impl = std::make_shared<Impl>();
  impl->is_composite = true;
  impl->composite_op = core::CompositeFilter::Operator::Or;
  impl->filters = filters;
  FilterBridge result;
  result.impl_ = std::move(impl);
  return result;
}

// ===========================================================================
// QueryBridge — filters, ordering and cursors
// ===========================================================================

namespace {

FieldFilter::Operator CoreOperator(FilterOperator op) {
  switch (op) {
    case FilterOperator::LessThan:
      return FieldFilter::Operator::LessThan;
    case FilterOperator::LessThanOrEqual:
      return FieldFilter::Operator::LessThanOrEqual;
    case FilterOperator::Equal:
      return FieldFilter::Operator::Equal;
    case FilterOperator::NotEqual:
      return FieldFilter::Operator::NotEqual;
    case FilterOperator::GreaterThanOrEqual:
      return FieldFilter::Operator::GreaterThanOrEqual;
    case FilterOperator::GreaterThan:
      return FieldFilter::Operator::GreaterThan;
    case FilterOperator::ArrayContains:
      return FieldFilter::Operator::ArrayContains;
    case FilterOperator::In:
      return FieldFilter::Operator::In;
    case FilterOperator::ArrayContainsAny:
      return FieldFilter::Operator::ArrayContainsAny;
    case FilterOperator::NotIn:
      return FieldFilter::Operator::NotIn;
  }
  UNREACHABLE();
}

/// Mirrors FIRQuery's boundFromSnapshot:isInclusive:.
Bound BoundFromSnapshot(const api::DocumentSnapshot& snapshot,
                        bool is_inclusive,
                        const core::Query& query) {
  if (!snapshot.exists()) {
    ThrowInvalidArgument(
        "Invalid query. You are trying to start or end a query using a "
        "document that doesn't exist.");
  }

  const auto& document = *snapshot.internal_document();
  const auto& database_id = snapshot.firestore()->database_id();
  const auto& order_bys = query.normalized_order_bys();

  nanopb::SharedMessage<google_firestore_v1_ArrayValue> components{{}};
  components->values_count = static_cast<pb_size_t>(order_bys.size());
  components->values = nanopb::MakeArray<google_firestore_v1_Value>(
      components->values_count);

  for (size_t i = 0; i < order_bys.size(); ++i) {
    const auto& field = order_bys[i].field();
    if (field == FieldPath::KeyFieldPath()) {
      components->values[i] =
          *model::RefValue(database_id, document->key()).release();
      continue;
    }
    auto value = document->field(field);
    if (!value) {
      ThrowInvalidArgument(
          "Invalid query. You are trying to start or end a query using a "
          "document for which the field '%s' (used as the order by) does not "
          "exist.",
          field.CanonicalString());
    }
    if (model::IsServerTimestamp(*value)) {
      ThrowInvalidArgument(
          "Invalid query. You are trying to start or end a query using a "
          "document for which the field '%s' is an uncommitted server "
          "timestamp. (Since the value of this field is unknown, you cannot "
          "start/end a query with it.)",
          field.CanonicalString());
    }
    components->values[i] = *model::DeepClone(*value).release();
  }
  return Bound::FromValue(std::move(components), is_inclusive);
}

/// Mirrors FIRQuery's boundFromFieldValues:isInclusive:.
Bound BoundFromFieldValues(const api::Query& api_query,
                           const BridgeFieldValueVector& values,
                           bool is_inclusive) {
  const core::Query& query = api_query.query();
  // Use explicit order bys because it has to match the query the user made.
  const auto& explicit_order_bys = query.explicit_order_bys();
  if (values.size() > explicit_order_bys.size()) {
    ThrowInvalidArgument(
        "Invalid query. You are trying to start or end a query using more "
        "values than were specified in the order by.");
  }

  const auto& database_id = api_query.firestore()->database_id();
  UserDataParser parser(database_id);

  nanopb::SharedMessage<google_firestore_v1_ArrayValue> components{{}};
  components->values_count = static_cast<pb_size_t>(values.size());
  components->values = nanopb::MakeArray<google_firestore_v1_Value>(
      components->values_count);

  for (size_t i = 0; i < values.size(); ++i) {
    auto value = parser.ParseQueryValue(values[i]);
    if (explicit_order_bys[i].field().IsKeyFieldPath()) {
      if (value->which_value_type != google_firestore_v1_Value_string_value_tag) {
        ThrowInvalidArgument(
            "Invalid query. Expected a string for the document ID.");
      }
      std::string document_id = nanopb::MakeString(value->string_value);
      if (!query.IsCollectionGroupQuery() &&
          document_id.find('/') != std::string::npos) {
        ThrowInvalidArgument(
            "Invalid query. When querying a collection and ordering by "
            "document ID, you must pass a plain document ID, but '%s' "
            "contains a slash.",
            document_id);
      }
      ResourcePath path = query.path().Append(ResourcePath::FromString(document_id));
      if (!DocumentKey::IsDocumentKey(path)) {
        ThrowInvalidArgument(
            "Invalid query. When querying a collection group and ordering by "
            "document ID, you must pass a value that results in a valid "
            "document path, but '%s' is not because it contains an odd number "
            "of segments.",
            path.CanonicalString());
      }
      value = model::RefValue(database_id, DocumentKey{path});
    }
    components->values[i] = *value.release();
  }
  return Bound::FromValue(std::move(components), is_inclusive);
}

}  // namespace

QueryBridge QueryBridge::Where(const FilterBridge& filter) const noexcept {
  const api::Query& query = impl_->query_;

  // Mirrors FIRQuery's parseFilter:. An empty composite filter parses to an
  // empty filter, and a composite of one filter to that filter.
  std::function<core::Filter(const FilterBridge::Impl&)> parse =
      [&](const FilterBridge::Impl& filter) -> core::Filter {
    if (filter.is_composite) {
      std::vector<core::Filter> filters;
      for (const auto& child : filter.filters) {
        core::Filter parsed = parse(*child.impl_);
        if (!parsed.IsEmpty()) {
          filters.push_back(std::move(parsed));
        }
      }
      if (filters.size() == 1) {
        return filters[0];
      }
      return core::CompositeFilter::Create(std::move(filters),
                                           filter.composite_op);
    }

    FieldFilter::Operator op = CoreOperator(filter.op);
    bool allow_arrays = op == FieldFilter::Operator::In ||
                        op == FieldFilter::Operator::NotIn ||
                        op == FieldFilter::Operator::ArrayContainsAny;
    auto value =
        ParserFor(query.firestore()).ParseQueryValue(filter.value, allow_arrays);
    return query.ParseFieldFilter(
        UserDataParser::MakeFieldPath(filter.field_path), op,
        nanopb::SharedMessage<google_firestore_v1_Value>(std::move(value)),
        [] { return std::string("a value"); });
  };

  core::Filter parsed = parse(*filter.impl_);
  if (parsed.IsEmpty()) {
    // An empty composite filter adds nothing.
    return *this;
  }
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(query.AddNewFilter(std::move(parsed)));
  return result;
}

QueryBridge QueryBridge::StartAt(const BridgeFieldValueVector& values,
                                 bool inclusive) const noexcept {
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.StartAt(
      BoundFromFieldValues(impl_->query_, values, inclusive)));
  return result;
}

QueryBridge QueryBridge::EndAt(const BridgeFieldValueVector& values,
                               bool inclusive) const noexcept {
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.EndAt(
      BoundFromFieldValues(impl_->query_, values, inclusive)));
  return result;
}

QueryBridge QueryBridge::StartAtDocument(const DocumentSnapshotBridge& snapshot,
                                         bool inclusive) const noexcept {
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.StartAt(BoundFromSnapshot(
      snapshot.impl_->snapshot_, inclusive, impl_->query_.query())));
  return result;
}

QueryBridge QueryBridge::EndAtDocument(const DocumentSnapshotBridge& snapshot,
                                       bool inclusive) const noexcept {
  QueryBridge result;
  result.impl_ = std::make_shared<Impl>(impl_->query_.EndAt(BoundFromSnapshot(
      snapshot.impl_->snapshot_, inclusive, impl_->query_.query())));
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

void WriteBatchBridge::SetData(const DocumentReferenceBridge& doc,
                               const BridgeFieldValueMap& data,
                               SetOption option,
                               const FieldPathVector& merge_fields) noexcept {
  auto parsed = ParserFor(impl_->batch_.firestore())
                    .ParseSetData(data, option, merge_fields);
  impl_->batch_.SetData(doc.impl_->ref_, std::move(parsed));
}

void WriteBatchBridge::UpdateData(const DocumentReferenceBridge& doc,
                                  const BridgeUpdateData& data) noexcept {
  auto parsed = ParserFor(impl_->batch_.firestore()).ParseUpdateData(data);
  impl_->batch_.UpdateData(doc.impl_->ref_, std::move(parsed));
}

void WriteBatchBridge::DeleteData(
    const DocumentReferenceBridge& doc) noexcept {
  impl_->batch_.DeleteData(doc.impl_->ref_);
}

void WriteBatchBridge::Commit(void* context, ErrorCallback callback) noexcept {
  impl_->batch_.Commit(Reporter(context, callback));
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
    int32_t& error_code,
    std::string& error_message) const noexcept {
  // Block until the async Lookup completes, as FIRTransaction does upstream.
  std::promise<void> lookup_done;

  DocumentSnapshotBridge result;
  Status status;

  auto key = doc.impl_->ref_.key();
  api::SnapshotMetadata meta(/*has_pending_writes=*/false, /*from_cache=*/false);
  impl_->txn_->Lookup(
      {key},
      [&result, &status, &lookup_done, this, key, meta](
          const StatusOr<std::vector<model::Document>>& maybe_docs) {
        if (!maybe_docs.ok()) {
          status = maybe_docs.status();
        } else {
          const auto& docs = maybe_docs.ValueOrDie();
          HARD_ASSERT(docs.size() == 1,
                      "Mismatch in docs returned from document lookup.");
          const auto& internal_doc = docs.front();
          DocumentSnapshot snapshot =
              internal_doc->is_found_document()
                  ? DocumentSnapshot::FromDocument(impl_->firestore_,
                                                   internal_doc, meta)
                  : DocumentSnapshot::FromNoDocument(impl_->firestore_, key,
                                                     meta);
          result.impl_ =
              std::make_shared<DocumentSnapshotBridge::Impl>(std::move(snapshot));
        }
        lookup_done.set_value();
      });

  lookup_done.get_future().wait();
  error_code = ErrorCode(status);
  error_message = status.ok() ? std::string() : status.error_message();
  return result;
}

void TransactionBridge::SetData(const DocumentReferenceBridge& doc,
                                const BridgeFieldValueMap& data,
                                SetOption option,
                                const FieldPathVector& merge_fields) noexcept {
  auto parsed =
      ParserFor(impl_->firestore_).ParseSetData(data, option, merge_fields);
  impl_->txn_->Set(doc.impl_->ref_.key(), std::move(parsed));
}

void TransactionBridge::UpdateData(const DocumentReferenceBridge& doc,
                                   const BridgeUpdateData& data) noexcept {
  auto parsed = ParserFor(impl_->firestore_).ParseUpdateData(data);
  impl_->txn_->Update(doc.impl_->ref_.key(), std::move(parsed));
}

void TransactionBridge::DeleteData(
    const DocumentReferenceBridge& doc) noexcept {
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
  WriteBatchBridge result;
  result.impl_ = std::make_shared<WriteBatchBridge::Impl>(
      impl_->firestore_->GetBatch());
  return result;
}

void FirestoreBridge::RunTransaction(
    void* context,
    TransactionUpdateCallback update_callback,
    void* result_context,
    ErrorCallback result_callback,
    int32_t max_attempts) const noexcept {
  // Capture the Firestore instance, not `this`: Swift calls this method on a
  // temporary copy of the bridge, which is gone before the transaction runs.
  auto update_fn = [context, update_callback, firestore = impl_->firestore_](
      std::shared_ptr<core::Transaction> txn,
      core::TransactionResultCallback done) {
    // Create a TransactionBridge on the heap for Swift to use.
    auto* bridge = new TransactionBridge();
    bridge->impl_ = std::make_shared<TransactionBridge::Impl>(txn, firestore);

    // What Swift calls when the update block has finished.
    using Completion = std::function<void(int32_t, const char*)>;
    auto completion = std::make_shared<Completion>(
        [txn, done = std::move(done)](int32_t code, const char* message) {
          if (code == 0) {
            done(Status::OK());
          } else {
            // The update block failed. That is final, so don't retry (kAborted
            // alone counts as retryable).
            txn->MarkPermanentlyFailed();
            done(Status(static_cast<Error>(code), message));
          }
        });
    ErrorCallback c_completion = [](void* ctx, int32_t code,
                                    const char* message) {
      (*static_cast<Completion*>(ctx))(code, message);
    };

    // This runs on the Firestore worker queue, but the update block calls
    // TransactionBridge::GetDocument, which blocks until a lookup completes
    // on that same queue. Run the block elsewhere, as FIRFirestore does with
    // a global dispatch queue upstream.
    TransactionUserExecutor().Execute(
        [context, update_callback, bridge, c_completion, completion] {
          update_callback(context, static_cast<void*>(bridge), c_completion,
                          static_cast<void*>(completion.get()));
        });
  };

  impl_->firestore_->RunTransaction(std::move(update_fn),
                                    Reporter(result_context, result_callback),
                                    max_attempts);
}

ListenerRegistrationBridge FirestoreBridge::AddSnapshotsInSyncListener(
    void* context,
    ContextReleaseCallback release_context,
    ErrorCallback callback) const noexcept {
  auto listener = EventListener<util::Empty>::Create(
      [owned = OwnContext(context, release_context),
       callback](StatusOr<util::Empty>) { callback(owned.get(), 0, ""); });
  ListenerRegistrationBridge result;
  result.impl_ = std::make_shared<ListenerRegistrationBridge::Impl>(
      impl_->firestore_->AddSnapshotsInSyncListener(std::move(listener)));
  return result;
}

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

