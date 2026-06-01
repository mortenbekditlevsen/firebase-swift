/// Copyright 2022 Google LLC
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

/// A Task that lists the entries under a StorageReference
enum StorageUpdateMetadataTask {
    @StorageActor
    static func updateMetadataTask(reference: StorageReference,
                                   metadata: StorageMetadata) async throws -> StorageMetadata {
        var request = StorageUtils.defaultRequestForReference(reference: reference)
        let updateData = try? JSONSerialization.data(withJSONObject: metadata.updatedMetadata())
        request.httpBody = updateData
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if let count = updateData?.count {
            request.setValue("\(count)", forHTTPHeaderField: "Content-Length")
        }
        
        let task = StorageInternalTask(reference: reference)
        let data = try await task.start(request: request,
                                        httpMethod: "PATCH",
                                        fetcherComment: "GetMetadataTask")
        if let responseDictionary = try? JSONSerialization
            .jsonObject(with: data) as? [String: AnyHashable] {
            var metadata = StorageMetadata(dictionary: responseDictionary)
            metadata.fileType = .file
            return metadata
        } else {
            throw StorageErrorCode.error(withInvalidRequest: data)
        }
    }
}
