// Copyright 2020 Google LLC
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

/// Generates a closure that returns a `Result` type from a closure that returns an optional type
/// and `Error`.
///
/// - Parameters:
///   - completion: A completion block returning a `Result` enum with either a generic object or
///                 an `Error`.
/// - Returns: A closure parameterized with an optional generic and optional `Error` to match
///            Objective-C APIs.
private func getResultCallback<T>(completion: @escaping (Result<T, Error>) -> Void) -> (_: T?,
                                                                                        _: Error?)
  -> Void {
  return { (value: T?, error: Error?) in
    if let value {
      completion(.success(value))
    } else if let error {
      completion(.failure(error))
    } else {
      completion(.failure(StorageError.internalError(
        message: "Internal failure in getResultCallback"
      )))
    }
  }
}

public extension StorageReference {
  
  /// Asynchronously downloads the object at the `StorageReference` to a `Data` object.
  ///
  /// A `Data` of the provided max size will be allocated, so ensure that the device has enough
  /// memory to complete. For downloading large files, the `write` API may be a better option.

  /// - Parameters:
  ///   - maxSize: The maximum size in bytes to download.
  ///   - completion: A completion block returning a `Result` enum with either a `Data` object or
  ///                 an `Error`.
  ///
  /// - Returns: A StorageDownloadTask that can be used to monitor or manage the download.
//  @discardableResult
//  func getData(maxSize: Int64, completion: @escaping (Result<Data, Error>) -> Void)
//    -> StorageDownloadTask {
//    return getData(maxSize: maxSize, completion: getResultCallback(completion: completion))
//  }

  /// Asynchronously uploads data to the currently specified `StorageReference`.
  /// This is not recommended for large files, and one should instead upload a file from disk.
  ///
  /// - Parameters:
  ///   - uploadData: The `Data` to upload.
  ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
  ///              about the object being uploaded.
  ///   - completion: A completion block that returns a `Result` enum with either the
  ///                object metadata or an `Error`.
  ///
  /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage
  ///            the upload.
  @discardableResult
  func putData(_ uploadData: Data,
               metadata: StorageMetadata? = nil,
               completion: @escaping (Result<StorageMetadata, Error>) -> Void)
    -> StorageUploadTask {
    return putData(uploadData,
                   metadata: metadata,
                   completion: getResultCallback(completion: completion))
  }

  /// Asynchronously uploads a file to the currently specified `StorageReference`.
  ///
  /// - Parameters:
  ///   - from: A URL representing the system file path of the object to be uploaded.
  ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
  ///              about the object being uploaded.
  ///   - completion: A completion block that returns a `Result` enum with either the
  ///                object metadata or an `Error`.
  ///
  /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage
  ///            the upload.
  @discardableResult
  func putFile(from: URL,
               metadata: StorageMetadata? = nil,
               completion: @escaping (Result<StorageMetadata, Error>) -> Void)
    -> StorageUploadTask {
    return putFile(from: from,
                   metadata: metadata,
                   completion: getResultCallback(completion: completion))
  }


  /// Asynchronously downloads the object at the current path to a specified system filepath.
  ///
  /// - Parameters:
  ///   - toFile: A file system URL representing the path the object should be downloaded to.
  ///   - completion: A completion block that fires when the file download completes. The
  ///                block returns a `Result` enum with either an NSURL pointing to the file
  ///                path of the downloaded file or an `Error`.
  ///
  /// - Returns: A `StorageDownloadTask` that can be used to monitor or manage the download.
  @discardableResult
  func write(toFile: URL, completion: @escaping (Result<URL, Error>)
    -> Void) -> StorageDownloadTask {
    return write(toFile: toFile, completion: getResultCallback(completion: completion))
  }
}
