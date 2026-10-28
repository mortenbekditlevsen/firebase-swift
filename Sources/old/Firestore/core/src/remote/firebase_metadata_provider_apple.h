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

#ifndef FIRESTORE_CORE_SRC_REMOTE_FIREBASE_METADATA_PROVIDER_APPLE_H_
#define FIRESTORE_CORE_SRC_REMOTE_FIREBASE_METADATA_PROVIDER_APPLE_H_

#include <functional>
#include <string>

#include "Firestore/core/src/remote/firebase_metadata_provider.h"

namespace firebase {
namespace firestore {
namespace remote {

/**
 * A FirebaseMetadataProvider that obtains metadata via callbacks, allowing
 * the provider to be constructed from Swift (or any other language) without
 * depending on Objective-C types.
 */
class FirebaseMetadataProviderApple : public FirebaseMetadataProvider {
 public:
  using HeartbeatCodeFn = std::function<int()>;
  using StringFn = std::function<std::string()>;

  /**
   * Constructs a metadata provider with the given callbacks.
   *
   * @param user_agent_fn A function returning the Firebase user agent string.
   * @param heartbeat_fn A function returning the heartbeat code for today
   *        (0 = none).
   * @param gmp_app_id The Google app ID (GMP app ID).
   */
  FirebaseMetadataProviderApple(StringFn user_agent_fn,
                                HeartbeatCodeFn heartbeat_fn,
                                std::string gmp_app_id);

  void UpdateMetadata(grpc::ClientContext& context) override;

 private:
  StringFn user_agent_fn_;
  HeartbeatCodeFn heartbeat_fn_;
  std::string gmp_app_id_;
};

}  // namespace remote
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_REMOTE_FIREBASE_METADATA_PROVIDER_APPLE_H_
