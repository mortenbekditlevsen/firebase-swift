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

#ifndef FIRESTORE_CORE_SRC_API_FIRESTORE_BRIDGE_INTERNAL_H_
#define FIRESTORE_CORE_SRC_API_FIRESTORE_BRIDGE_INTERNAL_H_

// What the parts of the Swift bridge outside firestore_bridge.cc (the
// pipeline bridge) need from it. Not visible to Swift.

#include <memory>

#include "Firestore/include/FirestoreBridge.h"
#include "Firestore/Protos/nanopb/google/firestore/v1/document.nanopb.h"
#include "Firestore/core/src/nanopb/message.h"

namespace firebase {
namespace firestore {
namespace api {
class DocumentReference;
class Firestore;
class ListenerRegistration;
class Query;
}  // namespace api

namespace util {
class Status;
}  // namespace util

namespace swift_bridge {

/// Reaches the API objects behind the bridge types.
struct BridgeAccess {
  static const std::shared_ptr<api::Firestore>& GetFirestore(
      const FirestoreBridge& firestore);
  static const api::Query& GetQuery(const QueryBridge& query);
  static const api::DocumentReference& GetDocumentReference(
      const DocumentReferenceBridge& document);
  static DocumentReferenceBridge MakeDocumentReference(
      api::DocumentReference document);
  static ListenerRegistrationBridge MakeListenerRegistration(
      std::unique_ptr<api::ListenerRegistration> registration);
};

/// Parses `value` as a query value (upstream's `parsedQueryValue:`); invalid
/// values abort.
nanopb::Message<google_firestore_v1_Value> ParseQueryValue(
    const std::shared_ptr<api::Firestore>& firestore,
    const BridgeFieldValue& value);

/// Converts a value read from the server or cache for Swift.
/// `server_timestamp_behavior` as in `DocumentSnapshotBridge::data`.
BridgeFieldValue ConvertValueForSwift(
    const google_firestore_v1_Value& value,
    const std::shared_ptr<api::Firestore>& firestore,
    int32_t server_timestamp_behavior);

/// The `firebase::firestore::Error` code of `status`.
int32_t StatusErrorCode(const util::Status& status);

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_API_FIRESTORE_BRIDGE_INTERNAL_H_
