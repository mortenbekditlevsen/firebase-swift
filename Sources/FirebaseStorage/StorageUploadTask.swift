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


/**
 * `StorageUploadTask` implements resumable uploads to a file in Firebase Storage.
 *
 * Uploads can be returned on completion with a completion callback, and can be monitored
 * by attaching observers, or controlled by calling `pause()`, `resume()`,
 * or `cancel()`.
 *
 * Uploads can be initialized from `Data` in memory, or a URL to a file on disk.
 */
public final class StorageUploadTask: StorageTaskManagement, Sendable {
    let observer: StorageObserver<StorageMetadata>
    /**
     * Prepares a task and begins execution.
     */
    public func observe() async -> (String, AsyncThrowingStream<StorageTaskSnapshot<StorageMetadata>, Error>) {
        let handle = UUID().uuidString
        let stream = await observer.observe(handle: handle)
        return (handle, stream)
    }
    
    public func enqueue() {
        Task { @StorageActor in
            do {
                let metadata = try await self.enqueueAsync()
                self.observer.fire(state: .success(metadata))
                
            } catch {
                observer.fail(with: error)
            }
        }
    }
    
    @StorageActor
    var state: StorageTaskState<StorageMetadata> {
        get { observer.base.state }
        set { observer.base.state = newValue }
    }
    
    @StorageActor
    var reference: StorageReference {
        get { observer.base.reference }
    }

    @StorageActor
    var baseRequest: URLRequest {
        get { observer.base.baseRequest }
    }

    @StorageActor
    func enqueueAsync() async throws -> StorageMetadata {
        if let contentValidationError = self.contentUploadError() {
            throw contentValidationError
        }
        
        self.state = .queueing
        
        let dataRepresentation = self.uploadMetadata.dictionaryRepresentation()
        let bodyData = try? JSONSerialization.data(withJSONObject: dataRepresentation)
        
        let fetcherService = await StorageFetcherService.shared.service(reference.storage)
        var request = self.baseRequest
        request.httpMethod = "POST"
        request.timeoutInterval = self.reference.storage.maxUploadRetryTime
        request.httpBody = bodyData
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if let count = bodyData?.count {
            request.setValue("\(count)", forHTTPHeaderField: "Content-Length")
        }
        
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        if components?.host == "www.googleapis.com",
           let path = components?.path {
            components?.percentEncodedPath = "/upload\(path)"
        }
        guard let path = self.GCSEscapedString(self.uploadMetadata.path) else {
            fatalError("Internal error enqueueing a Storage task")
        }
        components?.percentEncodedQuery = "uploadType=resumable&name=\(path)"
        
        request.url = components?.url
        
        guard let contentType = self.uploadMetadata.contentType else {
            fatalError("Internal error enqueueing a Storage task")
        }
        
        let uploadFetcher = GTMSessionUploadFetcher(
            request: request,
            uploadMIMEType: contentType,
            chunkSize: self.reference.storage.uploadChunkSizeBytes,
            fetcherService: fetcherService
        )
        if let uploadData {
            uploadFetcher.uploadData = uploadData
            uploadFetcher.comment = "Data UploadTask"
        } else if let fileURL = observer.fileURL {
            uploadFetcher.uploadFileURL = fileURL
            uploadFetcher.comment = "File UploadTask"
        }
        uploadFetcher.maxRetryInterval = self.reference.storage.maxUploadRetryInterval
        
        uploadFetcher.sendProgressBlock = { [weak self] (bytesSent: Int64, totalBytesSent: Int64,
                                                         totalBytesExpectedToSend: Int64) in
            guard let self else { return }
            Task { @StorageActor in
                self.observer.base.progress.completedUnitCount = totalBytesSent
                self.observer.base.progress.totalUnitCount = totalBytesExpectedToSend
                self.observer.base.metadata = self.uploadMetadata
                self.observer.fire(state: .progress)
                self.state = .running
            }
        }
        self.uploadFetcher = uploadFetcher
        
        // Process fetches
        self.state = .running
        do {
            let data = try await uploadFetcher.beginFetch()
            // Fire last progress updates
            self.observer.fire(state: .progress)
            
            
            if let responseDictionary = try? JSONSerialization
                .jsonObject(with: data) as? [String: AnyHashable] {
                var metadata = StorageMetadata(dictionary: responseDictionary)
                metadata.fileType = .file
                self.state = .success(metadata)
                self.observer.base.metadata = metadata
                return metadata
            } else {
                throw StorageErrorCode.error(withInvalidRequest: data)
            }
        } catch {
            self.observer.fire(state: .progress)
            let error = StorageErrorCode.error(withServerError: error as NSError,
                                               ref: self.reference)
            self.observer.base.metadata = self.uploadMetadata
            self.state = .failed(error)
            throw error
        }
    }

  /**
   * Pauses a task currently in progress.
   */
    public func pause() {
        Task { @StorageActor in
            self.uploadFetcher?.pauseFetching()
            if case .success = self.observer.base.state {
                ()
            } else {
                self.observer.base.metadata = self.uploadMetadata
            }
            self.observer.fire(state: .paused)
        }
    }

  /**
   * Cancels a task.
   */
    public func cancel() {
        Task { @StorageActor in
            let error = StorageErrorCode.error(
                withServerError: StorageErrorCode.cancelled as NSError,
                ref: self.observer.base.reference
            )
            self.observer.base.state = .cancelled(error)
            self.uploadFetcher?.stopFetching()
            if case .success = state {
                ()
            } else {
                self.observer.base.metadata = self.uploadMetadata
            }
            self.observer.fail(with: error)
        }
  }

  /**
   * Resumes a paused task.
   */
    public func resume() {
        Task { @StorageActor in
            self.observer.base.state = .resuming
            self.uploadFetcher?.resumeFetching()
            if case .success = state {
                ()
            } else {
                self.observer.base.metadata = self.uploadMetadata
            }
            self.observer.fire(state: .running)
        }
    }

    @StorageActor
  private var uploadFetcher: GTMSessionUploadFetcher?
    @StorageActor
  private let uploadMetadata: StorageMetadata
    @StorageActor
  private var uploadData: Data?

  // MARK: - Internal Implementations

  init(reference: StorageReference,
       file: URL? = nil,
       data: Data? = nil,
       metadata: StorageMetadata) {
      
      var metadata = metadata
      if metadata.contentType == nil {
          metadata.contentType = StorageUtils.MIMETypeForExtension(file?.pathExtension)
      }

      self.uploadMetadata = metadata
      self.uploadData = data
      self.observer = StorageObserver(reference: reference, file: file)

  }

  deinit {
    self.uploadFetcher?.stopFetching()
  }

    @StorageActor
  private func contentUploadError() -> NSError? {
    if uploadData != nil {
      return nil
    }
      if let resourceValues = try? observer.fileURL?.resourceValues(forKeys: [.isRegularFileKey]),
       let isFile = resourceValues.isRegularFile,
       isFile == true {
      return nil
    }
      return StorageError.unknown(message: "File at URL: \(observer.fileURL?.absoluteString ?? "") is " +
      "not reachable. Ensure file URL is not " +
      "a directory, symbolic link, or invalid url.",
      serverError: [:]) as NSError
  }

  private func GCSEscapedString(_ input: String?) -> String? {
    guard let input = input else {
      return nil
    }
    let GCSObjectAllowedCharacterSet =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*,=:@"
    let allowedCharacters = CharacterSet(charactersIn: GCSObjectAllowedCharacterSet)
    return input.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
  }
}
