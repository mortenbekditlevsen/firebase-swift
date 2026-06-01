// Copyright 2021 Google LLC
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

public extension StorageReference {
  /// Asynchronously uploads data to the currently specified StorageReference.
  /// This is not recommended for large files, and one should instead upload a file from disk
  /// from the Firebase Console.
  ///
  /// - Parameters:
  ///   - uploadData: The Data to upload.
  ///   - metadata: Optional StorageMetadata containing additional information (MIME type, etc.)
  ///              about the object being uploaded.
  ///   - onProgress: An optional closure function to return a `Progress` instance while the
  /// upload proceeds.
  /// - Throws: An error if the operation failed, for example if Storage was unreachable.
  /// - Returns: StorageMetadata with additional information about the object being uploaded.
    func putDataStream(
        _ uploadData: Data,
        metadata: StorageMetadata? = nil
    ) async -> AsyncThrowingStream<StorageTaskSnapshot<StorageMetadata>, Error> {
        let uploadTask = putDataTask(uploadData, metadata: metadata)
        let (_, stream) = await uploadTask.observe()
        return stream
    }


  /// Asynchronously downloads the object at the current path to a specified system filepath.
  ///
  /// - Parameters:
  ///   - fileURL: A URL representing the system file path of the object to be uploaded.
  ///   - onProgress: An optional closure function to return a `Progress` instance while the
  /// download proceeds.
  /// - Throws: An error if the operation failed, for example if Storage was unreachable
  ///   or `fileURL` did not reference a valid path on disk.
  /// - Returns: A `URL` pointing to the file path of the downloaded file.
    func writeStream(
        toFile fileURL: URL
    ) async -> AsyncThrowingStream<StorageTaskSnapshot<Data>, Error> {
      let downloadTask: StorageDownloadTask = write(toFile: fileURL)
      let (_, stream) = await downloadTask.observe()
      return stream
  }
}
