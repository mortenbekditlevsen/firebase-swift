/*
 * Copyright 2018 Google
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

#include "Firestore/core/src/credentials/firebase_auth_credentials_provider_apple.h"

#include <utility>

#include "Firestore/core/src/util/hard_assert.h"
#include "Firestore/core/src/util/log.h"

namespace firebase {
namespace firestore {
namespace credentials {

FirebaseAuthCredentialsProvider::FirebaseAuthCredentialsProvider(
    GetUserIDFn get_user_id_fn,
    GetTokenFn get_token_fn,
    ListenForAuthChangeFn listen_fn)
    : get_token_fn_(std::move(get_token_fn)),
      listen_fn_(std::move(listen_fn)) {
  std::string uid = get_user_id_fn();
  User initial_user = uid.empty() ? User::Unauthenticated() : User(uid);
  contents_ = std::make_shared<Contents>(std::move(initial_user));

  std::weak_ptr<Contents> weak_contents = contents_;
  unlisten_fn_ = listen_fn_([weak_contents, this](const std::string& uid) {
    std::shared_ptr<Contents> contents = weak_contents.lock();
    if (!contents) {
      return;
    }

    std::unique_lock<std::mutex> lock(contents->mutex);
    contents->current_user =
        uid.empty() ? User::Unauthenticated() : User(uid);
    contents->token_counter++;
    CredentialChangeListener<User> listener = change_listener_;
    if (listener) {
      listener(contents->current_user);
    }
  });
}

FirebaseAuthCredentialsProvider::~FirebaseAuthCredentialsProvider() {
  if (unlisten_fn_) {
    unlisten_fn_();
  }
}

void FirebaseAuthCredentialsProvider::GetToken(
    TokenListener<AuthToken> completion) {
  HARD_ASSERT(unlisten_fn_,
              "GetToken cannot be called after listener removed.");

  // Take note of the current value of the token_counter so that this method can
  // fail if there is a token change while the request is outstanding.
  int initial_token_counter = contents_->token_counter;

  // Capture self via a shared_ptr to ensure that the credentials provider
  // is not deallocated while the getToken request is outstanding.
  std::shared_ptr<FirebaseAuthCredentialsProvider> self = shared_from_this();

  get_token_fn_(
      force_refresh_,
      [self, completion, initial_token_counter](
          const std::string& token, const std::string& error_message) {
        std::unique_lock<std::mutex> lock(self->contents_->mutex);
        if (initial_token_counter != self->contents_->token_counter) {
          // Cancel the request since the user changed while the request was
          // outstanding so the response is likely for a previous user (which
          // user, we can't be sure).
          LOG_DEBUG("GetToken aborted due to token change.");
          return self->GetToken(completion);
        } else {
          if (error_message.empty()) {
            if (!token.empty()) {
              completion(
                  AuthToken{token, self->contents_->current_user});
            } else {
              completion(AuthToken::Unauthenticated());
            }
          } else {
            completion(util::Status(Error::kErrorUnknown, error_message));
          }
        }
      });

  force_refresh_ = false;
}

void FirebaseAuthCredentialsProvider::SetCredentialChangeListener(
    CredentialChangeListener<User> change_listener) {
  std::unique_lock<std::mutex> lock(contents_->mutex);
  if (change_listener) {
    HARD_ASSERT(!change_listener_, "set change_listener twice!");
    // Fire initial event.
    change_listener(contents_->current_user);
  } else {
    HARD_ASSERT(unlisten_fn_, "removed change_listener twice!");
    HARD_ASSERT(change_listener_, "change_listener removed without being set!");
    unlisten_fn_();
    unlisten_fn_ = nullptr;
  }
  change_listener_ = change_listener;
}

}  // namespace credentials
}  // namespace firestore
}  // namespace firebase
