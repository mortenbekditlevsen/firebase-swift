/*
 * Copyright 2020 Google LLC
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

#include "Firestore/core/src/remote/firebase_metadata_provider_apple.h"

#include <string>
#include <utility>

namespace firebase {
namespace firestore {
namespace remote {

FirebaseMetadataProviderApple::FirebaseMetadataProviderApple(
    StringFn user_agent_fn,
    HeartbeatCodeFn heartbeat_fn,
    std::string gmp_app_id)
    : user_agent_fn_(std::move(user_agent_fn)),
      heartbeat_fn_(std::move(heartbeat_fn)),
      gmp_app_id_(std::move(gmp_app_id)) {
}

void FirebaseMetadataProviderApple::UpdateMetadata(
    grpc::ClientContext& context) {
  int heartbeat = heartbeat_fn_();
  if (heartbeat != 0) {
    context.AddMetadata(kXFirebaseClientLogTypeHeader,
                        std::to_string(heartbeat));
  }

  context.AddMetadata(kXFirebaseClientHeader, user_agent_fn_());

  if (!gmp_app_id_.empty()) {
    context.AddMetadata(kXFirebaseGmpIdHeader, gmp_app_id_);
  }
}

}  // namespace remote
}  // namespace firestore
}  // namespace firebase
