// Copyright 2023 Google LLC
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

import Foundation
import Synchronization
@_exported import FirebaseCore

////import FirebaseCore
////import FirebaseCoreExtension
//import FirebaseAppCheckInterop
//import FirebaseAuthInterop
//#if COCOAPODS
//  @_implementationOnly import GoogleUtilities
//#else
//  @_implementationOnly import GoogleUtilities_AppDelegateSwizzler
//  @_implementationOnly import GoogleUtilities_Environment
//#endif
//
#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
  import UIKit
#endif

// TODO: What should this be?
// extension NSNotification.Name {
//    /**
//        @brief The name of the `NSNotificationCenter` notification which is posted when the auth state
//            changes (for example, a new token has been produced, a user signs in or signs out). The
//            object parameter of the notification is the sender `Auth` instance.
//     */
//    public static let AuthStateDidChange: NSNotification.Name
// }

//#if os(iOS)
//  @available(iOS 13.0, *)
//  extension Auth: UISceneDelegate {}
//
//  @available(iOS 13, *)
//  extension Auth: UIApplicationDelegate {
//    public func application(_ application: UIApplication,
//                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
//      setAPNSToken(deviceToken, type: .unknown)
//    }
//
//    public func application(_ application: UIApplication,
//                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
//      kAuthGlobalWorkQueue.sync {
//        self.tokenManager.cancel(withError: error)
//      }
//    }
//
//    public func application(_ application: UIApplication,
//                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
//                            fetchCompletionHandler completionHandler:
//                            @escaping (UIBackgroundFetchResult) -> Void) {
//      _ = canHandleNotification(userInfo)
//      completionHandler(UIBackgroundFetchResult.noData)
//    }
//
//    public func application(_ application: UIApplication,
//                            open url: URL,
//                            options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
//      return canHandle(url)
//    }
//  }
//#endif


@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
extension Auth: AuthInterop {

    public func getToken(forcingRefresh forceRefresh: Bool) async throws -> String? {
        // Enable token auto-refresh if not already enabled.
        let user: User? = _state.withLock { state in
            if !state.autoRefreshTokens {
                AuthLog.logInfo(code: "I-AUT000002", message: "Token auto-refresh enabled.")
                state.autoRefreshTokens = true
                _scheduleAutoTokenRefresh(state: &state)

#if os(iOS) || os(tvOS) // TODO: Is a similar mechanism needed on macOS?
                // TODO: re-port the UIApplication observers; the previous WIP referenced
                // an undefined `strongSelf` and never compiled. Tracking issue: phase 6.
#endif
            }
            return state.currentUser
        }
        // Call back with 'nil' if there is no current user.
        guard let user else { return nil }
        // Call back with current user token.
        return try await user.internalGetToken(forceRefresh: forceRefresh)
    }

  public func getUserID() -> String? {
    return _state.withLock { $0.currentUser?.uid }
  }
}

/** @class Auth
    @brief Manages authentication for Firebase apps.

    Thread-safe. All mutable state is protected by an internal `Mutex`. Callbacks
    delivered to listeners are invoked outside the lock and have no actor isolation;
    callers that need to update UI should hop to `@MainActor` themselves.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 open class Auth: @unchecked Sendable {
  /** @fn auth
   @brief Gets the auth object for the default Firebase app.
   @remarks The default Firebase app must have already been configured or an exception will be
   raised.
   */
  public class func auth() -> Auth {
    guard let defaultApp = FirebaseApp.defaultApp else {
      fatalError("The default FirebaseApp instance must be configured before the default Auth " +
        "instance can be initialized. One way to ensure this is to call " +
        "`FirebaseApp.configure()` in the App Delegate's " +
        "`application(_:didFinishLaunchingWithOptions:)` (or the `@main` struct's " +
        "initializer in SwiftUI).")
    }
    return auth(app: defaultApp)
  }

  /** @fn authWithApp:
   @brief Gets the auth object for a `FirebaseApp`.

   @param app The app for which to retrieve the associated `Auth` instance.
   @return The `Auth` instance associated with the given app.
   */
  public class func auth(app: FirebaseApp) -> Auth {
      // XXX TODO
//      fatalError()
//    let provider = ComponentType<AuthProvider>.instance(for: AuthProvider.self,
//                                                        in: app.container)
//    return provider.auth()
      let auth = Auth(app: app, keychainStorageProvider: AuthUserDefaults.self)
      app.auth = auth

      return auth
  }

  /** @property app
   @brief Gets the `FirebaseApp` object that this auth object is connected to.
   */
  public weak var app: FirebaseApp?

  /** @property currentUser
   @brief Synchronously gets the cached current user, or nil if there is none.
   */
  public var currentUser: User? {
    get { _state.withLock { $0.currentUser } }
    set { _state.withLock { $0.currentUser = newValue } }
  }

  /** @property languageCode
   @brief The current user language code. This property can be set to the app's current language by
   calling `useAppLanguage()`.

   @remarks The string used to set this property must be a language code that follows BCP 47.
   */
  public var languageCode: String? {
    get { _state.withLock { $0.languageCode } }
    set { _state.withLock { $0.languageCode = newValue } }
  }

  /** @property settings
   @brief Contains settings related to the auth object.
   */
  public var settings: AuthSettings? {
    get { _state.withLock { $0.settings } }
    set { _state.withLock { $0.settings = newValue } }
  }

  /** @property userAccessGroup
   @brief The current user access group that the Auth instance is using. Default is nil.
   */
  public var userAccessGroup: String? {
    get { _state.withLock { $0.userAccessGroup } }
    set { _state.withLock { $0.userAccessGroup = newValue } }
  }

  /** @property shareAuthStateAcrossDevices
   @brief Contains shareAuthStateAcrossDevices setting related to the auth object.
   @remarks If userAccessGroup is not set, setting shareAuthStateAcrossDevices will
   have no effect. You should set shareAuthStateAcrossDevices to it's desired
   state and then set the userAccessGroup after.
   */
  public var shareAuthStateAcrossDevices: Bool {
    get { _state.withLock { $0.shareAuthStateAcrossDevices } }
    set { _state.withLock { $0.shareAuthStateAcrossDevices = newValue } }
  }

  /** @property tenantID
   @brief The tenant ID of the auth instance. nil if none is available.
   */
  public var tenantID: String? {
    get { _state.withLock { $0.tenantID } }
    set { _state.withLock { $0.tenantID = newValue } }
  }

  /** @fn updateCurrentUser:completion:
   @brief Sets the `currentUser` on the receiver to the provided user object.
   @param user The user object to be set as the current user of the calling Auth instance.
   */
     public func updateCurrentUser(_ user: User) async throws {
         let myConfiguration = _state.withLock { $0.requestConfiguration }
         if user.requestConfiguration.apiKey != myConfiguration.apiKey {
             // If the API keys are different, then we need to confirm that the user belongs to the same
             // project before proceeding.
             user.requestConfiguration = myConfiguration
             try await user.reload()
         }
         try _state.withLock { state in
             try _updateCurrentUser(user, byForce: true, savingToDisk: true, state: &state)
         }
     }

  /** @fn fetchSignInMethodsForEmail:completion:
   @brief Fetches the list of all sign-in methods previously used for the provided email address.

   @param email The email address for which to obtain a list of sign-in methods.
   @param completion Optionally; a block which is invoked when the list of sign in methods for the
   specified email address is ready or an error was encountered. Invoked asynchronously on the
   main thread in the future.

   @remarks Possible error codes:

   + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.

   @remarks See @c AuthErrors for a list of error codes that are common to all API methods.
   */
  public func fetchSignInMethods(forEmail email: String) async throws -> [String] {
      let request = CreateAuthURIRequest(identifier: email,
                                         continueURI: "http:www.google.com",
                                         requestConfiguration: self.requestConfiguration)
      return try await AuthBackend.post(withRequest: request).signinMethods
  }

  /** @fn fetchSignInMethodsForEmail:completion:
   @brief Fetches the list of all sign-in methods previously used for the provided email address.

   @param email The email address for which to obtain a list of sign-in methods.

   @remarks Possible error codes:

   + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.

   @remarks See @c AuthErrors for a list of error codes that are common to all API methods.
   */

  /** @fn signInWithEmail:password:completion:
      @brief Signs in using an email address and password.

      @param email The user's email address.
      @param password The user's password.
      @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
          canceled. Invoked asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeOperationNotAllowed` - Indicates that email and password
              accounts are not enabled. Enable them in the Auth section of the
              Firebase console.
          + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
          + `AuthErrorCodeWrongPassword` - Indicates the user attempted
              sign in with an incorrect password.
          + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  public func signIn(withEmail email: String,
                     password: String) async throws -> AuthDataResult {
      let result = try await self.internalSignInAndRetrieveData(withEmail: email,
                                                          password: password)
      try _state.withLock { state in try _updateCurrentUser(result.user, byForce: false, savingToDisk: true, state: &state) }
      return result
  }

  /** @fn signInWithEmail:password:callback:
      @brief Signs in using an email address and password.
      @param email The user's email address.
      @param password The user's password.
      @param callback A block which is invoked when the sign in finishes (or is cancelled.) Invoked
          asynchronously on the global auth work queue in the future.
      @remarks This is the internal counterpart of this method, which uses a callback that does not
          update the current user.
   */
  /// Internal counterpart of `signIn(withEmail:password:)` that returns a `User`
  /// without updating `currentUser`. Renamed to avoid overload ambiguity with
  /// the public `signIn(withEmail:password:) -> AuthDataResult`.
  internal func internalSignIn(withEmail email: String,
                               password: String) async throws -> User {
      let request = VerifyPasswordRequest(email: email,
                                          password: password,
                                          requestConfiguration: requestConfiguration)
      guard !request.password.isEmpty else {
          throw AuthErrorUtils.wrongPasswordError(message: nil)
      }
      let response = try await AuthBackend.post(withRequest: request)
      return try await  self.completeSignIn(
        withAccessToken: response.idToken,
        accessTokenExpirationDate: response.approximateExpirationDate,
        refreshToken: response.refreshToken,
        anonymous: false
      )
  }

  /** @fn signInWithEmail:password:completion:
   @brief Signs in using an email address and password.

   @param email The user's email address.
   @param password The user's password.

   @remarks Possible error codes:

   + `AuthErrorCodeOperationNotAllowed` - Indicates that email and password
   accounts are not enabled. Enable them in the Auth section of the
   Firebase console.
   + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
   + `AuthErrorCodeWrongPassword` - Indicates the user attempted
   sign in with an incorrect password.
   + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  

  /** @fn signInWithEmail:link:completion:
   @brief Signs in using an email address and email sign-in link.

   @param email The user's email address.
   @param link The email sign-in link.
   @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
   canceled. Invoked asynchronously on the main thread in the future.

   @remarks Possible error codes:

   + `AuthErrorCodeOperationNotAllowed` - Indicates that email and email sign-in link
   accounts are not enabled. Enable them in the Auth section of the
   Firebase console.
   + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
   + `AuthErrorCodeInvalidEmail` - Indicates the email address is invalid.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  public func signIn(withEmail email: String,
                           link: String) async throws -> AuthDataResult {
      let credential = EmailAuthCredential(withEmail: email, link: link)
      let result = try await self.internalSignInAndRetrieveData(withCredential: credential,
                                         isReauthentication: false)
      try _state.withLock { state in try _updateCurrentUser(result.user, byForce: false, savingToDisk: true, state: &state) }
      return result
  }

  /** @fn signInWithEmail:link:completion:
   @brief Signs in using an email address and email sign-in link.

   @param email The user's email address.
   @param link The email sign-in link.
   @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
   canceled. Invoked asynchronously on the main thread in the future.

   @remarks Possible error codes:

   + `AuthErrorCodeOperationNotAllowed` - Indicates that email and email sign-in link
   accounts are not enabled. Enable them in the Auth section of the
   Firebase console.
   + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
   + `AuthErrorCodeInvalidEmail` - Indicates the email address is invalid.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */

  #if os(iOS)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    /** @fn signInWithProvider:UIDelegate:completion:
     @brief Signs in using the provided auth provider instance.
     This method is available on iOS, macOS Catalyst, and tvOS only.

     @param provider An instance of an auth provider used to initiate the sign-in flow.
     @param uiDelegate Optionally an instance of a class conforming to the AuthUIDelegate
     protocol, this is used for presenting the web context. If nil, a default AuthUIDelegate
     will be used.
     @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
     canceled. Invoked asynchronously on the main thread in the future.

     @remarks Possible error codes:
     <ul>
     <li>@c AuthErrorCodeOperationNotAllowed - Indicates that email and password
     accounts are not enabled. Enable them in the Auth section of the
     Firebase console.
     </li>
     <li>@c AuthErrorCodeUserDisabled - Indicates the user's account is disabled.
     </li>
     <li>@c AuthErrorCodeWebNetworkRequestFailed - Indicates that a network request within a
     SFSafariViewController or WKWebView failed.
     </li>
     <li>@c AuthErrorCodeWebInternalError - Indicates that an internal error occurred within a
     SFSafariViewController or WKWebView.
     </li>
     <li>@c AuthErrorCodeWebSignInUserInteractionFailure - Indicates a general failure during
     a web sign-in flow.
     </li>
     <li>@c AuthErrorCodeWebContextAlreadyPresented - Indicates that an attempt was made to
     present a new web context while one was already being presented.
     </li>
     <li>@c AuthErrorCodeWebContextCancelled - Indicates that the URL presentation was
     cancelled prematurely by the user.
     </li>
     <li>@c AuthErrorCodeAccountExistsWithDifferentCredential - Indicates the email asserted
     by the credential (e.g. the email in a Facebook access token) is already in use by an
     existing account, that cannot be authenticated with this sign-in method. Call
     fetchProvidersForEmail for this user’s email and then prompt them to sign in with any of
     the sign-in providers returned. This error will only be thrown if the "One account per
     email address" setting is enabled in the Firebase console, under Auth settings.
     </li>
     </ul>

     @remarks See @c AuthErrors for a list of error codes that are common to all API methods.
     */
    
    public func signIn(with provider: FederatedAuthProvider,
                       uiDelegate: AuthUIDelegate?,
                       completion: ((AuthDataResult?, Error?) -> Void)?) {
      kAuthGlobalWorkQueue.async {
        let decoratedCallback = self.signInFlowAuthDataResultCallback(byDecorating: completion)
        provider.getCredentialWith(uiDelegate) { rawCredential, error in
          if let error {
            decoratedCallback(nil, error)
            return
          }
          guard let credential = rawCredential else {
            fatalError("Internal Auth Error: Failed to get a AuthCredential")
          }
          self.internalSignInAndRetrieveData(withCredential: credential,
                                             isReauthentication: false,
                                             callback: decoratedCallback)
        }
      }
    }

    /** @fn signInWithProvider:UIDelegate:completion:
     @brief Signs in using the provided auth provider instance.
     This method is available on iOS, macOS Catalyst, and tvOS only.

     @param provider An instance of an auth provider used to initiate the sign-in flow.
     @param uiDelegate Optionally an instance of a class conforming to the AuthUIDelegate
     protocol, this is used for presenting the web context. If nil, a default AuthUIDelegate
     will be used.

     @remarks Possible error codes:
     <ul>
     <li>@c AuthErrorCodeOperationNotAllowed - Indicates that email and password
     accounts are not enabled. Enable them in the Auth section of the
     Firebase console.
     </li>
     <li>@c AuthErrorCodeUserDisabled - Indicates the user's account is disabled.
     </li>
     <li>@c AuthErrorCodeWebNetworkRequestFailed - Indicates that a network request within a
     SFSafariViewController or WKWebView failed.
     </li>
     <li>@c AuthErrorCodeWebInternalError - Indicates that an internal error occurred within a
     SFSafariViewController or WKWebView.
     </li>
     <li>@c AuthErrorCodeWebSignInUserInteractionFailure - Indicates a general failure during
     a web sign-in flow.
     </li>
     <li>@c AuthErrorCodeWebContextAlreadyPresented - Indicates that an attempt was made to
     present a new web context while one was already being presented.
     </li>
     <li>@c AuthErrorCodeWebContextCancelled - Indicates that the URL presentation was
     cancelled prematurely by the user.
     </li>
     <li>@c AuthErrorCodeAccountExistsWithDifferentCredential - Indicates the email asserted
     by the credential (e.g. the email in a Facebook access token) is already in use by an
     existing account, that cannot be authenticated with this sign-in method. Call
     fetchProvidersForEmail for this user’s email and then prompt them to sign in with any of
     the sign-in providers returned. This error will only be thrown if the "One account per
     email address" setting is enabled in the Firebase console, under Auth settings.
     </li>
     </ul>

     @remarks See @c AuthErrors for a list of error codes that are common to all API methods.
     */
    @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    public func signIn(with provider: FederatedAuthProvider,
                       uiDelegate: AuthUIDelegate?) async throws -> AuthDataResult {
      return try await withCheckedThrowingContinuation { continuation in
        self.signIn(with: provider, uiDelegate: uiDelegate) { result, error in
          if let result {
            continuation.resume(returning: result)
          } else {
            continuation.resume(throwing: error!)
          }
        }
      }
    }
  #endif // iOS

  /** @fn signInWithCredential:completion:
   @brief Asynchronously signs in to Firebase with the given 3rd-party credentials (e.g. a Facebook
   login Access Token, a Google ID Token/Access Token pair, etc.) and returns additional
   identity provider data.

   @param credential The credential supplied by the IdP.
   @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
   canceled. Invoked asynchronously on the main thread in the future.

   @remarks Possible error codes:

   + `AuthErrorCodeInvalidCredential` - Indicates the supplied credential is invalid.
   This could happen if it has expired or it is malformed.
   + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts
   with the identity provider represented by the credential are not enabled.
   Enable them in the Auth section of the Firebase console.
   + `AuthErrorCodeAccountExistsWithDifferentCredential` - Indicates the email asserted
   by the credential (e.g. the email in a Facebook access token) is already in use by an
   existing account, that cannot be authenticated with this sign-in method. Call
   fetchProvidersForEmail for this user’s email and then prompt them to sign in with any of
   the sign-in providers returned. This error will only be thrown if the "One account per
   email address" setting is enabled in the Firebase console, under Auth settings.
   + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
   + `AuthErrorCodeWrongPassword` - Indicates the user attempted sign in with an
   incorrect password, if credential is of the type EmailPasswordAuthCredential.
   + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
   + `AuthErrorCodeMissingVerificationID` - Indicates that the phone auth credential was
   created with an empty verification ID.
   + `AuthErrorCodeMissingVerificationCode` - Indicates that the phone auth credential
   was created with an empty verification code.
   + `AuthErrorCodeInvalidVerificationCode` - Indicates that the phone auth credential
   was created with an invalid verification Code.
   + `AuthErrorCodeInvalidVerificationID` - Indicates that the phone auth credential was
   created with an invalid verification ID.
   + `AuthErrorCodeSessionExpired` - Indicates that the SMS code has expired.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods
   */
  
  public func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
      let authResult = try await self.internalSignInAndRetrieveData(withCredential: credential,
                                                                    isReauthentication: false)
      try _state.withLock { state in try _updateCurrentUser(authResult.user, byForce: false, savingToDisk: true, state: &state) }
      return authResult
  }

  /** @fn signInWithCredential:completion:
   @brief Asynchronously signs in to Firebase with the given 3rd-party credentials (e.g. a Facebook
   login Access Token, a Google ID Token/Access Token pair, etc.) and returns additional
   identity provider data.

   @param credential The credential supplied by the IdP.
   @param completion Optionally; a block which is invoked when the sign in flow finishes, or is
   canceled. Invoked asynchronously on the main thread in the future.

   @remarks Possible error codes:

   + `AuthErrorCodeInvalidCredential` - Indicates the supplied credential is invalid.
   This could happen if it has expired or it is malformed.
   + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts
   with the identity provider represented by the credential are not enabled.
   Enable them in the Auth section of the Firebase console.
   + `AuthErrorCodeAccountExistsWithDifferentCredential` - Indicates the email asserted
   by the credential (e.g. the email in a Facebook access token) is already in use by an
   existing account, that cannot be authenticated with this sign-in method. Call
   fetchProvidersForEmail for this user’s email and then prompt them to sign in with any of
   the sign-in providers returned. This error will only be thrown if the "One account per
   email address" setting is enabled in the Firebase console, under Auth settings.
   + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
   + `AuthErrorCodeWrongPassword` - Indicates the user attempted sign in with an
   incorrect password, if credential is of the type EmailPasswordAuthCredential.
   + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
   + `AuthErrorCodeMissingVerificationID` - Indicates that the phone auth credential was
   created with an empty verification ID.
   + `AuthErrorCodeMissingVerificationCode` - Indicates that the phone auth credential
   was created with an empty verification code.
   + `AuthErrorCodeInvalidVerificationCode` - Indicates that the phone auth credential
   was created with an invalid verification Code.
   + `AuthErrorCodeInvalidVerificationID` - Indicates that the phone auth credential was
   created with an invalid verification ID.
   + `AuthErrorCodeSessionExpired` - Indicates that the SMS code has expired.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods
   */
 

  /** @fn signInAnonymouslyWithCompletion:
   @brief Asynchronously creates and becomes an anonymous user.
   @param completion Optionally; a block which is invoked when the sign in finishes, or is
   canceled. Invoked asynchronously on the main thread in the future.

   @remarks If there is already an anonymous user signed in, that user will be returned instead.
   If there is any other existing user signed in, that user will be signed out.

   @remarks Possible error codes:

   + `AuthErrorCodeOperationNotAllowed` - Indicates that anonymous accounts are
   not enabled. Enable them in the Auth section of the Firebase console.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
     public func signInAnonymously() async throws -> AuthDataResult {
         if let currentUser = self.currentUser, currentUser.isAnonymous {
             // Doesn't appear to be necessary when this is the current user, but old code did this
             try _state.withLock { state in try _updateCurrentUser(currentUser, byForce: false, savingToDisk: true, state: &state) }
             return AuthDataResult(withUser: currentUser, additionalUserInfo: nil)
         }
         let request = SignUpNewUserRequest(requestConfiguration: self.requestConfiguration)
         let response = try await AuthBackend.post(withRequest: request)
         let user = try await self.completeSignIn(withAccessToken: response.idToken,
                                                  accessTokenExpirationDate: response.approximateExpirationDate,
                                                  refreshToken: response.refreshToken,
                                                  anonymous: true)
         let additionalUserInfo = AdditionalUserInfo(providerID: nil,
                                                     profile: nil,
                                                     username: nil,
                                                     isNewUser: true)
         let result = AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
         try _state.withLock { state in try _updateCurrentUser(result.user, byForce: false, savingToDisk: true, state: &state) }
         return result
     }

  /** @fn signInAnonymouslyWithCompletion:
   @brief Asynchronously creates and becomes an anonymous user.

   @remarks If there is already an anonymous user signed in, that user will be returned instead.
   If there is any other existing user signed in, that user will be signed out.

   @remarks Possible error codes:

   + `AuthErrorCodeOperationNotAllowed` - Indicates that anonymous accounts are
   not enabled. Enable them in the Auth section of the Firebase console.

   @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
 

  /** @fn signInWithCustomToken:completion:
      @brief Asynchronously signs in to Firebase with the given Auth token.

      @param token A self-signed custom auth token.
      @param completion Optionally; a block which is invoked when the sign in finishes, or is
          canceled. Invoked asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidCustomToken` - Indicates a validation error with
              the custom token.
          + `AuthErrorCodeCustomTokenMismatch` - Indicates the service account and the API key
              belong to different projects.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  public func signIn(withCustomToken token: String) async throws -> AuthDataResult {
      let request = VerifyCustomTokenRequest(token: token,
                                             requestConfiguration: self.requestConfiguration)
      let response = try await AuthBackend.post(withRequest: request)
       let user = try await self.completeSignIn(withAccessToken: response.idToken,
                            accessTokenExpirationDate: response.approximateExpirationDate,
                            refreshToken: response.refreshToken,
                            anonymous: false)
      let additionalUserInfo = AdditionalUserInfo(providerID: nil,
                                                  profile: nil,
                                                  username: nil,
                                                  isNewUser: response.isNewUser)
      let result = AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
      try _state.withLock { state in try _updateCurrentUser(result.user, byForce: false, savingToDisk: true, state: &state) }
      return result
  }

  /** @fn signInWithCustomToken:completion:
      @brief Asynchronously signs in to Firebase with the given Auth token.

      @param token A self-signed custom auth token.
      @param completion Optionally; a block which is invoked when the sign in finishes, or is
          canceled. Invoked asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidCustomToken` - Indicates a validation error with
              the custom token.
          + `AuthErrorCodeCustomTokenMismatch` - Indicates the service account and the API key
              belong to different projects.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
 

  /** @fn createUserWithEmail:password:completion:
      @brief Creates and, on success, signs in a user with the given email address and password.

      @param email The user's email address.
      @param password The user's desired password.
      @param completion Optionally; a block which is invoked when the sign up flow finishes, or is
          canceled. Invoked asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
          + `AuthErrorCodeEmailAlreadyInUse` - Indicates the email used to attempt sign up
              already exists. Call fetchProvidersForEmail to check which sign-in mechanisms the user
              used, and prompt the user to sign in with one of those.
          + `AuthErrorCodeOperationNotAllowed` - Indicates that email and password accounts
              are not enabled. Enable them in the Auth section of the Firebase console.
          + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
              considered too weak. The NSLocalizedFailureReasonErrorKey field in the NSError.userInfo
              dictionary object will contain more detailed explanation that can be shown to the user.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  public func createUser(withEmail email: String,
                               password: String) async throws -> AuthDataResult {
    guard !password.isEmpty else {
        throw AuthErrorUtils.weakPasswordError(serverResponseReason: "Missing password")
    }
    guard !email.isEmpty else {
      throw AuthErrorUtils.missingEmailError(message: nil)
    }
      let request = SignUpNewUserRequest(email: email,
                                         password: password,
                                         displayName: nil,
                                         requestConfiguration: self.requestConfiguration)
      let response = try await AuthBackend.post(withRequest: request)
      let user = try await self.completeSignIn(withAccessToken: response.idToken,
                          accessTokenExpirationDate: response.approximateExpirationDate,
                          refreshToken: response.refreshToken,
                          anonymous: false)
      let additionalUserInfo = AdditionalUserInfo(providerID: EmailAuthProvider.id,
                                                  profile: nil,
                                                  username: nil,
                                                  isNewUser: true)
      let result = AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
      try _state.withLock { state in try _updateCurrentUser(result.user, byForce: false, savingToDisk: true, state: &state) }
      return result
  }

  /** @fn createUserWithEmail:password:completion:
      @brief Creates and, on success, signs in a user with the given email address and password.

      @param email The user's email address.
      @param password The user's desired password.
      @param completion Optionally; a block which is invoked when the sign up flow finishes, or is
          canceled. Invoked asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
          + `AuthErrorCodeEmailAlreadyInUse` - Indicates the email used to attempt sign up
              already exists. Call fetchProvidersForEmail to check which sign-in mechanisms the user
              used, and prompt the user to sign in with one of those.
          + `AuthErrorCodeOperationNotAllowed` - Indicates that email and password accounts
              are not enabled. Enable them in the Auth section of the Firebase console.
          + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
              considered too weak. The NSLocalizedFailureReasonErrorKey field in the NSError.userInfo
              dictionary object will contain more detailed explanation that can be shown to the user.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
 

  /** @fn confirmPasswordResetWithCode:newPassword:completion:
      @brief Resets the password given a code sent to the user outside of the app and a new password
        for the user.

      @param newPassword The new password.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
              considered too weak.
          + `AuthErrorCodeOperationNotAllowed` - Indicates the administrator disabled sign
              in with the specified identity provider.
          + `AuthErrorCodeExpiredActionCode` - Indicates the OOB code is expired.
          + `AuthErrorCodeInvalidActionCode` - Indicates the OOB code is invalid.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */
  public func confirmPasswordReset(withCode code: String, newPassword: String) async throws {
      let request = ResetPasswordRequest(oobCode: code,
                                         newPassword: newPassword,
                                         requestConfiguration: self.requestConfiguration)
      _ = try await AuthBackend.post(withRequest: request)
  }

  /** @fn confirmPasswordResetWithCode:newPassword:completion:
      @brief Resets the password given a code sent to the user outside of the app and a new password
        for the user.

      @param newPassword The new password.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
              considered too weak.
          + `AuthErrorCodeOperationNotAllowed` - Indicates the administrator disabled sign
              in with the specified identity provider.
          + `AuthErrorCodeExpiredActionCode` - Indicates the OOB code is expired.
          + `AuthErrorCodeInvalidActionCode` - Indicates the OOB code is invalid.

      @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
   */

  /** @fn checkActionCode:completion:
      @brief Checks the validity of an out of band code.

      @param code The out of band code to check validity.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */
     public func checkActionCode(_ code: String) async throws -> ActionCodeInfo {
         let request = ResetPasswordRequest(oobCode: code,
                                            newPassword: nil,
                                            requestConfiguration: self.requestConfiguration)
         let response = try await AuthBackend.post(withRequest: request)
         let operation = ActionCodeInfo.actionCodeOperation(forRequestType: response.requestType)
         let actionCodeInfo = ActionCodeInfo(withOperation: operation,
                                             email: response.email,
                                             newEmail: response.verifiedEmail)
         return actionCodeInfo
     }

  /** @fn checkActionCode:completion:
      @brief Checks the validity of an out of band code.

      @param code The out of band code to check validity.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */

  /** @fn verifyPasswordResetCode:completion:
      @brief Checks the validity of a verify password reset code.

      @param code The password reset code to be verified.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */
  public func verifyPasswordResetCode(_ code: String) async throws -> String {
      try await checkActionCode(code).email
  }

  /** @fn verifyPasswordResetCode:completion:
      @brief Checks the validity of a verify password reset code.

      @param code The password reset code to be verified.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */
 

  /** @fn applyActionCode:completion:
      @brief Applies out of band code.

      @param code The out of band code to be applied.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks This method will not work for out of band codes which require an additional parameter,
          such as password reset code.
   */
  public func applyActionCode(_ code: String) async throws {
      var request = SetAccountInfoRequest(requestConfiguration: self.requestConfiguration)
      request.oobCode = code
      _ = try await AuthBackend.post(withRequest: request)
  }

  /** @fn applyActionCode:completion:
      @brief Applies out of band code.

      @param code The out of band code to be applied.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks This method will not work for out of band codes which require an additional parameter,
          such as password reset code.
   */

  /** @fn sendPasswordResetWithEmail:completion:
      @brief Initiates a password reset for the given email address.

      @param email The email address of the user.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
              sent in the request.
          + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
              the console for this action.
          + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
              sending update email.

   */
  public func sendPasswordReset(withEmail email: String) async throws {
    try await sendPasswordReset(withEmail: email, actionCodeSettings: nil)
  }

  /** @fn sendPasswordResetWithEmail:actionCodeSetting:completion:
      @brief Initiates a password reset for the given email address and `ActionCodeSettings` object.

      @param email The email address of the user.
      @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
          handling action codes.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
              sent in the request.
          + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
              the console for this action.
          + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
              sending update email.
          + `AuthErrorCodeMissingIosBundleID` - Indicates that the iOS bundle ID is missing when
              `handleCodeInApp` is set to true.
          + `AuthErrorCodeMissingAndroidPackageName` - Indicates that the android package name
              is missing when the `androidInstallApp` flag is set to true.
          + `AuthErrorCodeUnauthorizedDomain` - Indicates that the domain specified in the
              continue URL is not allowlisted in the Firebase console.
          + `AuthErrorCodeInvalidContinueURI` - Indicates that the domain specified in the
              continue URL is not valid.

   */
  public func sendPasswordReset(withEmail email: String,
                                      actionCodeSettings: ActionCodeSettings?) async throws {
      let request = GetOOBConfirmationCodeRequest.passwordResetRequest(
        email: email,
        actionCodeSettings: actionCodeSettings,
        requestConfiguration: self.requestConfiguration
      )
      _ = try await AuthBackend.post(withRequest: request)
  }

  /** @fn sendPasswordResetWithEmail:actionCodeSetting:completion:
      @brief Initiates a password reset for the given email address and `ActionCodeSettings` object.

      @param email The email address of the user.
      @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
          handling action codes.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.

      @remarks Possible error codes:

          + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
              sent in the request.
          + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
              the console for this action.
          + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
              sending update email.
          + `AuthErrorCodeMissingIosBundleID` - Indicates that the iOS bundle ID is missing when
              `handleCodeInApp` is set to true.
          + `AuthErrorCodeMissingAndroidPackageName` - Indicates that the android package name
              is missing when the `androidInstallApp` flag is set to true.
          + `AuthErrorCodeUnauthorizedDomain` - Indicates that the domain specified in the
              continue URL is not allowlisted in the Firebase console.
          + `AuthErrorCodeInvalidContinueURI` - Indicates that the domain specified in the
              continue URL is not valid.

   */

  /** @fn sendSignInLinkToEmail:actionCodeSettings:completion:
      @brief Sends a sign in with email link to provided email address.

      @param email The email address of the user.
      @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
          handling action codes.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */
  public func sendSignInLink(toEmail email: String,
                                   actionCodeSettings: ActionCodeSettings) async throws {
      let request = GetOOBConfirmationCodeRequest.signInWithEmailLinkRequest(
        email,
        actionCodeSettings: actionCodeSettings,
        requestConfiguration: self.requestConfiguration
      )
      _ = try await AuthBackend.post(withRequest: request)
  }

  /** @fn sendSignInLinkToEmail:actionCodeSettings:completion:
      @brief Sends a sign in with email link to provided email address.

      @param email The email address of the user.
      @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
          handling action codes.
      @param completion Optionally; a block which is invoked when the request finishes. Invoked
          asynchronously on the main thread in the future.
   */

  /** @fn signOut:
      @brief Signs out the current user.

      @param error Optionally; if an error occurs, upon return contains an NSError object that
          describes the problem; is nil otherwise.
      @return @YES when the sign out request was successful. @NO otherwise.

      @remarks Possible error codes:

          + `AuthErrorCodeKeychainError` - Indicates an error occurred when accessing the
              keychain. The `NSLocalizedFailureReasonErrorKey` field in the `userInfo`
              dictionary will contain more information about the error encountered.

   */
   public func signOut() throws {
    try _state.withLock { state in
      guard state.currentUser != nil else { return }
      try _updateCurrentUser(nil, byForce: false, savingToDisk: true, state: &state)
    }
  }

  /** @fn isSignInWithEmailLink
      @brief Checks if link is an email sign-in link.

      @param link The email sign-in link.
      @return Returns true when the link passed matches the expected format of an email sign-in link.
   */
  public func isSignIn(withEmailLink link: String) -> Bool {
    guard link.count > 0 else {
      return false
    }
    let queryItems = getQueryItems(link)
    if let _ = queryItems["oobCode"],
       let mode = queryItems["mode"],
       mode == "signIn" {
      return true
    }
    return false
  }

  /** @fn addAuthStateDidChangeListener:
      @brief Registers a block as an "auth state did change" listener. To be invoked when:

        + The block is registered as a listener,
        + A user with a different UID from the current user has signed in, or
        + The current user has signed out.

      @param listener The block to be invoked. The block is always invoked asynchronously on the main
          thread, even for it's initial invocation after having been added as a listener.

      @remarks The block is invoked immediately after adding it according to it's standard invocation
          semantics, asynchronously on the main thread. Users should pay special attention to
          making sure the block does not inadvertently retain objects which should not be retained by
          the long-lived block. The block itself will be retained by `Auth` until it is
          unregistered or until the `Auth` instance is otherwise deallocated.

      @return A handle useful for manually unregistering the block as a listener.
   */
  
  public func addStateDidChangeListener(_ listener: @escaping @Sendable (Auth, User?) -> Void)
    -> any NSObjectProtocol {
    let firstInvocation = Mutex<Bool>(true)
    let previousUserID = Mutex<String?>(nil)
    return addIDTokenDidChangeListener { auth, user in
      let shouldCallListener = firstInvocation.withLock { first -> Bool in
        let prevID = previousUserID.withLock { $0 }
        let result = first || prevID != user?.uid
        first = false
        return result
      }
      previousUserID.withLock { $0 = user?.uid }
      if shouldCallListener {
        listener(auth, user)
      }
    }
  }

  /** @fn removeAuthStateDidChangeListener:
      @brief Unregisters a block as an "auth state did change" listener.

      @param listenerHandle The handle for the listener.
   */
  
  public func removeStateDidChangeListener(_ listenerHandle: any NSObjectProtocol) {
    NotificationCenter.default.removeObserver(listenerHandle)
    _state.withLock { state in
      state.listenerHandles.removeAll(where: { $0 === listenerHandle })
    }
  }

  /** @fn addIDTokenDidChangeListener:
      @brief Registers a block as an "ID token did change" listener. To be invoked when:

        + The block is registered as a listener,
        + A user with a different UID from the current user has signed in,
        + The ID token of the current user has been refreshed, or
        + The current user has signed out.

      @param listener The block to be invoked. The block is always invoked asynchronously on the main
          thread, even for it's initial invocation after having been added as a listener.

      @remarks The block is invoked immediately after adding it according to it's standard invocation
          semantics, asynchronously on the main thread. Users should pay special attention to
          making sure the block does not inadvertently retain objects which should not be retained by
          the long-lived block. The block itself will be retained by `Auth` until it is
          unregistered or until the `Auth` instance is otherwise deallocated.

      @return A handle useful for manually unregistering the block as a listener.
   */
  public func addIDTokenDidChangeListener(
    _ listener: @escaping @Sendable (Auth, User?) -> Void
  ) -> any NSObjectProtocol {
    let handle = NotificationCenter.default.addObserver(
      forName: Auth.authStateDidChangeNotification,
      object: self,
      queue: OperationQueue.main
    ) { notification in
      if let auth = notification.object as? Auth {
        listener(auth, auth.currentUser)
      }
    }
    _state.withLock { $0.listenerHandles.append(handle) }
    let auth = self
    DispatchQueue.main.async {
      listener(auth, auth.currentUser)
    }
    return handle
  }

  /** @fn removeIDTokenDidChangeListener:
      @brief Unregisters a block as an "ID token did change" listener.

      @param listenerHandle The handle for the listener.
   */
  public func removeIDTokenDidChangeListener(_ listenerHandle: AnyObject) {
    // TODO: implement me
  }

  /** @fn useAppLanguage
      @brief Sets `languageCode` to the app's current language.
   */
  public func useAppLanguage() {
    _state.withLock { $0.requestConfiguration.languageCode = Locale.preferredLanguages.first }
  }

  /** @fn useEmulatorWithHost:port
      @brief Configures Firebase Auth to connect to an emulated host instead of the remote backend.
   */
  public func useEmulator(withHost host: String, port: Int) {
    guard host.count > 0 else {
      fatalError("Cannot connect to empty host")
    }
    // If host is an IPv6 address, it should be formatted with surrounding brackets.
    let formattedHost = host.contains(":") ? "[\(host)]" : host
    _state.withLock { state in
      state.requestConfiguration.emulatorHostAndPort = "\(formattedHost):\(port)"
      #if os(iOS)
        state.settings?.appVerificationDisabledForTesting = true
      #endif
    }
  }

  /** @fn revokeTokenWithAuthorizationCode:Completion
      @brief Revoke the users token with authorization code.
      @param completion (Optional) the block invoked when the request to revoke the token is
          complete, or fails. Invoked asynchronously on the main thread in the future.
   */
     public func revokeToken(withAuthorizationCode authorizationCode: String) async throws {
         guard let currentUser = self.currentUser else { return }
         let idToken = try await currentUser.internalGetToken()
         let request = RevokeTokenRequest(withToken: authorizationCode,
                                          idToken: idToken,
                                          requestConfiguration: self.requestConfiguration)
         _ = try await AuthBackend.post(withRequest: request)
     }

  /** @fn revokeTokenWithAuthorizationCode:Completion
      @brief Revoke the users token with authorization code.
      @param completion (Optional) the block invoked when the request to revoke the token is
          complete, or fails. Invoked asynchronously on the main thread in the future.
   */

  /** @fn useUserAccessGroup:error:
      @brief Switch userAccessGroup and current user to the given accessGroup and the user stored in
          it.
   */
  public func useUserAccessGroup(_ accessGroup: String?) throws {
    try _state.withLock { state in
      try _internalUseUserAccessGroup(accessGroup, state: &state)
    }
  }

  private func _internalUseUserAccessGroup(_ accessGroup: String?, state: inout State) throws {
    state.storedUserManager.setStoredUserAccessGroup(accessGroup: accessGroup)
    let user = try _getStoredUser(forAccessGroup: accessGroup, state: &state)
    try _updateCurrentUser(user, byForce: false, savingToDisk: false, state: &state)
    if state.userAccessGroup == nil, accessGroup != nil {
      let userKey = "\(firebaseAppName)\(kUserKey)"
      try state.keychainServices.removeData(forKey: userKey)
    }
    state.userAccessGroup = accessGroup
    state.lastNotifiedUserToken = user?.rawAccessToken()
  }

  /// Get the stored user in the given accessGroup.
  ///
  /// - Note: Not supported on tvOS when `shareAuthStateAcrossDevices` is `true`. Returns `nil` in
  ///         that case. See https://github.com/firebase/firebase-ios-sdk/issues/8878.
  public func getStoredUser(forAccessGroup accessGroup: String?) throws -> User? {
    try _state.withLock { state in
      try _getStoredUser(forAccessGroup: accessGroup, state: &state)
    }
  }

  private func _getStoredUser(forAccessGroup accessGroup: String?, state: inout State) throws -> User? {
    var user: User?
    if let accessGroup {
      #if os(tvOS)
        if state.shareAuthStateAcrossDevices {
          AuthLog.logError(code: "I-AUT000001",
                           message: "Getting a stored user for a given access group is not supported " +
                             "on tvOS when `shareAuthStateAcrossDevices` is set to `true` (#8878)." +
                             "This case will return `nil`.")
          return nil
        }
      #endif
      guard let apiKey = app?.options.apiKey else {
        fatalError("Internal Auth Error: missing apiKey")
      }
      user = try state.storedUserManager.getStoredUser(
        accessGroup: accessGroup,
        shareAuthStateAcrossDevices: state.shareAuthStateAcrossDevices,
        projectIdentifier: apiKey
      ).user
    } else {
      let userKey = "\(firebaseAppName)\(kUserKey)"
      if let encodedUserData = try state.keychainServices.data(forKey: userKey) {
        let decoder = JSONDecoder()
        user = try decoder.decode(User.self, from: encodedUserData)
      }
    }
    user?.auth = self
    return user
  }

  #if os(iOS)
    public func setAPNSToken(_ token: Data, type: AuthAPNSTokenType) {
      _state.withLock { state in
        state.tokenManager.token = AuthAPNSToken(withData: token, type: type)
      }
    }

    public func canHandleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
      _state.withLock { state in
        state.notificationManager.canHandle(notification: userInfo)
      }
    }

    public func canHandle(_ url: URL) -> Bool {
      _state.withLock { state in
        guard let presenter = state.authURLPresenter as? AuthURLPresenter else {
          return false
        }
        return presenter.canHandle(url: url)
      }
    }
  #endif

  // TODO: Need to manage breaking change for
  // const NSNotificationName FIRAuthStateDidChangeNotification = @"FIRAuthStateDidChangeNotification";
  // Move to FIRApp with other Auth notifications?
  public static let authStateDidChangeNotification =
    NSNotification.Name(rawValue: "FIRAuthStateDidChangeNotification")

  // MARK: Internal methods

  init<T: AuthStorage>(app: FirebaseApp,
                       keychainStorageProvider: T.Type = AuthKeychainServices.self) {
    Auth.setKeychainServiceNameForApp(app)
    self.app = app
    self.firebaseAppName = app.name

    guard let apiKey = app.options.apiKey else {
      fatalError("Missing apiKey for Auth initialization")
    }

    let initialRequestConfiguration = AuthRequestConfiguration(
      apiKey: apiKey,
      appID: app.options.googleAppID,
      heartbeatLogger: app.heartbeatLogger,
      appCheck: nil
    )

    var initialState = State(requestConfiguration: initialRequestConfiguration)
    initialState.mainBundleUrlTypes = Bundle.main
      .object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
    #if os(iOS)
      initialState.authURLPresenter = AuthURLPresenter()
      initialState.settings = AuthSettings()
    #endif
    self._state = Mutex(initialState)

    _state.withLock { state in
      _protectedDataInitialization(keychainStorageProvider, state: &state)
    }
  }

  private func _protectedDataInitialization<T: AuthStorage>(
    _ keychainStorageProvider: T.Type,
    state: inout State
  ) {
    if let keychainServiceName = Auth.keychainServiceName(forAppName: firebaseAppName) {
      state.keychainServices = keychainStorageProvider.init(service: keychainServiceName)
      state.storedUserManager = AuthStoredUserManager(serviceName: keychainServiceName)
    }

    do {
      if let storedUserAccessGroup = state.storedUserManager.getStoredUserAccessGroup() {
        try _internalUseUserAccessGroup(storedUserAccessGroup, state: &state)
      } else {
        let user = try _getUser(state: &state)
        try _updateCurrentUser(user, byForce: false, savingToDisk: false, state: &state)
        if let user {
          state.tenantID = user.tenantID
          state.lastNotifiedUserToken = user.rawAccessToken()
        }
      }
    } catch {
      #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        // TODO: re-port the keychain pre-warming observer; the previous WIP referenced
        // an undefined `strongSelf` and never compiled. Tracking issue: phase 6.
      #endif
      AuthLog.logError(code: "I-AUT000001",
                       message: "Error loading saved user when starting up: \(error)")
    }

    #if os(iOS)
      // TODO: re-port the iOS phone-auth managers; the previous WIP referenced an
      // undefined `strongSelf` and never compiled. Tracking issue: phase 6.
    #endif
  }

  deinit {
    // TODO: re-enable observer removal once the iOS observer wiring is re-ported.
    // The previous WIP referenced an undefined `defaultCenter` symbol and never compiled.
  }

  private func _getUser(state: inout State) throws -> User? {
    var user: User?
    if let userAccessGroup = state.userAccessGroup {
      guard let apiKey = app?.options.apiKey else {
        fatalError("Internal Auth Error: missing apiKey")
      }
      user = try state.storedUserManager.getStoredUser(
        accessGroup: userAccessGroup,
        shareAuthStateAcrossDevices: state.shareAuthStateAcrossDevices,
        projectIdentifier: apiKey
      ).user
    } else {
      let userKey = "\(firebaseAppName)\(kUserKey)"
      guard let encodedUserData = try state.keychainServices.data(forKey: userKey) else {
        return nil
      }
      let decoder = JSONDecoder()
      user = try decoder.decode(User.self, from: encodedUserData)
    }
    user?.auth = self
    return user
  }

  /** @fn keychainServiceNameForAppName:
      @brief Gets the keychain service name global data for the particular app by name.
      @param appName The name of the Firebase app to get keychain service name for.
   */
  class func keychainServiceForAppID(_ appID: String) -> String {
    return "firebase_auth_\(appID)"
  }

     func updateKeychain(withUser user: User?) throws {
         try _state.withLock { state in
             if user != state.currentUser {
                 // No-op if the user is no longer signed in. This is not considered an error as we don't check
                 // whether the user is still current on other callbacks of user operations either.
                 return
             }
             try _saveUser(user, state: &state)
             _possiblyPostAuthStateChangeNotification(state: &state)
         }
     }

  /// A map from Firebase app name to keychain service names.
  ///
  /// Needed for looking up the keychain service name after the `FirebaseApp`
  /// instance is deleted, to remove the associated keychain item.
  fileprivate static let gKeychainServiceNameForAppName: Mutex<[String: String]> = .init([:])

  class func setKeychainServiceNameForApp(_ app: FirebaseApp) {
    gKeychainServiceNameForAppName.withLock {
      $0[app.name] = "firebase_auth_\(app.options.googleAppID)"
    }
  }

  /** @fn keychainServiceNameForAppName:
      @brief Gets the keychain service name global data for the particular app by name.
      @param appName The name of the Firebase app to get keychain service name for.
   */
  class func keychainServiceName(forAppName appName: String) -> String? {
    gKeychainServiceNameForAppName.withLock { $0[appName] }
  }

  /// Deletes the keychain service name global data for the particular app by name.
  class func deleteKeychainServiceNameForAppName(_ appName: String) {
    gKeychainServiceNameForAppName.withLock { _ = $0.removeValue(forKey: appName) }
  }

  internal func signOutByForce(withUserID userID: String) throws {
    try _state.withLock { state in
      guard state.currentUser?.uid == userID else { return }
      try _updateCurrentUser(nil, byForce: true, savingToDisk: true, state: &state)
    }
  }

  // MARK: Private methods

  /// Posts the auth state change notification if the current user's token has changed.
  /// Caller must hold the state lock; the actual notification post is dispatched async.
  private func _possiblyPostAuthStateChangeNotification(state: inout State) {
    let token = state.currentUser?.rawAccessToken()
    if state.lastNotifiedUserToken == token ||
      (token != nil && state.lastNotifiedUserToken == token) {
      return
    }
    state.lastNotifiedUserToken = token
    if state.autoRefreshTokens {
      // Schedule a new refresh task after successful attempt.
      _scheduleAutoTokenRefresh(state: &state)
    }
    // Post outside the lock by dispatching async.
    let center = NotificationCenter.default
    let name = Auth.authStateDidChangeNotification
    let auth = self
    DispatchQueue.main.async {
      center.post(name: name, object: auth)
    }
  }

  /// Schedules a task to automatically refresh tokens on the current user.
  /// The token refresh is scheduled 5 minutes before the scheduled expiration time.
  /// If the token expires in less than 5 minutes, schedules the refresh immediately.
  private func _scheduleAutoTokenRefresh(state: inout State) {
    let tokenExpirationInterval =
      (state.currentUser?.accessTokenExpirationDate()?.timeIntervalSinceNow ?? 0) - 5 * 60
    _scheduleAutoTokenRefresh(withDelay: max(tokenExpirationInterval, 0), retry: false, state: &state)
  }

  private func _scheduleAutoTokenRefresh(withDelay delay: TimeInterval, retry: Bool, state: inout State) {
    guard let accessToken = state.currentUser?.rawAccessToken() else {
      return
    }
    let intDelay = Int(ceil(delay))
    if retry {
      AuthLog.logInfo(code: "I-AUT000003", message: "Token auto-refresh re-scheduled in " +
                      "\(intDelay / 60):\(intDelay % 60) " +
                      "because of error on previous refresh attempt.")
    } else {
      AuthLog.logInfo(code: "I-AUT000004", message: "Token auto-refresh scheduled in " +
                      "\(intDelay / 60):\(intDelay % 60) " +
                      "for the new token.")
    }
    state.autoRefreshScheduled = true
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard let self else { return }
      let snapshot = self._state.withLock { state -> (User?, Bool) in
        (state.currentUser, state.isAppInBackground)
      }
      guard let currentUser = snapshot.0 else { return }
      guard currentUser.rawAccessToken() == accessToken else {
        // Another auto refresh must have been scheduled, so keep _autoRefreshScheduled unchanged.
        return
      }
      self._state.withLock { $0.autoRefreshScheduled = false }
      if snapshot.1 { return }
      let uid = currentUser.uid
      let _ = try await currentUser.internalGetToken(forceRefresh: true)
      if currentUser.uid != uid { return }
      // Kicks off exponential back off logic to retry failed attempt. Starts with one minute delay
      // (60 seconds) if this is the first failed attempt.
      let rescheduleDelay = retry ? min(delay * 2, 16 * 60) : 60
      self._state.withLock { state in
        self._scheduleAutoTokenRefresh(withDelay: rescheduleDelay, retry: true, state: &state)
      }
    }
  }

  /// Updates the current user, optionally persisting to disk.
  ///
  /// Called during sign-in/sign-out and class initialization. `saveToDisk` is only
  /// `false` during init when the user was just read from disk.
  /// Caller must hold the state lock.
  private func _updateCurrentUser(_ user: User?, byForce force: Bool,
                                  savingToDisk saveToDisk: Bool,
                                  state: inout State) throws {
    if user == state.currentUser {
      _possiblyPostAuthStateChangeNotification(state: &state)
    }
    if let user {
      if user.tenantID != nil || state.tenantID != nil, state.tenantID != user.tenantID {
        throw AuthErrorUtils.tenantIDMismatchError()
      }
    }
    var throwError: Error?
    if saveToDisk {
      do {
        try _saveUser(user, state: &state)
      } catch {
        throwError = error
      }
    }
    if throwError == nil || force {
      state.currentUser = user
      _possiblyPostAuthStateChangeNotification(state: &state)
    }
    if let throwError {
      throw throwError
    }
  }

  private func _saveUser(_ user: User?, state: inout State) throws {
    if let userAccessGroup = state.userAccessGroup {
      guard let apiKey = app?.options.apiKey else {
        fatalError("Internal Auth Error: Missing apiKey in saveUser")
      }
      if let user {
        try state.storedUserManager.setStoredUser(
          user: user,
          accessGroup: userAccessGroup,
          shareAuthStateAcrossDevices: state.shareAuthStateAcrossDevices,
          projectIdentifier: apiKey
        )
      } else {
        try state.storedUserManager.removeStoredUser(
          accessGroup: userAccessGroup,
          shareAuthStateAcrossDevices: state.shareAuthStateAcrossDevices,
          projectIdentifier: apiKey
        )
      }
    } else {
      let userKey = "\(firebaseAppName)\(kUserKey)"
      if let user {
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        try state.keychainServices.setData(data, forKey: userKey)
      } else {
        try state.keychainServices.removeData(forKey: userKey)
      }
    }
  }

  /** @fn completeSignInWithTokenService:callback:
      @brief Completes a sign-in flow once we have access and refresh tokens for the user.
      @param accessToken The STS access token.
      @param accessTokenExpirationDate The approximate expiration date of the access token.
      @param refreshToken The STS refresh token.
      @param anonymous Whether or not the user is anonymous.
      @param callback Called when the user has been signed in or when an error occurred. Invoked
          asynchronously on the global auth work queue in the future.
   */
  // TODO: internal
  public func completeSignIn(withAccessToken accessToken: String,
                                   accessTokenExpirationDate: Date?,
                                   refreshToken: String,
                                   anonymous: Bool) async throws -> User {
      try await User.retrieveUser(withAuth: self,
                                  accessToken: accessToken,
                                  accessTokenExpirationDate: accessTokenExpirationDate,
                                  refreshToken: refreshToken,
                                  anonymous: anonymous)
  }

  /** @fn internalSignInAndRetrieveDataWithEmail:password:callback:
      @brief Signs in using an email address and password.
      @param email The user's email address.
      @param password The user's password.
      @param completion A block which is invoked when the sign in finishes (or is cancelled.) Invoked
          asynchronously on the global auth work queue in the future.
      @remarks This is the internal counterpart of this method, which uses a callback that does not
          update the current user.
   */
     private func internalSignInAndRetrieveData(withEmail email: String, password: String) async throws -> AuthDataResult {
         let credential = EmailAuthCredential(withEmail: email, password: password)
         return try await internalSignInAndRetrieveData(
            withCredential: credential,
            isReauthentication: false
         )
     }

  internal func internalSignInAndRetrieveData(withCredential credential: AuthCredential,
                                              isReauthentication: Bool) async throws -> AuthDataResult {
      if let emailCredential = credential as? EmailAuthCredential {
          // Special case for email/password credentials
          switch emailCredential.emailType {
          case let .link(link):
              // Email link sign in
              return try await internalSignInAndRetrieveData(withEmail: emailCredential.email,
                                                             link: link)
          case let .password(password):
              // Email password sign in
              let user: User = try await internalSignIn(withEmail: emailCredential.email,
                                                        password: password)
              let additionalUserInfo = AdditionalUserInfo(providerID: EmailAuthProvider.id,
                                                          profile: nil,
                                                          username: nil,
                                                          isNewUser: false)
              return AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
          }
      }
#if os(macOS) || os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
      if let gameCenterCredential = credential as? GameCenterAuthCredential {
          return try await signInAndRetrieveData(withGameCenterCredential: gameCenterCredential)
      }
#endif
#if os(iOS)
      if let phoneCredential = credential as? PhoneAuthCredential {
          // Special case for phone auth credentials
          let operation = isReauthentication ? AuthOperationType.reauth : AuthOperationType
              .signUpOrSignIn
          signIn(withPhoneCredential: phoneCredential,
                 operation: operation) { rawResponse, error in
              if let callback {
                  if let error {
                      callback(nil, error)
                      return
                  }
                  guard let response = rawResponse as? VerifyPhoneNumberResponse else {
                      fatalError("Internal Auth Error: Failed to get a VerifyPhoneNumberResponse")
                  }
                  self.completeSignIn(withAccessToken: response.idToken,
                                      accessTokenExpirationDate: response.approximateExpirationDate,
                                      refreshToken: response.refreshToken,
                                      anonymous: false) { user, error in
                      if let error {
                          callback(nil, error)
                          return
                      }
                      if let user {
                          let additionalUserInfo = AdditionalUserInfo(providerID: PhoneAuthProvider.id,
                                                                      profile: nil,
                                                                      username: nil,
                                                                      isNewUser: response.isNewUser)
                          let result = AuthDataResult(
                            withUser: user,
                            additionalUserInfo: additionalUserInfo
                          )
                          callback(result, nil)
                      } else {
                          callback(nil, nil)
                      }
                  }
              }
          }
          return
      }
#endif
      
      var request = VerifyAssertionRequest(providerID: credential.provider,
                                           requestConfiguration: requestConfiguration)
      request.autoCreate = !isReauthentication
      credential.prepare(&request)
      let response = try await AuthBackend.post(withRequest: request)
      if response.needConfirmation {
          let email = response.email
          let credential = OAuthCredential(withVerifyAssertionResponse: response)
          throw AuthErrorUtils.accountExistsWithDifferentCredentialError(
            email: email,
            updatedCredential: credential
          )
      }
      guard let providerID = response.providerID, providerID.count > 0 else {
          throw AuthErrorUtils.unexpectedResponse(deserializedResponse: response)
      }
      let user = try await self.completeSignIn(withAccessToken: response.idToken,
                                               accessTokenExpirationDate: response.approximateExpirationDate,
                                               refreshToken: response.refreshToken,
                                               anonymous: false)
      let additionalUserInfo = AdditionalUserInfo.userInfo(verifyAssertionResponse: response)
      let updatedOAuthCredential = OAuthCredential(withVerifyAssertionResponse: response)
      let result = AuthDataResult(withUser: user,
                                  additionalUserInfo: additionalUserInfo,
                                  credential: updatedOAuthCredential)
      return result
  }

  #if os(iOS)
    /** @fn signInWithPhoneCredential:callback:
        @brief Signs in using a phone credential.
        @param credential The Phone Auth credential used to sign in.
        @param operation The type of operation for which this sign-in attempt is initiated.
        @param callback A block which is invoked when the sign in finishes (or is cancelled.) Invoked
            asynchronously on the global auth work queue in the future.
     */
    private func signIn(withPhoneCredential credential: PhoneAuthCredential,
                        operation: AuthOperationType,
                        callback: @escaping (AuthRPCResponse?, Error?) -> Void) {
      switch credential.credentialKind {
      case let .phoneNumber(phoneNumber, temporaryProof):
        let request = VerifyPhoneNumberRequest(temporaryProof: temporaryProof,
                                               phoneNumber: phoneNumber,
                                               operation: operation,
                                               requestConfiguration: requestConfiguration)
        AuthBackend.post(withRequest: request, callback: callback)
        return
      case let .verification(verificationID, code):
        guard verificationID.count > 0 else {
          callback(nil, AuthErrorUtils.missingVerificationIDError(message: nil))
          return
        }
        guard code.count > 0 else {
          callback(nil, AuthErrorUtils.missingVerificationCodeError(message: nil))
          return
        }
        let request = VerifyPhoneNumberRequest(verificationID: verificationID,
                                               verificationCode: code,
                                               operation: operation,
                                               requestConfiguration: requestConfiguration)
        AuthBackend.post(withRequest: request, callback: callback)
      }
    }
  #endif

#if os(macOS) || os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    /** @fn signInAndRetrieveDataWithGameCenterCredential:callback:
        @brief Signs in using a game center credential.
        @param credential The Game Center Auth Credential used to sign in.
        @param callback A block which is invoked when the sign in finished (or is cancelled). Invoked
            asynchronously on the global auth work queue in the future.
     */
     private func signInAndRetrieveData(withGameCenterCredential credential: GameCenterAuthCredential) async throws -> AuthDataResult {
         guard let publicKeyURL = credential.publicKeyURL,
               let signature = credential.signature,
               let salt = credential.salt else {
             fatalError(
                "Internal Auth Error: Game Center credential missing publicKeyURL, signature, or salt"
             )
         }
         let request = SignInWithGameCenterRequest(playerID: credential.playerID,
                                                   teamPlayerID: credential.teamPlayerID,
                                                   gamePlayerID: credential.gamePlayerID,
                                                   publicKeyURL: publicKeyURL,
                                                   signature: signature,
                                                   salt: salt,
                                                   timestamp: credential.timestamp,
                                                   displayName: credential.displayName,
                                                   requestConfiguration: requestConfiguration)
         let response = try await AuthBackend.post(withRequest: request)
         let user = try await self.completeSignIn(withAccessToken: response.idToken,
                                                  accessTokenExpirationDate: response.approximateExpirationDate,
                                                  refreshToken: response.refreshToken,
                                                  anonymous: false)
         let additionalUserInfo = AdditionalUserInfo(providerID: GameCenterAuthProvider.id,
                                                     profile: nil,
                                                     username: nil,
                                                     isNewUser: response.isNewUser)
         return AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
     }
  #endif

  /** @fn internalSignInAndRetrieveDataWithEmail:link:completion:
      @brief Signs in using an email and email sign-in link.
      @param email The user's email address.
      @param link The email sign-in link.
      @param callback A block which is invoked when the sign in finishes (or is cancelled.) Invoked
          asynchronously on the global auth work queue in the future.
   */
  private func internalSignInAndRetrieveData(withEmail email: String,
                                             link: String) async throws -> AuthDataResult {
      guard isSignIn(withEmailLink: link) else {
          fatalError("The link provided is not valid for email/link sign-in. Please check the link by " +
                     "calling isSignIn(withEmailLink:) on the Auth instance before attempting to use it " +
                     "for email/link sign-in.")
      }
      let queryItems = getQueryItems(link)
      guard let actionCode = queryItems["oobCode"] else {
          fatalError("Missing oobCode in link URL")
      }
      let request = EmailLinkSignInRequest(email: email,
                                           oobCode: actionCode,
                                           requestConfiguration: requestConfiguration)
      let response = try await AuthBackend.post(withRequest: request)
      let user = try await self.completeSignIn(withAccessToken: response.idToken,
                                               accessTokenExpirationDate: response.approximateExpirationDate,
                                               refreshToken: response.refreshToken,
                                               anonymous: false)
      let additionalUserInfo = AdditionalUserInfo(providerID: EmailAuthProvider.id,
                                                  profile: nil,
                                                  username: nil,
                                                  isNewUser: response.isNewUser)
      return AuthDataResult(withUser: user, additionalUserInfo: additionalUserInfo)
  }

  private func getQueryItems(_ link: String) -> [String: String] {
    var queryItems = AuthWebUtils.parseURL(link)
    if queryItems.count == 0 {
      let urlComponents = URLComponents(string: link)
      if let query = urlComponents?.query {
        queryItems = AuthWebUtils.parseURL(query)
      }
    }
    return queryItems
  }

  /** @fn signInFlowAuthDataResultCallbackByDecoratingCallback:
       @brief Creates a FIRAuthDataResultCallback block which wraps another FIRAuthDataResultCallback;
           trying to update the current user before forwarding it's invocations along to a subject
           block.
       @param callback Called when the user has been updated or when an error has occurred. Invoked
           asynchronously on the main thread in the future.
       @return Returns a block that updates the current user.
       @remarks Typically invoked as part of the complete sign-in flow. For any other uses please
           consider alternative ways of updating the current user.
   */

  // MARK: Internal properties

  /** @property mainBundle
      @brief Allow tests to swap in an alternate mainBundle.
   */
  internal var mainBundleUrlTypes: [[String: Any]]? {
    get { _state.withLock { $0.mainBundleUrlTypes } }
    set { _state.withLock { $0.mainBundleUrlTypes = newValue } }
  }

  /** @property requestConfiguration
      @brief The configuration object comprising of paramters needed to make a request to Firebase
          Auth's backend.
   */
  // TODO: internal
  public var requestConfiguration: AuthRequestConfiguration {
    get { _state.withLock { $0.requestConfiguration } }
    set { _state.withLock { $0.requestConfiguration = newValue } }
  }

  #if os(iOS)

    // TODO: the next three should be internal after Sample is ported.
    public var tokenManager: AuthAPNSTokenManager! {
      get { _state.withLock { $0.tokenManager } }
      set { _state.withLock { $0.tokenManager = newValue } }
    }

    public var appCredentialManager: AuthAppCredentialManager! {
      get { _state.withLock { $0.appCredentialManager } }
      set { _state.withLock { $0.appCredentialManager = newValue } }
    }

    public var notificationManager: AuthNotificationManager! {
      get { _state.withLock { $0.notificationManager } }
      set { _state.withLock { $0.notificationManager = newValue } }
    }

    internal var authURLPresenter: AuthWebViewControllerDelegate {
      get { _state.withLock { $0.authURLPresenter! } }
      set { _state.withLock { $0.authURLPresenter = newValue } }
    }

  #endif // TARGET_OS_IOS

  // MARK: Private properties

  /// The Firebase app name. Immutable.
  private let firebaseAppName: String

  /// Key of user stored in the keychain. Prefixed with a Firebase app name.
  private let kUserKey = "_firebase_user"

  /// All mutable state lives here, protected by `Mutex`.
  ///
  /// Methods that mutate compound state (e.g. `_updateCurrentUser`) take an
  /// `inout State` and are called from inside a single `_state.withLock` block.
  /// Public scalar properties go through one `withLock` per access.
  fileprivate let _state: Mutex<State>

  /// Bag of all mutable Auth state. Access only via `_state.withLock`.
  struct State: @unchecked Sendable {
    var requestConfiguration: AuthRequestConfiguration
    var currentUser: User?
    var languageCode: String?
    var settings: AuthSettings?
    var userAccessGroup: String?
    var shareAuthStateAcrossDevices: Bool = false
    var tenantID: String?
    var lastNotifiedUserToken: String?
    var autoRefreshTokens: Bool = false
    var autoRefreshScheduled: Bool = false
    var isAppInBackground: Bool = false
    var mainBundleUrlTypes: [[String: Any]]?
    var keychainServices: AuthStorage!
    var storedUserManager: AuthStoredUserManager!
    var listenerHandles: [any NSObjectProtocol] = []

    #if os(iOS)
      var tokenManager: AuthAPNSTokenManager!
      var appCredentialManager: AuthAppCredentialManager!
      var notificationManager: AuthNotificationManager!
      var authURLPresenter: AuthWebViewControllerDelegate!
      var applicationDidBecomeActiveObserver: AnyObject?
      var applicationDidEnterBackgroundObserver: AnyObject?
      var protectedDataDidBecomeAvailableObserver: AnyObject?
    #endif

    init(requestConfiguration: AuthRequestConfiguration) {
      self.requestConfiguration = requestConfiguration
    }
  }
}
