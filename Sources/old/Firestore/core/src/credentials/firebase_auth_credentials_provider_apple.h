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

#ifndef FIRESTORE_CORE_SRC_CREDENTIALS_FIREBASE_AUTH_CREDENTIALS_PROVIDER_APPLE_H_
#define FIRESTORE_CORE_SRC_CREDENTIALS_FIREBASE_AUTH_CREDENTIALS_PROVIDER_APPLE_H_

#include <functional>
#include <memory>
#include <mutex>
#include <string>

#include "Firestore/core/src/credentials/credentials_provider.h"
#include "Firestore/core/src/credentials/user.h"

namespace firebase {
namespace firestore {
namespace credentials {

/**
 * `FirebaseAuthCredentialsProvider` uses callbacks to obtain auth tokens,
 * decoupled from any platform-specific auth implementation.
 *
 * The caller provides:
 * - A function to get the current user ID.
 * - A function to get a token (with a force-refresh flag and a callback to
 *   deliver the result).
 * - A function to register/unregister an auth state change listener.
 *
 * NOTE: To simplify the implementation, it requires that you call
 * `SetCredentialChangeListener()` with a non-nullptr value no more than once
 * and don't call `GetToken()` after setting it to `nullptr`.
 *
 * This class must be implemented in a thread-safe manner since it is accessed
 * from the thread backing our internal worker queue and the callbacks from
 * auth will be executed on an arbitrary different thread.
 */
class FirebaseAuthCredentialsProvider
    : public CredentialsProvider<AuthToken, User>,
      public std::enable_shared_from_this<FirebaseAuthCredentialsProvider> {
 public:
  /**
   * Callback type for delivering a token result. The first parameter is the
   * token string (empty if unauthenticated), the second is an error message
   * (empty on success).
   */
  using TokenResultCallback =
      std::function<void(const std::string& token,
                         const std::string& error_message)>;

  /**
   * Function type for requesting a token. Parameters:
   * - force_refresh: whether to force a token refresh.
   * - callback: the TokenResultCallback to invoke with the result.
   */
  using GetTokenFn =
      std::function<void(bool force_refresh, TokenResultCallback callback)>;

  /**
   * Function type for getting the current user ID.
   * Returns an empty string if unauthenticated.
   */
  using GetUserIDFn = std::function<std::string()>;

  /**
   * Callback invoked when the auth state changes.
   * The parameter is the new user ID (empty if signed out).
   */
  using AuthStateChangeFn = std::function<void(const std::string& uid)>;

  /**
   * Function type for registering an auth state change listener.
   * The function receives a callback to be invoked on auth state changes,
   * and returns a function that, when called, unregisters the listener.
   */
  using ListenForAuthChangeFn =
      std::function<std::function<void()>(AuthStateChangeFn)>;

  /**
   * Initializes a new FirebaseAuthCredentialsProvider.
   *
   * @param get_user_id_fn Function to get the current user ID.
   * @param get_token_fn Function to request an auth token.
   * @param listen_fn Function to register an auth state change listener.
   */
  FirebaseAuthCredentialsProvider(GetUserIDFn get_user_id_fn,
                                  GetTokenFn get_token_fn,
                                  ListenForAuthChangeFn listen_fn);

  ~FirebaseAuthCredentialsProvider() override;

  void GetToken(TokenListener<AuthToken> completion) override;

  void SetCredentialChangeListener(
      CredentialChangeListener<User> change_listener) override;

 private:
  struct Contents {
    Contents(User&& user) : current_user(std::move(user)) {}

    /** The current user as reported via the auth state change listener. */
    User current_user;

    /**
     * Counter used to detect if the token changed while a GetToken() request
     * was outstanding.
     */
    int token_counter = 0;

    std::mutex mutex;
  };

  GetTokenFn get_token_fn_;
  ListenForAuthChangeFn listen_fn_;

  /** Function to call to unregister the auth state listener, if registered. */
  std::function<void()> unlisten_fn_;

  std::shared_ptr<Contents> contents_;
};

}  // namespace credentials
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_CREDENTIALS_FIREBASE_AUTH_CREDENTIALS_PROVIDER_APPLE_H_
