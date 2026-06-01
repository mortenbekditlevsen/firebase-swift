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

@globalActor
actor StorageActor {
    static let shared = StorageActor()
}


/**
 * `StorageDownloadTask` implements resumable downloads from an object in Firebase Storage.
 *
 * Downloads can be returned on completion with a completion handler, and can be monitored
 * by attaching observers, or controlled by calling `pause()`, `resume()`,
 * or `cancel()`.
 *
 * Downloads can currently be returned as `Data` in memory, or as a `URL` to a file on disk.
 */
public final class StorageDownloadTask: StorageTaskManagement, Sendable {
    
    let observer: StorageObserver<Data>
  /**
   * Prepares a task and begins execution.
   */
   public func enqueue() {
    Task { @StorageActor in
      await enqueueImplementation()
    }
  }
    
    @StorageActor
    func start() async throws -> Data {
        try await enqueueImplementationAsync()
    }
    
    public func observe() async -> (String, AsyncThrowingStream<StorageTaskSnapshot<Data>, Error>) {
        let handle = UUID().uuidString
        return (handle, await observer.observe(handle: handle))
    }

  /**
   * Pauses a task currently in progress. Calling this on a paused task has no effect.
   */
    public func pause() {
        Task { @StorageActor in
            switch observer.base.state {
            case .paused, .pausing:
                return
            default:
                ()
            }
            observer.base.state = .pausing
            // Use the resume callback to confirm pause status since it always runs after the last
            // NSURLSession update.
            if let fetcher {
                fetcher.resumeDataBlock = { [weak self] (data: Data) in
                    guard let self else { return }
                    Task { @StorageActor in
                        self.downloadData = data
                        self.observer.fire(state: .paused)
                    }
                }
                fetcher.stopFetching()
            }
        }
    }

  /**
   * Cancels a task.
   */
    public func cancel() {
        cancel(withError: StorageError.cancelled as NSError)
  }

  /**
   * Resumes a paused task. Calling this on a running task has no effect.
   */
    public func resume() {
        Task { @StorageActor in
            self.observer.base.state = .resuming
            self.observer.fire(state: .running)
            await self.enqueueImplementation(resumeWith: self.downloadData)
        }
    }

    @StorageActor
  private var fetcher: GTMSessionFetcher?

    // reference to already downloaded data for pause/resume
    @StorageActor
    var downloadData: Data?

  // MARK: - Internal Implementations

   init(reference: StorageReference,
                file: URL?) {
       self.observer = StorageObserver(
        reference: reference,
        file: file
       )
  }

  deinit {
    self.fetcher?.stopFetching()
  }

    @StorageActor
    private func enqueueImplementation(resumeWith resumeData: Data? = nil) async {
        do {
            let data = try await enqueueImplementationAsync(resumeWith: resumeData)
            self.downloadData = data
        } catch {
            // Observer already set to 'failed' state
        }
    }
    
    @StorageActor
    private func enqueueImplementationAsync(resumeWith resumeData: Data? = nil) async throws -> Data {

        observer.base.state = .queueing

        var request = observer.base.baseRequest
        let reference = observer.base.reference
      request.httpMethod = "GET"
        request.timeoutInterval = reference.storage.maxDownloadRetryTime
      var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
      components?.query = "alt=media"
      request.url = components?.url

      var fetcher: GTMSessionFetcher
      if let resumeData {
        fetcher = GTMSessionFetcher(downloadResumeData: resumeData)
        fetcher.comment = "Resuming DownloadTask"
      } else {
        let fetcherService = await StorageFetcherService.shared.service(reference.storage)

        fetcher = fetcherService.fetcher(with: request)
        fetcher.comment = "Starting DownloadTask"
      }
      fetcher.maxRetryInterval = reference.storage.maxDownloadRetryInterval

      if let fileURL = observer.fileURL {
        // Handle file downloads
        fetcher.destinationFileURL = fileURL
        fetcher.downloadProgressBlock = { [weak self] (bytesWritten: Int64,
                                                       totalBytesWritten: Int64,
                                                       totalBytesExpectedToWrite: Int64) in
            guard let self else { return }
            Task { @StorageActor in
                self.observer.base.progress.completedUnitCount = totalBytesWritten
                self.observer.base.progress.totalUnitCount = totalBytesExpectedToWrite
                self.observer.fire(state: .progress)
                self.observer.base.state = .running
            }
        }
      } else {
        // Handle data downloads
        fetcher.receivedProgressBlock = { [weak self] (bytesWritten: Int64,
                                                       totalBytesWritten: Int64) in
            guard let self else { return }
            Task { @StorageActor in
                self.observer.base.progress.completedUnitCount = totalBytesWritten
                if let totalLength = self.fetcher?.response?.expectedContentLength {
                    self.observer.base.progress.totalUnitCount = totalLength
                }
                self.observer.fire(state: .progress)
                self.observer.base.state = .running
            }
        }
      }
      self.fetcher = fetcher
        observer.base.state = .running
      do {
          let data = try await fetcher.beginFetch()
          // Fire last progress updates
          observer.fire(state: .progress)

          // Download completed successfully, fire completion callbacks
          observer.succeed(with: data)
          return data
      } catch {
          observer.fire(state: .progress)
          let error = StorageErrorCode.error(
            withServerError: error as NSError,
            ref: reference
          )
          observer.fail(with: error)
          throw error
      }
    }


  func cancel(withError error: Error) {
      Task { @StorageActor in
          observer.base.state = .cancelled(error)
          fetcher?.stopFetching()
          observer.fail(with: error)
      }
  }
}
