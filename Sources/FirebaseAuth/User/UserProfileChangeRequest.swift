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

/** @class UserProfileChangeRequest
    @brief Represents an object capable of updating a user's profile data.
    @remarks Properties are marked as being part of a profile update when they are set. Setting a
        property value to nil is not the same as leaving the property unassigned.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public class UserProfileChangeRequest {
  /** @property displayName
   @brief The name of the user.
   */
  public var displayName: String? {
    get { _displayName }
    set {
      kAuthGlobalWorkQueue.async {
        if self.consumed {
          fatalError("Internal Auth Error: Invalid call to setDisplayName after commitChanges.")
        }
        self.displayNameWasSet = true
        self._displayName = newValue
      }
    }
  }

  private var _displayName: String?

  /** @property photoURL
   @brief The URL of the user's profile photo.
   */
  public var photoURL: URL? {
    get { return _photoURL }
    set(newPhotoURL) {
      kAuthGlobalWorkQueue.async {
        if self.consumed {
          fatalError("Internal Auth Error: Invalid call to setPhotoURL after commitChanges.")
        }
        self.photoURLWasSet = true
        self._photoURL = newPhotoURL
      }
    }
  }

  private var _photoURL: URL?

  /** @fn commitChangesWithCompletion:
   @brief Commits any pending changes.
   @remarks This method should only be called once. Once called, property values should not be
   changed.

   @param completion Optionally; the block invoked when the user profile change has been applied.
   Invoked asynchronously on the main thread in the future.
   */
     @MainActor
     public func commitChanges() async throws  {
         if self.consumed {
             fatalError("Internal Auth Error: commitChanges should only be called once.")
         }
         self.consumed = true
         // Return fast if there is nothing to update:
         if !self.photoURLWasSet, !self.displayNameWasSet {
             return
         }
         let displayName = self.displayName
         let displayNameWasSet = self.displayNameWasSet
         let photoURL = self.photoURL
         let photoURLWasSet = self.photoURLWasSet
         
         try await self.user.executeUserUpdateWithChanges(changeBlock: { user, request in
             if photoURLWasSet {
                 request.photoURL = photoURL
             }
             if displayNameWasSet {
                 request.displayName = displayName
             }
         })
         
         if displayNameWasSet {
             self.user.displayName = displayName
         }
         if photoURLWasSet {
             self.user.photoURL = photoURL
         }
         try self.user.updateKeychain()
         
     }

  /** @fn commitChanges
   @brief Commits any pending changes.
   @remarks This method should only be called once. Once called, property values should not be
   changed.

   @throws on error.
   */

  init(_ user: User) {
    self.user = user
  }

  private let user: User
  private var consumed = false
  private var displayNameWasSet = false
  private var photoURLWasSet = false
}
