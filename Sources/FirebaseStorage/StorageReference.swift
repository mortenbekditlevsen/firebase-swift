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

/// `StorageReference` represents a reference to a Google Cloud Storage object. Developers can
/// upload and download objects, as well as get/set object metadata, and delete an object at the
/// path. See the [Cloud docs](https://cloud.google.com/storage/)  for more details.
public struct StorageReference: Sendable {
    // MARK: - Public APIs
    
    /// The `Storage` service object which created this reference.
    public let storage: Storage
    
    /// The name of the Google Cloud Storage bucket associated with this reference.
    /// For example, in `gs://bucket/path/to/object.txt`, the bucket would be 'bucket'.
    public var bucket: String {
        path.bucket
    }
    
    /// The full path to this object, not including the Google Cloud Storage bucket.
    /// In `gs://bucket/path/to/object.txt`, the full path would be: `path/to/object.txt`.
    public var fullPath: String {
        path.object ?? ""
    }
    
    /// The short name of the object associated with this reference.
    ///
    /// In `gs://bucket/path/to/object.txt`, the name of the object would be `object.txt`.
    public var name: String {
        (path.object as? NSString)?.lastPathComponent ?? ""
    }
    
    /// Creates a new `StorageReference` pointing to the root object.
    /// - Returns: A new `StorageReference` pointing to the root object.
    public func root() -> StorageReference {
        StorageReference(storage: storage, path: path.root())
    }
    
    /// Creates a new `StorageReference` pointing to the parent of the current reference
    /// or `nil` if this instance references the root location.
    /// ```
    /// For example:
    ///     path = foo/bar/baz   parent = foo/bar
    ///     path = foo           parent = (root)
    ///     path = (root)        parent = nil
    /// ```
    /// - Returns: A new `StorageReference` pointing to the parent of the current reference.
    public func parent() -> StorageReference? {
        guard let parentPath = path.parent() else {
            return nil
        }
        return StorageReference(storage: storage, path: parentPath)
    }
    
    /// Creates a new `StorageReference` pointing to a child object of the current reference.
    /// ```
    ///     path = foo      child = bar    newPath = foo/bar
    ///     path = foo/bar  child = baz    ntask.impl.snapshotwPath = foo/bar/baz
    /// All leading and trailing slashes will be removed, and consecutive slashes will be
    /// compressed to single slashes. For example:
    ///     child = /foo/bar     newPath = foo/bar
    ///     child = foo/bar/     newPath = foo/bar
    ///     child = foo///bar    newPath = foo/bar
    /// ```
    ///
    /// - Parameter path: The path to append to the current path.
    /// - Returns: A new `StorageReference` pointing to a child location of the current reference.
    public func child(_ path: String) -> StorageReference {
        StorageReference(storage: storage, path: self.path.child(path))
    }
    
    // MARK: - Uploads
    
    /// Asynchronously uploads data to the currently specified `StorageReference`,
    /// without additional metadata.
    /// This is not recommended for large files, and one should instead upload a file from disk.
    /// - Parameters:
    ///   - uploadData: The data to upload.
    ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
    ///       about the object being uploaded.
    /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage the
    /// upload.
    @discardableResult
    public func putData(_ uploadData: Data, metadata: StorageMetadata? = nil) -> StorageUploadTask {
        return putDataTask(uploadData, metadata: metadata)
    }
       
    internal func putDataTask(_ uploadData: Data,
                        metadata: StorageMetadata? = nil) -> StorageUploadTask {
        var putMetadata = metadata ?? StorageMetadata()
        if let path = path.object {
            putMetadata.path = path
            putMetadata.name = (path as NSString).lastPathComponent as String
        }
        let task = StorageUploadTask(reference: self,
                                     data: uploadData,
                                     metadata: putMetadata)

        task.enqueue()
        return task
    }

    /// Asynchronously uploads data to the currently specified `StorageReference`.
    /// This is not recommended for large files, and one should instead upload a file from disk.
    /// - Parameters:
    ///   - uploadData: The data to upload.
    ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
    ///       about the object being uploaded.
    ///   - completion: A closure that either returns the object metadata on success,
    ///       or an error on failure.
    /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage the
    /// upload.
    @discardableResult
    public func putData(_ uploadData: Data,
                        metadata: StorageMetadata? = nil) async throws -> StorageMetadata {
        var putMetadata = metadata ?? StorageMetadata()
        if let path = path.object {
            putMetadata.path = path
            putMetadata.name = (path as NSString).lastPathComponent as String
        }
        let task = StorageUploadTask(reference: self,
                                     data: uploadData,
                                     metadata: putMetadata)
        return try await task.enqueueAsync()
    }
    
    /// Asynchronously uploads a file to the currently specified `StorageReference`.
    /// - Parameters:
    ///   - fileURL: A URL representing the system file path of the object to be uploaded.
    ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
    ///       about the object being uploaded.
    /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage the
    /// upload.
    @discardableResult
    public func putFile(from fileURL: URL, metadata: StorageMetadata? = nil) -> StorageUploadTask {
        putFileTask(from: fileURL, metadata: metadata)
    }
    
    /// Asynchronously uploads a file to the currently specified `StorageReference`.
    /// - Parameters:
    ///   - fileURL: A URL representing the system file path of the object to be uploaded.
    ///   - metadata: `StorageMetadata` containing additional information (MIME type, etc.)
    ///       about the object being uploaded.
    ///   - completion: A completion block that either returns the object metadata on success,
    ///       or an error on failure.
    /// - Returns: An instance of `StorageUploadTask`, which can be used to monitor or manage the
    /// upload.
    @discardableResult
    public func putFile(from fileURL: URL,
                        metadata: StorageMetadata? = nil) async throws -> StorageMetadata {
        var putMetadata: StorageMetadata = metadata ?? StorageMetadata()
        if let path = path.object {
            putMetadata.path = path
            putMetadata.name = (path as NSString).lastPathComponent as String
        }
        let task = StorageUploadTask(reference: self,
                                     file: fileURL,
                                     metadata: putMetadata)
        return try await task.enqueueAsync()
    }
    
    internal func putFileTask(from fileURL: URL,
                        metadata: StorageMetadata? = nil) -> StorageUploadTask {
        var putMetadata: StorageMetadata = metadata ?? StorageMetadata()
        if let path = path.object {
            putMetadata.path = path
            putMetadata.name = (path as NSString).lastPathComponent as String
        }
        let task = StorageUploadTask(reference: self,
                                     file: fileURL,
                                     metadata: putMetadata)
        task.enqueue()
        return task
    }

    
    // MARK: - Downloads
    
    /// Asynchronously downloads the object at the `StorageReference` to a `Data` instance in memory.
    /// A `Data` buffer of the provided max size will be allocated, so ensure that the device has
    /// enough free
    /// memory to complete the download. For downloading large files, `write(toFile:)` may be a better
    /// option.
    /// - Parameters:
    ///   - maxSize: The maximum size in bytes to download. If the download exceeds this size,
    ///       the task will be cancelled and an error will be returned.
    ///   - completion: A completion block that either returns the object data on success,
    ///       or an error on failure.
    /// - Returns: A `StorageDownloadTask` that can be used to monitor or manage the download.
    @discardableResult
    public func getData(maxSize: Int64) async throws -> Data {
        let task = StorageDownloadTask(reference: self,
                                       file: nil)
        
        Task { @StorageActor in
            // It is ok to implicitly ignore errors here, since the
            // same errors are surfaced in the task.start() below
            let (_, stream) = await task.observe()
            for try await snapshot in stream {
                guard case .progress = snapshot.status else {
                    continue
                }
                if let error = self.checkSizeOverflow(progress: snapshot.base.progress, maxSize: maxSize) {
                    task.cancel(withError: error)
                }
            }
        }

        let data = try await task.start()
        let progress = await task.observer.base.progress
        if let error = self.checkSizeOverflow(
            progress: progress,
            maxSize: maxSize
        ) {
            throw error
        }

        return data
    }
    
    /// Asynchronously retrieves a long lived download URL with a revokable token.
    /// This can be used to share the file with others, but can be revoked by a developer
    /// in the Firebase Console.
    /// - Throws: An error if the download URL could not be retrieved.
    /// - Returns: The URL on success.
    public func downloadURL() async throws -> URL {
        try await StorageGetDownloadURLTask.getDownloadURLTask(reference: self)
    }
    
    /// Asynchronously downloads the object at the current path to a specified system filepath.
    /// - Parameter fileURL: A file system URL representing the path the object should be downloaded
    /// to.
    /// - Returns A `StorageDownloadTask` that can be used to monitor or manage the download.
    @discardableResult
    public func write(toFile fileURL: URL) -> StorageDownloadTask {
        let task = StorageDownloadTask(reference: self,
                                       file: fileURL)
        task.enqueue()
        return task
    }
    
    /// Asynchronously downloads the object at the current path to a specified system filepath.
    /// - Parameters:
    ///   - fileURL: A file system URL representing the path the object should be downloaded to.
    ///   - completion: A closure that fires when the file download completes, passed either
    ///       a URL pointing to the file path of the downloaded file on success,
    ///       or an error on failure.
    /// - Returns: A `StorageDownloadTask` that can be used to monitor or manage the download.
    @discardableResult
    public func write(toFile fileURL: URL) async throws -> URL {
        let task = StorageDownloadTask(reference: self,
                                       file: fileURL)
        _ = try await task.start()
        return fileURL
    }
    
    // MARK: - List Support
    
    /// Lists all items (files) and prefixes (folders) under this StorageReference.
    /// This is a helper method for calling list() repeatedly until there are no more results.
    /// Consistency of the result is not guaranteed if objects are inserted or removed while this
    /// operation is executing. All results are buffered in memory.
    /// `listAll()` is only available for projects using Firebase Rules Version 2.
    /// - Throws: An error if the list operation failed.
    /// - Returns: All items and prefixes under the current `StorageReference`.
    public func listAll() async throws -> StorageListResult {
        var prefixes = [StorageReference]()
        var items = [StorageReference]()
        
        var pageToken: String? = nil
        while true {
            let result = try await StorageListTask.listTask(
                reference: self,
                pageSize: nil,
                previousPageToken: pageToken
            )
            prefixes.append(contentsOf: result.prefixes)
            items.append(contentsOf: result.items)
            pageToken = result.pageToken
            if pageToken == nil {
                let result = StorageListResult(withPrefixes: prefixes, items: items, pageToken: nil)
                return result
            }
        }
        
    }
    
    /// List up to `maxResults` items (files) and prefixes (folders) under this StorageReference.
    ///
    /// "/" is treated as a path delimiter. Firebase Storage does not support unsupported object
    /// paths that end with "/" or contain two consecutive "/"s. All invalid objects in GCS will be
    /// filtered.
    ///
    /// Only available for projects using Firebase Rules Version 2.
    ///
    /// - Parameters:
    ///   - maxResults: The maximum number of results to return in a single page. Must be
    ///                greater than 0 and at most 1000.
    /// - Throws: An error if the operation failed, for example if Storage was unreachable
    ///   or the storage reference referenced an invalid path.
    /// - Returns: A `StorageListResult` containing the contents of the storage reference.
    public func list(maxResults: Int64) async throws -> StorageListResult {
        if maxResults <= 0 || maxResults > 1000 {
            throw StorageError.invalidArgument(
                message: "Argument 'maxResults' must be between 1 and 1000 inclusive."
            )
        } else {
            return try await StorageListTask.listTask(reference: self,
                                                      pageSize: maxResults,
                                                      previousPageToken: nil)
        }
    }

    /// List up to `maxResults` items (files) and prefixes (folders) under this StorageReference.
    ///
    /// "/" is treated as a path delimiter. Firebase Storage does not support unsupported object
    /// paths that end with "/" or contain two consecutive "/"s. All invalid objects in GCS will be
    /// filtered.
    ///
    /// Only available for projects using Firebase Rules Version 2.
    ///
    /// - Parameters:
    ///   - maxResults: The maximum number of results to return in a single page. Must be
    ///                greater than 0 and at most 1000.
    ///   - pageToken: A page token from a previous call to list.
    /// - Throws:
    ///   - An error if the operation failed, for example if Storage was unreachable
    ///   or the storage reference referenced an invalid path.
    /// - Returns:
    ///   - completion A `Result` enum with either the list or an `Error`.
    public func list(maxResults: Int64,
                 pageToken: String) async throws -> StorageListResult  {
    if maxResults <= 0 || maxResults > 1000 {
      throw StorageError.invalidArgument(
        message: "Argument 'maxResults' must be between 1 and 1000 inclusive."
      )
    } else {
      return try await StorageListTask.listTask(reference: self,
                               pageSize: maxResults,
                               previousPageToken: pageToken)
    }
  }

  // MARK: - Metadata Operations

    /// Retrieves metadata associated with an object at the current path.
    /// - Throws: An error if the object metadata could not be retrieved.
    /// - Returns: The object metadata on success.
    public func getMetadata() async throws -> StorageMetadata {
        try await StorageGetMetadataTask.getMetadataTask(reference: self)
    }


    /// Updates the metadata associated with an object at the current path.
    /// - Parameter metadata: A `StorageMetadata` object with the metadata to update.
    /// - Throws: An error if the metadata update operation failed.
    /// - Returns: The object metadata on success.
    public func updateMetadata(_ metadata: StorageMetadata) async throws -> StorageMetadata {
        try await StorageUpdateMetadataTask.updateMetadataTask(reference: self,
                                                 metadata: metadata)
  }


  // MARK: - Delete

    /// Deletes the object at the current path.
    /// - Throws: An error if the delete operation failed.
    public func delete() async throws {
    _ = try await StorageDeleteTask.deleteTask(
        reference: self
    )
  }

    public var description: String {
        return "gs://\(path.bucket)/\(path.object ?? "")"
    }

  // MARK: - Internal APIs

  /// The current path which points to an object in the Google Cloud Storage bucket.
  let path: StoragePath

    init() {
    storage = Storage.storage()
    let storageBucket = storage.app.options.storageBucket!
    path = StoragePath(with: storageBucket)
  }

  init(storage: Storage, path: StoragePath) {
    self.storage = storage
    self.path = path
  }

  /// For maxSize API, return an error if the size is exceeded.
  private func checkSizeOverflow(progress: Progress, maxSize: Int64) -> NSError? {
    if progress.totalUnitCount > maxSize || progress.completedUnitCount > maxSize {
      return StorageError.downloadSizeExceeded(
        total: progress.totalUnitCount,
        maxSize: maxSize
      ) as NSError
    }
    return nil
  }
}
