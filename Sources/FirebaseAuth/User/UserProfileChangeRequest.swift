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

/** @class UserProfileChangeRequest
    @brief Represents an object capable of updating a user's profile data.
    @remarks Properties are marked as being part of a profile update when they are set. Setting a
        property value to nil is not the same as leaving the property unassigned.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
public final class UserProfileChangeRequest: Sendable {
  private struct State {
    var displayName: String?
    var displayNameWasSet = false
    var photoURL: URL?
    var photoURLWasSet = false
    var consumed = false
  }

  private let user: User
  private let _state = Mutex(State())

  /** @property displayName
   @brief The name of the user.
   */
  public var displayName: String? {
    get { _state.withLock { $0.displayName } }
    set {
      _state.withLock { state in
        if state.consumed {
          fatalError("Internal Auth Error: Invalid call to setDisplayName after commitChanges.")
        }
        state.displayNameWasSet = true
        state.displayName = newValue
      }
    }
  }

  /** @property photoURL
   @brief The URL of the user's profile photo.
   */
  public var photoURL: URL? {
    get { _state.withLock { $0.photoURL } }
    set {
      _state.withLock { state in
        if state.consumed {
          fatalError("Internal Auth Error: Invalid call to setPhotoURL after commitChanges.")
        }
        state.photoURLWasSet = true
        state.photoURL = newValue
      }
    }
  }

  /** @fn commitChanges
   @brief Commits any pending changes.
   @remarks This method should only be called once. Once called, property values should not be
   changed.

   @throws on error.
   */
  @MainActor
  public func commitChanges() async throws {
    let changes = _state.withLock { state -> State in
      if state.consumed {
        fatalError("Internal Auth Error: commitChanges should only be called once.")
      }
      state.consumed = true
      return state
    }
    // Return fast if there is nothing to update:
    if !changes.photoURLWasSet, !changes.displayNameWasSet {
      return
    }

    try await user.executeUserUpdateWithChanges(changeBlock: { user, request in
      if changes.photoURLWasSet {
        request.photoURL = changes.photoURL
      }
      if changes.displayNameWasSet {
        request.displayName = changes.displayName
      }
    })

    if changes.displayNameWasSet {
      user.displayName = changes.displayName
    }
    if changes.photoURLWasSet {
      user.photoURL = changes.photoURL
    }
    try user.updateKeychain()
  }

  init(_ user: User) {
    self.user = user
  }
}
