// Copyright 2022 Google LLC
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

/// Task which provides the ability to delete an object in Firebase Storage.
enum StorageGetMetadataTask {
    @StorageActor
  static func getMetadataTask(reference: StorageReference) async throws -> StorageMetadata {
      let task = StorageInternalTask(reference: reference)
      let data = try await task.start(httpMethod: "GET",
                                      fetcherComment: "GetMetadataTask")
      if let responseDictionary = try? JSONSerialization.jsonObject(with: data) as? [String: AnyHashable] {
          var metadata = StorageMetadata(dictionary: responseDictionary)
          metadata.fileType = .file
          return metadata
      } else {
          throw StorageErrorCode.error(withInvalidRequest: data)
      }
  }
}
