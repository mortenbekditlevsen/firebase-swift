/*
 * Copyright 2021 Google LLC
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

#include "Firestore/core/src/credentials/firebase_app_check_credentials_provider_apple.h"

#include <string>

namespace firebase {
namespace firestore {
namespace credentials {

void FirebaseAppCheckCredentialsProvider::GetToken(
    TokenListener<std::string> completion) {
  // AppCheck is not yet implemented; return an empty token.
  completion(std::string{""});
}

void FirebaseAppCheckCredentialsProvider::SetCredentialChangeListener(
    CredentialChangeListener<std::string> change_listener) {
  if (change_listener) {
    // Fire initial event with an empty token.
    change_listener(std::string{""});
  }
}

}  // namespace credentials
}  // namespace firestore
}  // namespace firebase
