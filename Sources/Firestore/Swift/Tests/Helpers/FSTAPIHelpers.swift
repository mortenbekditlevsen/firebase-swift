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

// Swift replacements for the ObjC helpers in Example/Tests/API/FSTAPIHelpers.h.

import FirebaseCore
import FirebaseFirestore

/// A Firestore instance for tests. Its client is created lazily, so building
/// references never touches the network.
let FSTTestFirestore: Firestore = {
  let options = FirebaseApp.Options(
    projectID: "test-project",
    googleAppID: "1:123:ios:123ab",
    apiKey: nil,
    clientID: nil,
    storageBucket: nil
  )
  return Firestore.firestore(app: FirebaseApp(options: options, name: "FSTTestFirestore"))
}()

func FSTTestDocRef(_ path: String) -> DocumentReference {
  FSTTestFirestore.document(path)
}
