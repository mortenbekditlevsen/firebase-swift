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

//@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
//extension User: Codable {}

/// A small wrapper so a `weak` reference can be stored inside a `Mutex`.
struct WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

/** @class User
    @brief Represents a user. Firebase Auth does not attempt to validate users
        when loading them from the keychain. Invalidated users (such as those
        whose passwords have been changed on another client) are automatically
        logged out when an auth-dependent operation is attempted or when the
        ID token is automatically refreshed.
    @remarks This class is thread-safe.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
public final class User: UserInfo, Sendable, Codable, Equatable {
    public static func == (lhs: User, rhs: User) -> Bool {
        lhs.userdata == rhs.userdata
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let userData = try container.decode(UserData.self)
        self._userData = Mutex(userData)
        self.taskQueue = AuthSerialTaskQueue()
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(userdata)
    }
    
    nonisolated
    internal var userdata: UserData {
        get {
            _userData.withLock { $0 }
        }
        set {
            _userData.withLock {
                $0 = newValue
            }
        }
    }
    
    private let _userData: Mutex<UserData>
    
    /** @property anonymous
     @brief Indicates the user represents an anonymous user.
     */
    public var isAnonymous: Bool {
        userdata.isAnonymous
    }
    
    /** @property emailVerified
     @brief Indicates the email address associated with this user has been verified.
     */
    public var isEmailVerified: Bool {
        userdata.isEmailVerified
    }
    
    /** @property providerData
     @brief Profile data for each identity provider, if any.
     @remarks This data is cached on sign-in and updated when linking or unlinking.
     */
    public var providerData: [UserInfoImpl] {
        Array(providerDataRaw.values)
    }
    
    private var providerDataRaw: [String: UserInfoImpl] {
        userdata.providerDataRaw
    }
    
    /** @property metadata
     @brief Metadata associated with the Firebase user in question.
     */
    public var metadata: UserMetadata {
        userdata.metadata
    }
    
    /** @property tenantID
     @brief The tenant ID of the current user. nil if none is available.
     */
    public var tenantID: String? {
        get {
            userdata.tenantID
        }
        set {
            userdata.tenantID = newValue
        }
    }
    
#if os(iOS)
    /** @property multiFactor
     @brief Multi factor object associated with the user.
     This property is available on iOS only.
     */
    @MainActor
    public private(set) var multiFactor: MultiFactor
#endif
    
    /** @fn updateEmail:completion:
     @brief Updates the email address for the user. On success, the cached user profile data is
     updated.
     @remarks May fail if there is already an account with this email address that was created using
     email and password authentication.
     
     @param email The email address for the user.
     @param completion Optionally; the block invoked when the user profile change has finished.
     Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
     sent in the request.
     + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
     the console for this action.
     + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
     sending update email.
     + `AuthErrorCodeEmailAlreadyInUse` - Indicates the email is already in use by another
     account.
     + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s email is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    public func updateEmail(to email: String) async throws {
        //        kAuthGlobalWorkQueue.async {
        try await self.updateEmail(email: email, password: nil)
        //            User.callInMainThreadWithError(callback: completion, error: error)
        //        }
    }
    
    /** @fn updateEmail
     @brief Updates the email address for the user. On success, the cached user profile data is
     updated.
     @remarks May fail if there is already an account with this email address that was created using
     email and password authentication.
     
     @param email The email address for the user.
     @throws Error on failure.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
     sent in the request.
     + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
     the console for this action.
     + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
     sending update email.
     + `AuthErrorCodeEmailAlreadyInUse` - Indicates the email is already in use by another
     account.
     + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s email is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    /** @fn updatePassword:completion:
     @brief Updates the password for the user. On success, the cached user profile data is updated.
     
     @param password The new password for the user.
     @param completion Optionally; the block invoked when the user profile change has finished.
     Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeOperationNotAllowed` - Indicates the administrator disabled
     sign in with the specified identity provider.
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s password is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
     considered too weak. The `NSLocalizedFailureReasonErrorKey` field in the `userInfo`
     dictionary object will contain more detailed explanation that can be shown to the user.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    public func updatePassword(to password: String) async throws {
        guard !password.isEmpty else {
            throw AuthErrorUtils.weakPasswordError(serverResponseReason: "Missing Password")
        }
        try await self.updateEmail(email: nil, password: password)
    }
    
    /** @fn updatePassword
     @brief Updates the password for the user. On success, the cached user profile data is updated.
     
     @param password The new password for the user.
     @throws Error on failure.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeOperationNotAllowed` - Indicates the administrator disabled
     sign in with the specified identity provider.
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s password is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     + `AuthErrorCodeWeakPassword` - Indicates an attempt to set a password that is
     considered too weak. The `NSLocalizedFailureReasonErrorKey` field in the `userInfo`
     dictionary object will contain more detailed explanation that can be shown to the user.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
#if os(iOS)
    /** @fn updatePhoneNumberCredential:completion:
     @brief Updates the phone number for the user. On success, the cached user profile data is
     updated.
     This method is available on iOS only.
     
     @param phoneNumberCredential The new phone number credential corresponding to the phone number
     to be added to the Firebase account, if a phone number is already linked to the account this
     new phone number will replace it.
     @param completion Optionally; the block invoked when the user profile change has finished.
     Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s phone number is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    public func updatePhoneNumber(_ credential: PhoneAuthCredential,
                                  completion: ((Error?) -> Void)? = nil) {
        kAuthGlobalWorkQueue.async {
            self.internalUpdateOrLinkPhoneNumber(credential: credential,
                                                 isLinkOperation: false) { error in
                User.callInMainThreadWithError(callback: completion, error: error)
            }
        }
    }
    
    /** @fn updatePhoneNumberCredential
     @brief Updates the phone number for the user. On success, the cached user profile data is
     updated.
     This method is available on iOS only.
     
     @param phoneNumberCredential The new phone number credential corresponding to the phone number
     to be added to the Firebase account, if a phone number is already linked to the account this
     new phone number will replace it.
     @throws an error.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeRequiresRecentLogin` - Updating a user’s phone number is a security
     sensitive operation that requires a recent login from the user. This error indicates
     the user has not signed in recently enough. To resolve, reauthenticate the user by
     calling `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    @available(iOS 13, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
    public func updatePhoneNumber(_ credential: PhoneAuthCredential) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.updatePhoneNumber(credential) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
#endif
    
    /** @fn profileChangeRequest
     @brief Creates an object which may be used to change the user's profile data.
     
     @remarks Set the properties of the returned object, then call
     `UserProfileChangeRequest.commitChanges()` to perform the updates atomically.
     
     @return An object which may be used to change the user's profile data atomically.
     */
    
    public func createProfileChangeRequest() -> UserProfileChangeRequest {
        UserProfileChangeRequest(self)
    }
    
    /** @property refreshToken
     @brief A refresh token; useful for obtaining new access tokens independently.
     @remarks This property should only be used for advanced scenarios, and is not typically needed.
     */
    public var refreshToken: String? {
        self.tokenService.refreshToken
    }
    
    /** @fn reloadWithCompletion:
     @brief Reloads the user's profile data from the server.
     
     @param completion Optionally; the block invoked when the reload has finished. Invoked
     asynchronously on the main thread in the future.
     
     @remarks May fail with a `AuthErrorCodeRequiresRecentLogin` error code. In this case
     you should call `reauthenticate(with:)` before re-invoking
     `updateEmail(to:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    public func reload() async throws {
        _ = try await self.getAccountInfoRefreshingCache()
    }
    
    /** @fn reload
     @brief Reloads the user's profile data from the server.
     
     @param completion Optionally; the block invoked when the reload has finished. Invoked
     asynchronously on the main thread in the future.
     
     @remarks May fail with a `AuthErrorCodeRequiresRecentLogin` error code. In this case
     you should call `reauthenticate(with:)` before re-invoking
     `updateEmail(to:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    /** @fn reauthenticateWithCredential:completion:
     @brief Renews the user's authentication tokens by validating a fresh set of credentials supplied
     by the user  and returns additional identity provider data.
     
     @param credential A user-supplied credential, which will be validated by the server. This can be
     a successful third-party identity provider sign-in, or an email address and password.
     @param completion Optionally; the block invoked when the re-authentication operation has
     finished. Invoked asynchronously on the main thread in the future.
     
     @remarks If the user associated with the supplied credential is different from the current user,
     or if the validation of the supplied credentials fails; an error is returned and the current
     user remains signed in.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidCredential` - Indicates the supplied credential is invalid.
     This could happen if it has expired or it is malformed.
     + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts with the
     identity provider represented by the credential are not enabled. Enable them in the
     Auth section of the Firebase console.
     + `AuthErrorCodeEmailAlreadyInUse` -  Indicates the email asserted by the credential
     (e.g. the email in a Facebook access token) is already in use by an existing account,
     that cannot be authenticated with this method. Call `Auth.fetchSignInMethods(forEmail:)`
     for this user’s email and then prompt them to sign in with any of the sign-in providers
     returned. This error will only be thrown if the "One account per email address"
     setting is enabled in the Firebase console, under Auth settings. Please note that the
     error code raised in this specific situation may not be the same on Web and Android.
     + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
     + `AuthErrorCodeWrongPassword` - Indicates the user attempted reauthentication with
     an incorrect password, if credential is of the type `EmailPasswordAuthCredential`.
     + `AuthErrorCodeUserMismatch` -  Indicates that an attempt was made to
     reauthenticate with a user which is not the current user.
     + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    public func reauthenticate(with credential: AuthCredential) async throws -> AuthDataResult {
        // Perhaps not the best error, but this is what would be thrown if auth was nil in the old code
        guard let auth else {
            throw AuthErrorUtils.userMismatchError()
        }
        let authResult: AuthDataResult
        do {
            authResult = try await auth.internalSignInAndRetrieveData(
                withCredential: credential,
                isReauthentication: true
            )
        } catch {
            // If "user not found" error returned by backend,
            // translate to user mismatch error which is more
            // accurate.
            var reportError: Error = error
            if (error as NSError).code == AuthErrorCode.userNotFound.rawValue {
                reportError = AuthErrorUtils.userMismatchError()
            }
            throw reportError
        }
        let user = authResult.user
        guard user.uid == auth.getUserID() else {
            throw AuthErrorUtils.userMismatchError()
        }
        // Successful reauthenticate
        try await self.setTokenService(tokenService: user.tokenService)
        return authResult
    }
    
    /** @fn reauthenticateWithCredential
     @brief Renews the user's authentication tokens by validating a fresh set of credentials supplied
     by the user  and returns additional identity provider data.
     
     @param credential A user-supplied credential, which will be validated by the server. This can be
     a successful third-party identity provider sign-in, or an email address and password.
     @returns An AuthDataResult.
     
     @remarks If the user associated with the supplied credential is different from the current user,
     or if the validation of the supplied credentials fails; an error is returned and the current
     user remains signed in.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidCredential` - Indicates the supplied credential is invalid.
     This could happen if it has expired or it is malformed.
     + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts with the
     identity provider represented by the credential are not enabled. Enable them in the
     Auth section of the Firebase console.
     + `AuthErrorCodeEmailAlreadyInUse` -  Indicates the email asserted by the credential
     (e.g. the email in a Facebook access token) is already in use by an existing account,
     that cannot be authenticated with this method. Call `Auth.fetchSignInMethods(forEmail:)`
     for this user’s email and then prompt them to sign in with any of the sign-in providers
     returned. This error will only be thrown if the "One account per email address"
     setting is enabled in the Firebase console, under Auth settings. Please note that the
     error code raised in this specific situation may not be the same on Web and Android.
     + `AuthErrorCodeUserDisabled` - Indicates the user's account is disabled.
     + `AuthErrorCodeWrongPassword` - Indicates the user attempted reauthentication with
     an incorrect password, if credential is of the type `EmailPasswordAuthCredential`.
     + `AuthErrorCodeUserMismatch` -  Indicates that an attempt was made to
     reauthenticate with a user which is not the current user.
     + `AuthErrorCodeInvalidEmail` - Indicates the email address is malformed.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
  
    
#if os(iOS)
    /** @fn reauthenticateWithProvider:UIDelegate:completion:
     @brief Renews the user's authentication using the provided auth provider instance.
     This method is available on iOS only.
     
     @param provider An instance of an auth provider used to initiate the reauthenticate flow.
     @param UIDelegate Optionally an instance of a class conforming to the `AuthUIDelegate`
     protocol, used for presenting the web context. If nil, a default `AuthUIDelegate`
     will be used.
     @param completion Optionally; a block which is invoked when the reauthenticate flow finishes, or
     is canceled. Invoked asynchronously on the main thread in the future.
     */
    
    public func reauthenticate(with provider: FederatedAuthProvider,
                               uiDelegate: AuthUIDelegate?,
                               completion: ((AuthDataResult?, Error?) -> Void)? = nil) {
        kAuthGlobalWorkQueue.async {
            provider.getCredentialWith(uiDelegate) { credential, error in
                if let error {
                    if let completion {
                        completion(nil, error)
                    }
                    return
                }
                if let credential {
                    self.reauthenticate(with: credential, completion: completion)
                }
            }
        }
    }
    
    /** @fn reauthenticateWithProvider:UIDelegate
     @brief Renews the user's authentication using the provided auth provider instance.
     This method is available on iOS only.
     
     @param provider An instance of an auth provider used to initiate the reauthenticate flow.
     @param UIDelegate Optionally an instance of a class conforming to the `AuthUIDelegate`
     protocol, used for presenting the web context. If nil, a default `AuthUIDelegate`
     will be used.
     @returns An AuthDataResult.
     */
    @available(iOS 13, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
    @discardableResult
    public func reauthenticate(with provider: FederatedAuthProvider,
                               uiDelegate: AuthUIDelegate?) async throws -> AuthDataResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.reauthenticate(with: provider, uiDelegate: uiDelegate) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else if let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
#endif
    
    /** @fn getIDTokenWithCompletion:
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param completion Optionally; the block invoked when the token is available. Invoked
     asynchronously on the main thread in the future.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    
    /** @fn getIDTokenForcingRefresh:completion:
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param forceRefresh Forces a token refresh. Useful if the token becomes invalid for some reason
     other than an expiration.
     @param completion Optionally; the block invoked when the token is available. Invoked
     asynchronously on the main thread in the future.
     
     @remarks The authentication token will be refreshed (by making a network request) if it has
     expired, or if `forceRefresh` is true.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    public func getIDToken(forcingRefresh forceRefresh: Bool = false) async throws -> String? {
        
        try await getIDTokenResult(forcingRefresh: forceRefresh)?.token
    }
    
    /** @fn getIDTokenForcingRefresh:completion:
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param forceRefresh Forces a token refresh. Useful if the token becomes invalid for some reason
     other than an expiration.
     @returns The Token.
     
     @remarks The authentication token will be refreshed (by making a network request) if it has
     expired, or if `forceRefresh` is true.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    /** @fn getIDTokenResultWithCompletion:
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param completion Optionally; the block invoked when the token is available. Invoked
     asynchronously on the main thread in the future.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    /** @fn getIDTokenResultForcingRefresh:completion:
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param forceRefresh Forces a token refresh. Useful if the token becomes invalid for some reason
     other than an expiration.
     @param completion Optionally; the block invoked when the token is available. Invoked
     asynchronously on the main thread in the future.
     
     @remarks The authentication token will be refreshed (by making a network request) if it has
     expired, or if `forceRefresh` is YES.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    public func getIDTokenResult(forcingRefresh: Bool = false) async throws -> AuthTokenResult? {
        let token = try await self.internalGetToken(forceRefresh: forcingRefresh)
        
        let tokenResult = AuthTokenResult.tokenResult(token: token)
        AuthLog.logDebug(code: "I-AUT000017", message: "Actual token expiration date: " +
                         "\(String(describing: tokenResult?.expirationDate))," +
                         "current date: \(Date())")
        return tokenResult
    }
    
    /** @fn getIDTokenResultForcingRefresh
     @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
     
     @param forceRefresh Forces a token refresh. Useful if the token becomes invalid for some reason
     other than an expiration.
     @returns The token.
     
     @remarks The authentication token will be refreshed (by making a network request) if it has
     expired, or if `forceRefresh` is YES.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all API methods.
     */
    
    /** @fn linkWithCredential:completion:
     @brief Associates a user account from a third-party identity provider with this user and
     returns additional identity provider data.
     
     @param credential The credential for the identity provider.
     @param completion Optionally; the block invoked when the unlinking is complete, or fails.
     Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeProviderAlreadyLinked` - Indicates an attempt to link a provider of a
     type already linked to this account.
     + `AuthErrorCodeCredentialAlreadyInUse` - Indicates an attempt to link with a
     credential that has already been linked with a different Firebase account.
     + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts with the identity
     provider represented by the credential are not enabled. Enable them in the Auth section
     of the Firebase console.
     
     @remarks This method may also return error codes associated with `updateEmail(to:)` and
     `updatePassword(to:)` on `User`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    public func link(with credential: AuthCredential) async throws -> AuthDataResult {
        if self.providerDataRaw[credential.provider] != nil {
            throw AuthErrorUtils.providerAlreadyLinkedError()
        }
        if let emailCredential = credential as? EmailAuthCredential {
            return try await self.link(withEmailCredential: emailCredential)
        }
#if os(macOS) || os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        if let gameCenterCredential = credential as? GameCenterAuthCredential {
            return try await self.link(withGameCenterCredential: gameCenterCredential)
        }
#endif
#if os(iOS)
        if let phoneCredential = credential as? PhoneAuthCredential {
            return try await self.link(withPhoneCredential: phoneCredential)
        }
#endif
        
        let user = try await self.taskQueue.enqueue {
            let accessToken = try await self.internalGetToken()
            guard let requestConfiguration = self.auth?.requestConfiguration else {
                fatalError("Internal Error: Unexpected nil requestConfiguration.")
            }
            var request = VerifyAssertionRequest(
                providerID: credential.provider,
                requestConfiguration: requestConfiguration
            )
            credential.prepare(&request)
            request.accessToken = accessToken
            let response: VerifyAssertionResponse
            do {
                response = try await AuthBackend.post(withRequest: request)
            } catch {
                self.signOutIfTokenIsInvalid(withError: error)
                throw error
            }
            let additionalUserInfo = AdditionalUserInfo.userInfo(verifyAssertionResponse: response)
            let updatedOAuthCredential = OAuthCredential(withVerifyAssertionResponse: response)
            let result = AuthDataResult(
                withUser: self,
                additionalUserInfo: additionalUserInfo,
                credential: updatedOAuthCredential
            )
            let updatedResult = try await self.updateTokenAndRefreshUser(
                idToken: response.idToken,
                refreshToken: response.refreshToken,
                accessToken: accessToken,
                expirationDate: response.approximateExpirationDate,
                result: result,
                requestConfiguration: requestConfiguration
            )
            return updatedResult.user
        }
        // XXX TODO: THIS IS WRONG, BUT QUEUE IS A USER QUEUE
        return AuthDataResult(withUser: user, additionalUserInfo: nil)
    }
    
    /** @fn linkWithCredential:
     @brief Associates a user account from a third-party identity provider with this user and
     returns additional identity provider data.
     
     @param credential The credential for the identity provider.
     @returns The AuthDataResult.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeProviderAlreadyLinked` - Indicates an attempt to link a provider of a
     type already linked to this account.
     + `AuthErrorCodeCredentialAlreadyInUse` - Indicates an attempt to link with a
     credential that has already been linked with a different Firebase account.
     + `AuthErrorCodeOperationNotAllowed` - Indicates that accounts with the identity
     provider represented by the credential are not enabled. Enable them in the Auth section
     of the Firebase console.
     
     @remarks This method may also return error codes associated with `updateEmail(to:)` and
     `updatePassword(to:)` on `User`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
#if os(iOS)
    /** @fn linkWithProvider:UIDelegate:completion:
     @brief link the user with the provided auth provider instance.
     This method is available on iOSonly.
     
     @param provider An instance of an auth provider used to initiate the link flow.
     @param UIDelegate Optionally an instance of a class conforming to the `AuthUIDelegate`
     protocol used for presenting the web context. If nil, a default `AuthUIDelegate`
     will be used.
     @param completion Optionally; a block which is invoked when the link flow finishes, or
     is canceled. Invoked asynchronously on the main thread in the future.
     */
    
    public func link(with provider: FederatedAuthProvider,
                     uiDelegate: AuthUIDelegate?,
                     completion: ((AuthDataResult?, Error?) -> Void)? = nil) {
        kAuthGlobalWorkQueue.async {
            provider.getCredentialWith(uiDelegate) { credential, error in
                if let error {
                    if let completion {
                        completion(nil, error)
                    }
                } else {
                    guard let credential else {
                        fatalError("Failed to get credential for link withProvider")
                    }
                    self.link(with: credential, completion: completion)
                }
            }
        }
    }
    
    /** @fn linkWithProvider:UIDelegate:
     @brief link the user with the provided auth provider instance.
     This method is available on iOS, macOS Catalyst, and tvOS only.
     
     @param provider An instance of an auth provider used to initiate the link flow.
     @param UIDelegate Optionally an instance of a class conforming to the `AuthUIDelegate`
     protocol used for presenting the web context. If nil, a default `AuthUIDelegate`
     will be used.
     @returns An AuthDataResult.
     */
    @available(iOS 13, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
    @discardableResult
    public func link(with provider: FederatedAuthProvider,
                     uiDelegate: AuthUIDelegate?) async throws -> AuthDataResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.link(with: provider, uiDelegate: uiDelegate) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else if let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
#endif
    
    /** @fn unlinkFromProvider:completion:
     @brief Disassociates a user account from a third-party identity provider with this user.
     
     @param provider The provider ID of the provider to unlink.
     @param completion Optionally; the block invoked when the unlinking is complete, or fails.
     Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeNoSuchProvider` - Indicates an attempt to unlink a provider
     that is not linked to the account.
     + `AuthErrorCodeRequiresRecentLogin` - Updating email is a security sensitive
     operation that requires a recent login from the user. This error indicates the user
     has not signed in recently enough. To resolve, reauthenticate the user by calling
     `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    public func unlink(fromProvider provider: String) async throws -> User {
        try await taskQueue.enqueue {
            let accessToken = try await self.internalGetToken()
            guard let requestConfiguration = self.auth?.requestConfiguration else {
                fatalError("Internal Error: Unexpected nil requestConfiguration.")
            }
            var request = SetAccountInfoRequest(requestConfiguration: requestConfiguration)
            request.accessToken = accessToken
            
            if self.providerDataRaw[provider] == nil {
                throw AuthErrorUtils.noSuchProviderError()
            }
            request.deleteProviders = [provider]
            let response: SetAccountInfoResponse
            do {
                response = try await AuthBackend.post(withRequest: request)
            } catch {
                self.signOutIfTokenIsInvalid(withError: error)
                throw error
            }
            // We can't just use the provider info objects in FIRSetAccountInfoResponse
            // because they don't have localID and email fields. Remove the specific
            // provider manually.
            self.userdata.providerDataRaw.removeValue(forKey: provider)
            if provider == EmailAuthProvider.id {
                self.userdata.hasEmailPasswordCredential = false
            }
#if os(iOS)
            // After successfully unlinking a phone auth provider, remove the phone number
            // from the cached user info.
            if provider == PhoneAuthProvider.id {
                self.phoneNumber = nil
            }
#endif
            if let idToken = response.idToken,
               let refreshToken = response.refreshToken {
                let tokenService = SecureTokenService(
                    withRequestConfiguration: requestConfiguration,
                    accessToken: idToken,
                    accessTokenExpirationDate: response
                        .approximateExpirationDate,
                    refreshToken: refreshToken
                )
                try await self.setTokenService(tokenService: tokenService)
            }
            try self.updateKeychain()
            return self
        }
    }
    
    /** @fn unlinkFromProvider:
     @brief Disassociates a user account from a third-party identity provider with this user.
     
     @param provider The provider ID of the provider to unlink.
     @returns The user.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeNoSuchProvider` - Indicates an attempt to unlink a provider
     that is not linked to the account.
     + `AuthErrorCodeRequiresRecentLogin` - Updating email is a security sensitive
     operation that requires a recent login from the user. This error indicates the user
     has not signed in recently enough. To resolve, reauthenticate the user by calling
     `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    
    /** @fn sendEmailVerificationWithCompletion:
     @brief Initiates email verification for the user.
     
     @param completion Optionally; the block invoked when the request to send an email verification
     is complete, or fails. Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
     sent in the request.
     + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
     the console for this action.
     + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
     sending update email.
     + `AuthErrorCodeUserNotFound` - Indicates the user account was not found.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    
    /** @fn sendEmailVerificationWithActionCodeSettings:completion:
     @brief Initiates email verification for the user.
     
     @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
     handling action codes.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
     sent in the request.
     + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
     the console for this action.
     + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
     sending update email.
     + `AuthErrorCodeUserNotFound` - Indicates the user account was not found.
     + `AuthErrorCodeMissingIosBundleID` - Indicates that the iOS bundle ID is missing when
     a iOS App Store ID is provided.
     + `AuthErrorCodeMissingAndroidPackageName` - Indicates that the android package name
     is missing when the `androidInstallApp` flag is set to true.
     + `AuthErrorCodeUnauthorizedDomain` - Indicates that the domain specified in the
     continue URL is not allowlisted in the Firebase console.
     + `AuthErrorCodeInvalidContinueURI` - Indicates that the domain specified in the
     continue URL is not valid.
     */
    
    public func sendEmailVerification(with actionCodeSettings: ActionCodeSettings? = nil) async throws  {
        let accessToken = try await self.internalGetToken()
        guard let requestConfiguration = self.auth?.requestConfiguration else {
            fatalError("Internal Error: Unexpected nil requestConfiguration.")
        }
        let request = GetOOBConfirmationCodeRequest.verifyEmailRequest(
            accessToken: accessToken,
            actionCodeSettings: actionCodeSettings,
            requestConfiguration: requestConfiguration
        )
        do {
            _ = try await AuthBackend.post(withRequest: request)
        } catch {
            self.signOutIfTokenIsInvalid(withError: error)
            throw error
        }
    }
    
    /** @fn sendEmailVerificationWithActionCodeSettings:
     @brief Initiates email verification for the user.
     
     @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
     handling action codes.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeInvalidRecipientEmail` - Indicates an invalid recipient email was
     sent in the request.
     + `AuthErrorCodeInvalidSender` - Indicates an invalid sender email is set in
     the console for this action.
     + `AuthErrorCodeInvalidMessagePayload` - Indicates an invalid email template for
     sending update email.
     + `AuthErrorCodeUserNotFound` - Indicates the user account was not found.
     + `AuthErrorCodeMissingIosBundleID` - Indicates that the iOS bundle ID is missing when
     a iOS App Store ID is provided.
     + `AuthErrorCodeMissingAndroidPackageName` - Indicates that the android package name
     is missing when the `androidInstallApp` flag is set to true.
     + `AuthErrorCodeUnauthorizedDomain` - Indicates that the domain specified in the
     continue URL is not allowlisted in the Firebase console.
     + `AuthErrorCodeInvalidContinueURI` - Indicates that the domain specified in the
     continue URL is not valid.
     */
    
    /** @fn deleteWithCompletion:
     @brief Deletes the user account (also signs out the user, if this was the current user).
     
     @param completion Optionally; the block invoked when the request to delete the account is
     complete, or fails. Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeRequiresRecentLogin` - Updating email is a security sensitive
     operation that requires a recent login from the user. This error indicates the user
     has not signed in recently enough. To resolve, reauthenticate the user by calling
     `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    public func delete() async throws {
        let accessToken = try await self.internalGetToken()
        let request = DeleteAccountRequest(
            localID: self.uid,
            accessToken: accessToken,
            requestConfiguration: requestConfiguration
        )
        _ = try await AuthBackend.post(withRequest: request)
        try self.auth?.signOutByForce(withUserID: self.uid)
    }
    
    /** @fn delete
     @brief Deletes the user account (also signs out the user, if this was the current user).
     
     @param completion Optionally; the block invoked when the request to delete the account is
     complete, or fails. Invoked asynchronously on the main thread in the future.
     
     @remarks Possible error codes:
     
     + `AuthErrorCodeRequiresRecentLogin` - Updating email is a security sensitive
     operation that requires a recent login from the user. This error indicates the user
     has not signed in recently enough. To resolve, reauthenticate the user by calling
     `reauthenticate(with:)`.
     
     @remarks See `AuthErrors` for a list of error codes that are common to all `User` methods.
     */
    
    /** @fn sendEmailVerificationBeforeUpdatingEmail:completion:
     @brief Send an email to verify the ownership of the account then update to the new email.
     @param email The email to be updated to.
     @param completion Optionally; the block invoked when the request to send the verification
     email is complete, or fails.
     */
    
    public func __sendEmailVerificationBeforeUpdating(email: String) async throws {
        try await sendEmailVerification(beforeUpdatingEmail: email)
    }
    
    /** @fn sendEmailVerificationBeforeUpdatingEmail:completion:
     @brief Send an email to verify the ownership of the account then update to the new email.
     @param email The email to be updated to.
     @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
     handling action codes.
     @param completion Optionally; the block invoked when the request to send the verification
     email is complete, or fails.
     */
    public func sendEmailVerification(beforeUpdatingEmail email: String,
                                      actionCodeSettings: ActionCodeSettings? =
                                      nil) async throws {
        let accessToken = try await self.internalGetToken()
        guard let requestConfiguration = self.auth?.requestConfiguration else {
            fatalError("Internal Error: Unexpected nil requestConfiguration.")
        }
        let request = GetOOBConfirmationCodeRequest.verifyBeforeUpdateEmail(
            accessToken: accessToken,
            newEmail: email,
            actionCodeSettings: actionCodeSettings,
            requestConfiguration: requestConfiguration
        )
        _ = try await AuthBackend.post(withRequest: request)
    }
    
    /** @fn sendEmailVerificationBeforeUpdatingEmail:completion:
     @brief Send an email to verify the ownership of the account then update to the new email.
     @param email The email to be updated to.
     @param actionCodeSettings An `ActionCodeSettings` object containing settings related to
     handling action codes.
     @throws on failure.
     */
    
    public func rawAccessToken() -> String {
        tokenService.accessToken
    }
    
    public func accessTokenExpirationDate() -> Date? {
        tokenService.accessTokenExpirationDate
    }
    
    // MARK: Internal implementations below
    
    init(withTokenService tokenService: SecureTokenService) {
        self._userData = Mutex(UserData(withTokenService: tokenService))
        self.taskQueue = AuthSerialTaskQueue()
    }
    
    init(userData: UserData) {
        self._userData = Mutex(userData)
        self.taskQueue = AuthSerialTaskQueue()
    }
    
    // TODO: internal Swift
    @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
    public static func retrieveUser(withAuth auth: Auth,
                                   accessToken: String,
                                   accessTokenExpirationDate: Date?,
                                   refreshToken: String,
                                   anonymous: Bool) async throws -> User {
        let tokenService = SecureTokenService(withRequestConfiguration: auth.requestConfiguration,
                                              accessToken: accessToken,
                                              accessTokenExpirationDate: accessTokenExpirationDate,
                                              refreshToken: refreshToken)
        let user = User(withTokenService: tokenService)
        user.auth = auth
        user.tenantID = auth.tenantID
        user.requestConfiguration = auth.requestConfiguration
        let accessToken = try await user.internalGetToken()
        let getAccountInfoRequest = GetAccountInfoRequest(accessToken: accessToken,
                                                          requestConfiguration: user
            .requestConfiguration)
        let response = try await AuthBackend.post(withRequest: getAccountInfoRequest)
        
        user.userdata.isAnonymous = anonymous
        user.update(withGetAccountInfoResponse: response)
        return user
    }
    
    public var providerID: String {
        return "Firebase"
    }
    
    /** @property uid
     @brief The provider's user ID for the user.
     */
    public var uid: String {
        userdata.uid
    }
    
    /** @property displayName
     @brief The name of the user.
     */

    public var displayName: String? {
        get {
            userdata.displayName
        } set {
            userdata.displayName = newValue
        }
    }
    
    /** @property photoURL
     @brief The URL of the user's profile photo.
     */

    public var photoURL: URL? {
        get {
            userdata.photoURL
        }
        set {
            userdata.photoURL = newValue
        }
    }
    
    /** @property email
     @brief The user's email address.
     */

    public var email: String? {
        userdata.email
    }
    
    /** @property phoneNumber
     @brief A phone number associated with the user.
     @remarks This property is only available for users authenticated via phone number auth.
     */
    public var phoneNumber: String? {
        userdata.phoneNumber
    }
    
    /** @var hasEmailPasswordCredential
     @brief Whether or not the user can be authenticated by using Firebase email and password.
     */
    private var hasEmailPasswordCredential: Bool {
        userdata.hasEmailPasswordCredential
    }
    
    /** @var _taskQueue
     @brief Used to serialize the update profile calls.
     */
    private let taskQueue: AuthSerialTaskQueue<User>
    
    /** @property requestConfiguration
     @brief A strong reference to a requestConfiguration instance associated with this user instance.
     */
    // TODO: internal
    public var requestConfiguration: AuthRequestConfiguration {
        get {
            userdata.requestConfiguration
        }
        set {
            userdata.requestConfiguration = newValue
        }
    }
    
    /** @var _tokenService
     @brief A secure token service associated with this user. For performing token exchanges and
     refreshing access tokens.
     */
    // TODO: internal
    public var tokenService: SecureTokenService {
        userdata.tokenService
    }
    
    /** @property auth
     @brief A weak reference to a FIRAuth instance associated with this instance.
     */
    // TODO: internal
    private let _auth: Mutex<WeakRef<Auth>> = .init(WeakRef(nil))
    public var auth: Auth? {
        get { _auth.withLock { $0.value } }
        set { _auth.withLock { $0.value = newValue } }
    }
    
    // MARK: Private functions
    
    private func updateEmail(email: String?,
                             password: String?) async throws {
        let hadEmailPasswordCredential = hasEmailPasswordCredential
        try await executeUserUpdateWithChanges(changeBlock: { user, request in
            if let email {
                request.email = email
            }
            if let password {
                request.password = password
            }
        })
        
        guard let email else {
            try self.updateKeychain()
            return
        }
        self.userdata.email = email
        if !hadEmailPasswordCredential {
            // The list of providers need to be updated for the newly added email-password provider.
            let accessToken = try await self.internalGetToken()
            if let requestConfiguration = self.auth?.requestConfiguration {
                let getAccountInfoRequest = GetAccountInfoRequest(accessToken: accessToken,
                                                                  requestConfiguration: requestConfiguration)
                let response: GetAccountInfoResponse
                do {
                    response = try await AuthBackend.post(withRequest: getAccountInfoRequest)
                } catch {
                    self.signOutIfTokenIsInvalid(withError: error)
                    throw error
                }
                // Set the account to non-anonymous if there are any providers, even if
                // they're not email/password ones.
                if let providerUsers = response.user.providerUserInfo {
                    if providerUsers.count > 0 {
                        self.userdata.isAnonymous = false
                        for providerUserInfo in providerUsers {
                            if providerUserInfo.providerID == EmailAuthProvider.id {
                                self.userdata.hasEmailPasswordCredential = true
                                break
                            }
                        }
                    }
                }
                self.update(withGetAccountInfoResponse: response)
                try self.updateKeychain()
            }
        }
    }
    
    /** @fn executeUserUpdateWithChanges:callback:
     @brief Performs a setAccountInfo request by mutating the results of a getAccountInfo response,
     atomically in regards to other calls to this method.
     @param changeBlock A block responsible for mutating a template @c FIRSetAccountInfoRequest
     @param callback A block to invoke when the change is complete. Invoked asynchronously on the
     auth global work queue in the future.
     */
    func executeUserUpdateWithChanges(
        changeBlock: @escaping @Sendable (GetAccountInfoResponseUser?,
                                inout SetAccountInfoRequest) -> Void
    ) async throws {
        _ = try await taskQueue.enqueue {
            let user = try await self.getAccountInfoRefreshingCache()
            let accessToken = try await self.internalGetToken()
            if let configuration = self.auth?.requestConfiguration {
                // Mutate setAccountInfoRequest in block
                var setAccountInfoRequest = SetAccountInfoRequest(requestConfiguration: configuration)
                setAccountInfoRequest.accessToken = accessToken
                changeBlock(user, &setAccountInfoRequest)
                // Execute request:
                let response: SetAccountInfoResponse
                do {
                    response = try await AuthBackend.post(withRequest: setAccountInfoRequest)
                } catch {
                    self.signOutIfTokenIsInvalid(withError: error)
                    throw error
                }
                if let idToken = response.idToken,
                   let refreshToken = response.refreshToken {
                    let tokenService = SecureTokenService(
                        withRequestConfiguration: configuration,
                        accessToken: idToken,
                        accessTokenExpirationDate: response.approximateExpirationDate,
                        refreshToken: refreshToken
                    )
                    try await self.setTokenService(tokenService: tokenService)
                }
            }
            return self
        }
    }
    
    
    /** @fn setTokenService:callback:
     @brief Sets a new token service for the @c FIRUser instance.
     @param tokenService The new token service object.
     @param callback The block to be called in the global auth working queue once finished.
     @remarks The method makes sure the token service has access and refresh token and the new tokens
     are saved in the keychain before calling back.
     */
    private func setTokenService(tokenService: SecureTokenService) async throws {
        var tokenService = tokenService
        _ = try await tokenService.fetchAccessToken(forcingRefresh: false)
        self.userdata.tokenService = tokenService
        try self.updateKeychain()
    }
    
    /** @fn getAccountInfoRefreshingCache:
     @brief Gets the users's account data from the server, updating our local values.
     @param callback Invoked when the request to getAccountInfo has completed, or when an error has
     been detected. Invoked asynchronously on the auth global work queue in the future.
     */
    private func getAccountInfoRefreshingCache() async throws -> GetAccountInfoResponseUser {
        let token = try await internalGetToken()
        guard let requestConfiguration = self.auth?.requestConfiguration else {
            fatalError("Internal Error: Unexpected nil requestConfiguration.")
        }
        let request = GetAccountInfoRequest(accessToken: token,
                                            requestConfiguration: requestConfiguration)
        do {
            let accountInfoResponse = try await AuthBackend.post(withRequest: request)
            self.update(withGetAccountInfoResponse: accountInfoResponse)
            try self.updateKeychain()
            return accountInfoResponse.user
            
        } catch {
            self.signOutIfTokenIsInvalid(withError: error)
            throw error
        }
    }
    
    private func update(withGetAccountInfoResponse response: GetAccountInfoResponse) {
        let user = response.user
        userdata.uid = user.localID ?? ""
        userdata.email = user.email
        userdata.isEmailVerified = user.emailVerified
        userdata.displayName = user.displayName
        userdata.photoURL = user.photoURL
        userdata.phoneNumber = user.phoneNumber
        userdata.hasEmailPasswordCredential = user.passwordHash != nil && user.passwordHash!.count > 0
        userdata.metadata = UserMetadata(withCreationDate: user.creationDate,
                                lastSignInDate: user.lastLoginDate)
        var providerData: [String: UserInfoImpl] = [:]
        if let providerUserInfos = user.providerUserInfo {
            for providerUserInfo in providerUserInfos {
                let userInfo = UserInfoImpl.userInfo(withGetAccountInfoResponseProviderUserInfo:
                                                        providerUserInfo)
                if let providerID = providerUserInfo.providerID {
                    providerData[providerID] = userInfo
                }
            }
        }
        userdata.providerDataRaw = providerData
#if os(iOS)
        if let enrollments = user.mfaEnrollments {
            userdata.multiFactor = MultiFactor(withMFAEnrollments: enrollments)
        }
        userdata.multiFactor.user = self
#endif
    }
    
#if os(iOS)
    /** @fn internalUpdateOrLinkPhoneNumber
     @brief Updates the phone number for the user. On success, the cached user profile data is
     updated.
     
     @param phoneAuthCredential The new phone number credential corresponding to the phone number
     to be added to the Firebase account, if a phone number is already linked to the account this
     new phone number will replace it.
     @param isLinkOperation Boolean value indicating whether or not this is a link operation.
     @param completion Optionally; the block invoked when the user profile change has finished.
     Invoked asynchronously on the global work queue in the future.
     */
    private func internalUpdateOrLinkPhoneNumber(credential: PhoneAuthCredential,
                                                 isLinkOperation: Bool,
                                                 completion: @escaping (Error?) -> Void) {
        internalGetToken { accessToken, error in
            if let error {
                completion(error)
                return
            }
            guard let accessToken = accessToken else {
                fatalError("Auth Internal Error: Both accessToken and error are nil")
            }
            guard let configuration = self.auth?.requestConfiguration else {
                fatalError("Auth Internal Error: nil value for VerifyPhoneNumberRequest initializer")
            }
            switch credential.credentialKind {
            case .phoneNumber: fatalError("Internal Error: Missing verificationCode")
            case let .verification(verificationID, code):
                let operation = isLinkOperation ? AuthOperationType.link : AuthOperationType.update
                let request = VerifyPhoneNumberRequest(verificationID: verificationID,
                                                       verificationCode: code,
                                                       operation: operation,
                                                       requestConfiguration: configuration)
                request.accessToken = accessToken
                AuthBackend.post(withRequest: request) { response, error in
                    if let error {
                        self.signOutIfTokenIsInvalid(withError: error)
                        completion(error)
                        return
                    }
                    // Update the new token and refresh user info again.
                    if let verifyResponse = response as? VerifyPhoneNumberResponse {
                        if let idToken = verifyResponse.idToken,
                           let refreshToken = verifyResponse.refreshToken {
                            self.tokenService = SecureTokenService(
                                withRequestConfiguration: configuration,
                                accessToken: idToken,
                                accessTokenExpirationDate: verifyResponse.approximateExpirationDate,
                                refreshToken: refreshToken
                            )
                        }
                    }
                    // Get account info to update cached user info.
                    self.getAccountInfoRefreshingCache { user, error in
                        if let error {
                            self.signOutIfTokenIsInvalid(withError: error)
                            completion(error)
                            return
                        }
                        self.isAnonymous = false
                        if let error = self.updateKeychain() {
                            completion(error)
                            return
                        }
                        completion(nil)
                    }
                }
            }
        }
    }
#endif
    
    private func link(withEmailCredential emailCredential: EmailAuthCredential) async throws -> AuthDataResult {
        if hasEmailPasswordCredential {
            throw AuthErrorUtils
                .providerAlreadyLinkedError()
        }
        switch emailCredential.emailType {
        case let .password(password):
            try await updateEmail(email: emailCredential.email, password: password)
            return AuthDataResult(withUser: self, additionalUserInfo: nil)
            
        case let .link(link):
            let accessToken = try await internalGetToken()
            var queryItems = AuthWebUtils.parseURL(link)
            if link.count == 0 {
                if let urlComponents = URLComponents(string: link),
                   let query = urlComponents.query {
                    queryItems = AuthWebUtils.parseURL(query)
                }
            }
            guard let actionCode = queryItems["oobCode"],
                  let requestConfiguration = self.auth?.requestConfiguration else {
                fatalError("Internal Auth Error: Missing oobCode or requestConfiguration")
            }
            var request = EmailLinkSignInRequest(email: emailCredential.email,
                                                 oobCode: actionCode,
                                                 requestConfiguration: requestConfiguration)
            request.idToken = accessToken
            let response = try await AuthBackend.post(withRequest: request)
            let result = try await self.updateTokenAndRefreshUser(
                idToken: response.idToken,
                refreshToken: response.refreshToken,
                accessToken: accessToken,
                expirationDate: response.approximateExpirationDate,
                result: AuthDataResult(
                    withUser: self,
                    additionalUserInfo: nil
                ),
                requestConfiguration: requestConfiguration
            )
            return result
        }
    }


#if os(macOS) || os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    private func link(withGameCenterCredential gameCenterCredential: GameCenterAuthCredential) async throws -> AuthDataResult {
        let accessToken = try await internalGetToken()
        guard let requestConfiguration = self.auth?.requestConfiguration,
              let publicKeyURL = gameCenterCredential.publicKeyURL,
              let signature = gameCenterCredential.signature,
              let salt = gameCenterCredential.salt else {
            fatalError("Internal Auth Error: Nil value field for SignInWithGameCenterRequest")
        }
        var request = SignInWithGameCenterRequest(
            playerID: gameCenterCredential.playerID,
            teamPlayerID: gameCenterCredential.teamPlayerID,
            gamePlayerID: gameCenterCredential.gamePlayerID,
            publicKeyURL: publicKeyURL,
            signature: signature,
            salt: salt,
            timestamp: gameCenterCredential.timestamp,
            displayName: gameCenterCredential.displayName,
            requestConfiguration: requestConfiguration
        )
        request.accessToken = accessToken
        let response = try await AuthBackend.post(withRequest: request)
        let result = try await self.updateTokenAndRefreshUser(
            idToken: response.idToken,
            refreshToken: response.refreshToken,
            accessToken: accessToken,
            expirationDate: response.approximateExpirationDate,
            result: AuthDataResult(
                withUser: self,
                additionalUserInfo: nil
            ),
            requestConfiguration: requestConfiguration
        )
        return result
    }
  #endif

  #if os(iOS)
    private func link(withPhoneCredential phoneCredential: PhoneAuthCredential,
                      completion: ((AuthDataResult?, Error?) -> Void)?) {
      internalUpdateOrLinkPhoneNumber(credential: phoneCredential,
                                      isLinkOperation: true) { error in
        if let error {
          User.callInMainThreadWithAuthDataResultAndError(
            callback: completion,
            result: nil,
            error: error
          )
        } else {
          let result = AuthDataResult(withUser: self, additionalUserInfo: nil)
          User.callInMainThreadWithAuthDataResultAndError(
            callback: completion,
            result: result,
            error: nil
          )
        }
      }
    }
  #endif

  // Update the new token and refresh user info again.
  private func updateTokenAndRefreshUser(idToken: String, refreshToken: String,
                                         accessToken: String,
                                         expirationDate: Date?,
                                         result: AuthDataResult,
                                         requestConfiguration: AuthRequestConfiguration
                                         ) async throws -> AuthDataResult {
      userdata.tokenService = SecureTokenService(
        withRequestConfiguration: requestConfiguration,
        accessToken: idToken,
        accessTokenExpirationDate: expirationDate,
        refreshToken: refreshToken
      )
      _ = try await internalGetToken()
      let getAccountInfoRequest = GetAccountInfoRequest(accessToken: accessToken,
                                                        requestConfiguration: requestConfiguration)
      let response: GetAccountInfoResponse
      do {
          response = try await AuthBackend.post(withRequest: getAccountInfoRequest)
      } catch {
          self.signOutIfTokenIsInvalid(withError: error)
          throw error
      }
      self.userdata.isAnonymous = false
      self.update(withGetAccountInfoResponse: response)
      try self.updateKeychain()
      return result
  }

  /** @fn signOutIfTokenIsInvalidWithError:
      @brief Signs out this user if the user or the token is invalid.
      @param error The error from the server.
   */
  private func signOutIfTokenIsInvalid(withError error: Error) {
    let code = (error as NSError).code
    if code == AuthErrorCode.userNotFound.rawValue ||
      code == AuthErrorCode.userDisabled.rawValue ||
      code == AuthErrorCode.invalidUserToken.rawValue ||
      code == AuthErrorCode.userTokenExpired.rawValue {
      AuthLog.logNotice(code: "I-AUT000016",
                        message: "Invalid user token detected, user is automatically signed out.")
      try? auth?.signOutByForce(withUserID: uid)
    }
  }

  /** @fn internalGetToken
      @brief Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
      @param callback The block to invoke when the token is available. Invoked asynchronously on the
          global work thread in the future.
   */
  // TODO: internal
  
    public func internalGetToken(forceRefresh: Bool = false) async throws -> String {
        do {
            let (token, tokenUpdated) = try await userdata.tokenService.fetchAccessToken(forcingRefresh: forceRefresh)
            print("internalGetToken: \(token) \(tokenUpdated)")
            if tokenUpdated {
                try self.updateKeychain()
            }
            return token
            
        } catch {
            self.signOutIfTokenIsInvalid(withError: error)
            throw error
        }
    }

  /** @fn updateKeychain:
      @brief Updates the keychain for user token or info changes.
      @param error The error if NO is returned.
      @return Whether the operation is successful.
   */
  func updateKeychain() throws {
      try auth?.updateKeychain(withUser: self)
  }
  
}

struct UserData: Codable, Equatable, Sendable {
    var isAnonymous: Bool
    var uid: String
    var displayName: String?
    var photoURL: URL?
    var email: String?
    var phoneNumber: String?
    var hasEmailPasswordCredential: Bool
    var providerDataRaw: [String: UserInfoImpl]
    var isEmailVerified: Bool
    var metadata: UserMetadata
    var tenantID: String?
    var tokenService: SecureTokenService
    var requestConfiguration: AuthRequestConfiguration

    /** @var _taskQueue
     @brief Used to serialize the update profile calls.
     */

    enum CodingKeys: String, CodingKey {
        case tenantID, uid, isAnonymous, hasEmailPasswordCredential, providerData, email, phoneNumber, isEmailVerified, photoURL, displayName, metadata, APIKey, appID, tokenService, multiFactor
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(uid, forKey: .uid)
        try container.encode(isAnonymous, forKey: .isAnonymous)
        try container.encode(hasEmailPasswordCredential, forKey: .hasEmailPasswordCredential)
        try container.encode(providerDataRaw, forKey: .providerData)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encode(isEmailVerified, forKey: .isEmailVerified)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(tenantID, forKey: .tenantID)
//        if let auth {
//            try container.encode(auth.requestConfiguration.apiKey, forKey: .APIKey)
//            try container.encode(auth.requestConfiguration.appID, forKey: .appID)
//        }
        try container.encode(tokenService, forKey: .tokenService)
#if os(iOS)
        try container.encode(multiFactor, forKey: .multiFactor)
#endif
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.uid = try container.decode(String.self, forKey: .uid)
        
        let apiKey = try container.decode(String.self, forKey: .APIKey)
        let appID = try container.decode(
            String.self,
            forKey: .appID
        )
        self.tokenService = try container.decode(SecureTokenService.self, forKey: .tokenService)
        self.isAnonymous = try container.decode(Bool.self, forKey: .isAnonymous)
        self.hasEmailPasswordCredential = try container.decode(Bool.self, forKey: .hasEmailPasswordCredential)
        self.displayName = try container.decodeIfPresent(String.self,
                                                         forKey: .displayName
        )
        self.photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.phoneNumber = try container.decodeIfPresent(String.self,
                                                         forKey: .phoneNumber
        )
        self.isEmailVerified = try container.decode(Bool.self, forKey: .isEmailVerified)
        self.providerDataRaw = try container.decodeIfPresent([String: UserInfoImpl].self, forKey: .providerData) ?? [:]
        self.metadata = try container.decodeIfPresent(UserMetadata.self, forKey: .metadata) ?? UserMetadata(withCreationDate: nil, lastSignInDate: nil)
        self.tenantID = try container.decodeIfPresent(String.self, forKey: .tenantID)
        // The `heartbeatLogger` and `appCheck` will be set later via a property update.
        self.requestConfiguration = AuthRequestConfiguration(apiKey: apiKey, appID: appID)
//        self.taskQueue = AuthSerialTaskQueue()
#if os(iOS)
        // XXX TODO: Is this correct?
        let multiFactor = MultiFactor()
        self.multiFactor = multiFactor
        multiFactor.user = self
#endif
    }

    init(withTokenService tokenService: SecureTokenService) {
        providerDataRaw = [:]
        self.tokenService = tokenService
        isAnonymous = false
        isEmailVerified = false
        metadata = UserMetadata(withCreationDate: nil, lastSignInDate: nil)
        tenantID = nil
#if os(iOS)
        multiFactor = MultiFactor(withMFAEnrollments: [])
#endif
        uid = ""
        hasEmailPasswordCredential = false
        requestConfiguration = AuthRequestConfiguration(apiKey: "", appID: "")
    }
}
