// Copyright 2024 Google LLC
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FirebaseShared

// MARK: - Type Aliases

/// Callback invoked by the fetcher's test block to provide a simulated response.
/// - Parameters:
///   - response: The simulated HTTP response, or nil.
///   - data: The simulated response body data, or nil.
///   - error: The simulated error, or nil.
typealias GTMSessionFetcherTestResponse = (HTTPURLResponse?, Data?, Error?) -> Void

/// A test block that intercepts fetcher requests for unit testing.
/// - Parameters:
///   - fetcher: The fetcher making the request.
///   - response: A callback to invoke with the simulated response.
typealias GTMSessionFetcherTestBlock = (GTMSessionFetcher, @escaping GTMSessionFetcherTestResponse) -> Void

/// Callback for a retry decision.
/// - Parameter shouldRetry: Whether the fetcher should retry.
typealias GTMSessionFetcherRetryResponse = (Bool) -> Void

/// A retry block invoked when a retryable error occurs.
/// - Parameters:
///   - suggestedWillRetry: Whether the fetcher suggests retrying.
///   - error: The error that occurred, or nil.
///   - response: A callback to invoke with the retry decision.
typealias GTMSessionFetcherRetryBlock = (Bool, Error?, @escaping GTMSessionFetcherRetryResponse) -> Void

/// Progress block for downloads to a file.
/// - Parameters:
///   - bytesWritten: Bytes written in this chunk.
///   - totalBytesWritten: Total bytes written so far.
///   - totalBytesExpectedToWrite: Total expected bytes, or -1 if unknown.
typealias GTMSessionFetcherDownloadProgressBlock = (Int64, Int64, Int64) -> Void

/// Progress block for in-memory data reception.
/// - Parameters:
///   - bytesReceived: Bytes received in this chunk.
///   - totalBytesReceived: Total bytes received so far.
typealias GTMSessionFetcherReceivedProgressBlock = (Int64, Int64) -> Void

/// Progress block for upload progress.
/// - Parameters:
///   - bytesSent: Bytes sent in this chunk.
///   - totalBytesSent: Total bytes sent so far.
///   - totalBytesExpectedToSend: Total expected bytes to send.
typealias GTMSessionFetcherSendProgressBlock = (Int64, Int64, Int64) -> Void

/// Block invoked with resume data when a download is paused or stopped.
/// - Parameter resumeData: Data that can be used to resume the download.
typealias GTMSessionFetcherResumeDataBlock = (Data) -> Void

// MARK: - GTMSessionFetcher

/// A wrapper around URLSession that provides retry logic, authorization, progress reporting,
/// and test injection capabilities. This replaces GTMSessionFetcher from the original
/// GTMSessionFetcher library with a pure Swift, cross-platform implementation.
class GTMSessionFetcher: @unchecked Sendable {

    /// The underlying URL request.
    private(set) var request: URLRequest?

    /// An optional comment for debugging/logging.
    var comment: String?

    /// The maximum interval between retries.
    var maxRetryInterval: TimeInterval = 60.0

    /// Whether retry is enabled.
    var isRetryEnabled: Bool = false

    /// Block invoked to decide whether to retry after an error.
    var retryBlock: GTMSessionFetcherRetryBlock?

    /// The test block, if set, is called instead of performing a real network request.
    var testBlock: GTMSessionFetcherTestBlock?

    /// The authorizer used to add authorization headers to requests.
    var authorizer: StorageTokenAuthorizer?

    /// The HTTP response received from the server.
    private(set) var response: HTTPURLResponse?

    /// The destination file URL for download tasks. When set, data is written to this file.
    var destinationFileURL: URL?

    /// Progress block for file downloads.
    var downloadProgressBlock: GTMSessionFetcherDownloadProgressBlock?

    /// Progress block for in-memory data downloads.
    var receivedProgressBlock: GTMSessionFetcherReceivedProgressBlock?

    /// Block called with resume data when the fetcher stops.
    var resumeDataBlock: GTMSessionFetcherResumeDataBlock?

    /// Resume data from a previous interrupted download.
    private var downloadResumeData: Data?

    /// The URLSession task backing this fetcher.
    private var sessionTask: URLSessionTask?

    /// Whether this fetcher was stopped.
    private var isStopped = false

    // MARK: - Initialization

    /// Creates a fetcher with a URL request.
    init(request: URLRequest) {
        self.request = request
    }

    /// Creates a fetcher that resumes a download from previously saved resume data.
    init(downloadResumeData: Data) {
        self.downloadResumeData = downloadResumeData
    }

    // MARK: - Fetching

    /// Begins the fetch operation. If a test block is set, it is invoked instead of a real request.
    /// - Returns: The response body data on success.
    /// - Throws: An error if the request fails.
    func beginFetch() async throws -> Data {
        guard !isStopped else {
            throw URLError(.cancelled)
        }

        // Authorize the request
        if let authorizer, let request {
            var mutableRequest = request
            try await authorizer.authorizeRequest(&mutableRequest)
            self.request = mutableRequest
        }

        // If a test block is set, use it instead of real networking
        if let testBlock {
            return try await withCheckedThrowingContinuation { continuation in
                testBlock(self) { response, data, error in
                    if let error {
                        self.response = response
                        continuation.resume(throwing: error)
                    } else {
                        self.response = response
                        continuation.resume(returning: data ?? Data())
                    }
                }
            }
        }

        guard let request else {
            throw URLError(.badURL)
        }

        // Perform the actual network request
        let session = URLSession.shared

        if let destinationFileURL {
            return try await performDownloadToFile(
                session: session,
                request: request,
                destinationURL: destinationFileURL
            )
        } else if downloadResumeData != nil {
            return try await performResumedDownload(session: session)
        } else {
            return try await performDataRequest(session: session, request: request)
        }
    }

    // MARK: - Private Network Methods

    private func performDataRequest(session: URLSession, request: URLRequest) async throws -> Data {
        let (chunks, urlResponse) = try await session.chunkedBytes(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        self.response = httpResponse

        let expectedLength = httpResponse.expectedContentLength
        var receivedData = Data()
        if expectedLength > 0 {
            receivedData.reserveCapacity(Int(expectedLength))
        }

        for try await chunk in chunks {
            guard !isStopped else { throw URLError(.cancelled) }
            receivedData.append(chunk)

            if let receivedProgressBlock {
                let total = Int64(receivedData.count)
                receivedProgressBlock(1, total)
            }
        }

        let statusCode = httpResponse.statusCode
        if statusCode >= 400 {
            let errorInfo: [String: Any] = [
                NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                "data": receivedData,
            ]
            throw NSError(domain: "com.google.HTTPStatus", code: statusCode, userInfo: errorInfo)
        }

        return receivedData
    }

    private func performDownloadToFile(
        session: URLSession,
        request: URLRequest,
        destinationURL: URL
    ) async throws -> Data {
        let delegate = DownloadDelegate(
            progressBlock: downloadProgressBlock,
            isStopped: { [weak self] in self?.isStopped ?? true }
        )
        let downloadSession = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { downloadSession.finishTasksAndInvalidate() }

        let (tempURL, urlResponse) = try await downloadSession.download(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        self.response = httpResponse

        let statusCode = httpResponse.statusCode
        if statusCode >= 400 {
            let data = (try? Data(contentsOf: tempURL)) ?? Data()
            let errorInfo: [String: Any] = [
                NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                "data": data,
            ]
            throw NSError(domain: "com.google.HTTPStatus", code: statusCode, userInfo: errorInfo)
        }

        // Move downloaded file to destination
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)

        return Data()
    }

    private func performResumedDownload(session: URLSession) async throws -> Data {
        // For a resumed download we start a fresh data request
        // since resume data handling is platform-specific.
        // In a full implementation this would use URLSession's
        // downloadTask(withResumeData:) API.
        guard let request else {
            throw URLError(.badURL)
        }
        return try await performDataRequest(session: session, request: request)
    }

    // MARK: - Control

    /// Stops the current fetch operation.
    func stopFetching() {
        isStopped = true
        sessionTask?.cancel()
    }
}

// MARK: - DownloadDelegate

/// URLSession delegate for tracking download progress.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressBlock: GTMSessionFetcherDownloadProgressBlock?
    let isStopped: (() -> Bool)?

    init(progressBlock: GTMSessionFetcherDownloadProgressBlock?, isStopped: (() -> Bool)?) {
        self.progressBlock = progressBlock
        self.isStopped = isStopped
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if isStopped?() == true {
            downloadTask.cancel()
            return
        }
        progressBlock?(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download(for:) call
    }
}

// MARK: - GTMSessionUploadFetcher

/// A fetcher that handles chunked, resumable uploads. This replaces GTMSessionUploadFetcher
/// from the original GTMSessionFetcher library.
class GTMSessionUploadFetcher: @unchecked Sendable {

    /// The underlying request for the initial upload request.
    private(set) var request: URLRequest

    /// The MIME type of the upload content.
    let uploadMIMEType: String

    /// The chunk size for resumable uploads.
    let chunkSize: Int64

    /// The fetcher service used to create sub-fetchers.
    let fetcherService: GTMSessionFetcherService

    /// An optional comment for debugging/logging.
    var comment: String?

    /// The maximum interval between retries.
    var maxRetryInterval: TimeInterval = 60.0

    /// Data to upload (for in-memory uploads).
    var uploadData: Data?

    /// File URL to upload from (for file-based uploads).
    var uploadFileURL: URL?

    /// Whether to use a background URLSession for uploads.
    var useBackgroundSession: Bool = true

    /// Progress block called during upload.
    var sendProgressBlock: GTMSessionFetcherSendProgressBlock?

    /// The HTTP response received from the server.
    private(set) var response: HTTPURLResponse?

    /// Whether this fetcher has been stopped.
    private var isStopped = false

    /// Whether this fetcher is paused.
    private var isPaused = false

    /// The URLSession task backing this upload.
    private var sessionTask: URLSessionTask?

    // MARK: - Initialization

    /// Creates an upload fetcher.
    /// - Parameters:
    ///   - request: The initial upload request (typically a POST to initiate a resumable upload).
    ///   - uploadMIMEType: The MIME type of the content being uploaded.
    ///   - chunkSize: The size of each upload chunk.
    ///   - fetcherService: The fetcher service for creating sub-fetchers.
    init(request: URLRequest,
         uploadMIMEType: String,
         chunkSize: Int64,
         fetcherService: GTMSessionFetcherService) {
        self.request = request
        self.uploadMIMEType = uploadMIMEType
        self.chunkSize = chunkSize
        self.fetcherService = fetcherService
    }

    // MARK: - Fetching

    /// Begins the upload fetch operation.
    /// - Returns: The response body data on success.
    /// - Throws: An error if the upload fails.
    func beginFetch() async throws -> Data {
        guard !isStopped else {
            throw URLError(.cancelled)
        }

        // Authorize the request
        if let authorizer = fetcherService.authorizer {
            var mutableRequest = request
            try await authorizer.authorizeRequest(&mutableRequest)
            self.request = mutableRequest
        }

        // If a test block is set on the service, use it
        if let testBlock = fetcherService.testBlock {
            let fetcher = GTMSessionFetcher(request: request)
            fetcher.comment = comment
            return try await withCheckedThrowingContinuation { continuation in
                testBlock(fetcher) { response, data, error in
                    if let error {
                        self.response = response
                        continuation.resume(throwing: error)
                    } else {
                        self.response = response
                        continuation.resume(returning: data ?? Data())
                    }
                }
            }
        }

        // Determine the upload body
        let bodyData: Data
        if let uploadData {
            bodyData = uploadData
        } else if let uploadFileURL {
            bodyData = try Data(contentsOf: uploadFileURL)
        } else {
            throw URLError(.cannotOpenFile)
        }

        let totalBytes = Int64(bodyData.count)

        let delegate = UploadDelegate(
            sendProgressBlock: sendProgressBlock,
            totalBytes: totalBytes,
            isStopped: { [weak self] in self?.isStopped ?? true }
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        // The resumable upload protocol, as GTMSessionUploadFetcher speaks it:
        // a "start" request carries the metadata (the request's JSON body) and
        // returns the upload URL; the data then goes there in chunks, the last
        // one finalizing the upload and returning the object's metadata.
        var startRequest = request
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(uploadMIMEType, forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        startRequest.setValue("\(totalBytes)", forHTTPHeaderField: "X-Goog-Upload-Content-Length")

        let (startData, startResponse) = try await send(startRequest, in: session)
        guard let uploadURLString = startResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            self.response = startResponse
            throw Self.statusError(code: startResponse.statusCode, data: startData)
        }

        // Every chunk but the last must be a multiple of the server's granularity.
        var chunkSize = max(chunkSize, 1)
        if let granularityString = startResponse.value(forHTTPHeaderField: "X-Goog-Upload-Chunk-Granularity"),
           let granularity = Int64(granularityString), granularity > 0 {
            chunkSize = max(granularity, chunkSize - chunkSize % granularity)
        }

        var offset: Int64 = 0
        repeat {
            while isPaused && !isStopped {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !isStopped else {
                throw URLError(.cancelled)
            }

            let length = min(chunkSize, totalBytes - offset)
            let isLast = offset + length == totalBytes
            let chunk = bodyData.subdata(in: Int(offset) ..< Int(offset + length))

            var chunkRequest = URLRequest(url: uploadURL)
            chunkRequest.httpMethod = "PUT"
            chunkRequest.timeoutInterval = request.timeoutInterval
            chunkRequest.setValue(isLast ? "upload, finalize" : "upload",
                                  forHTTPHeaderField: "X-Goog-Upload-Command")
            chunkRequest.setValue("\(offset)", forHTTPHeaderField: "X-Goog-Upload-Offset")
            chunkRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            if let authorizer = fetcherService.authorizer {
                try await authorizer.authorizeRequest(&chunkRequest)
            }

            delegate.setOffset(offset)
            let (data, response) = try await send(chunkRequest, body: chunk, in: session)
            offset += length
            if isLast {
                return data
            }
            guard response.value(forHTTPHeaderField: "X-Goog-Upload-Status") == "active" else {
                throw Self.statusError(code: response.statusCode, data: data)
            }
        } while true
    }

    /// Sends one request of the upload, throwing for an HTTP error status.
    private func send(_ request: URLRequest, body: Data? = nil,
                      in session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let (data, urlResponse) = if let body {
            try await session.upload(for: request, from: body)
        } else {
            try await session.data(for: request)
        }
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        self.response = httpResponse
        if httpResponse.statusCode >= 400 {
            throw Self.statusError(code: httpResponse.statusCode, data: data)
        }
        return (data, httpResponse)
    }

    private static func statusError(code: Int, data: Data) -> NSError {
        let errorInfo: [String: Any] = [
            NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: code),
            "data": data,
        ]
        return NSError(domain: "com.google.HTTPStatus", code: code, userInfo: errorInfo)
    }

    // MARK: - Control

    /// Pauses the upload.
    func pauseFetching() {
        isPaused = true
        sessionTask?.suspend()
    }

    /// Resumes a paused upload.
    func resumeFetching() {
        isPaused = false
        sessionTask?.resume()
    }

    /// Stops the upload.
    func stopFetching() {
        isStopped = true
        sessionTask?.cancel()
    }
}

// MARK: - UploadDelegate

/// URLSession delegate for tracking upload progress across all chunks.
private final class UploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let sendProgressBlock: GTMSessionFetcherSendProgressBlock?
    let totalBytes: Int64
    let isStopped: (() -> Bool)?
    private let lock = NSLock()
    private var offset: Int64 = 0

    init(sendProgressBlock: GTMSessionFetcherSendProgressBlock?, totalBytes: Int64,
         isStopped: (() -> Bool)?) {
        self.sendProgressBlock = sendProgressBlock
        self.totalBytes = totalBytes
        self.isStopped = isStopped
    }

    /// Sets where the chunk being sent starts in the whole upload.
    func setOffset(_ offset: Int64) {
        lock.lock()
        defer { lock.unlock() }
        self.offset = offset
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if isStopped?() == true {
            task.cancel()
            return
        }
        lock.lock()
        let offset = self.offset
        lock.unlock()
        sendProgressBlock?(bytesSent, offset + totalBytesSent, totalBytes)
    }
}

// MARK: - GTMSessionFetcherService

/// A service that creates and configures fetchers. This replaces GTMSessionFetcherService
/// from the original GTMSessionFetcher library.
class GTMSessionFetcherService: @unchecked Sendable {

    /// Whether retry is enabled for fetchers created by this service.
    var isRetryEnabled: Bool = false

    /// Block invoked to decide whether to retry after an error.
    var retryBlock: GTMSessionFetcherRetryBlock?

    /// Whether to allow requests to localhost.
    var allowLocalhostRequest: Bool = false

    /// The maximum interval between retries.
    var maxRetryInterval: TimeInterval = 60.0

    /// The test block applied to all fetchers created by this service.
    var testBlock: GTMSessionFetcherTestBlock?

    /// The authorizer used by fetchers created by this service.
    var authorizer: StorageTokenAuthorizer?

    /// Schemes that are allowed even without TLS (e.g. "http" for emulator).
    var allowedInsecureSchemes: [String] = []

    // MARK: - Creating Fetchers

    /// Creates a fetcher configured with this service's settings.
    /// - Parameter request: The URL request for the fetcher.
    /// - Returns: A configured `GTMSessionFetcher`.
    func fetcher(with request: URLRequest) -> GTMSessionFetcher {
        let fetcher = GTMSessionFetcher(request: request)
        fetcher.isRetryEnabled = isRetryEnabled
        fetcher.retryBlock = retryBlock
        fetcher.maxRetryInterval = maxRetryInterval
        fetcher.testBlock = testBlock
        fetcher.authorizer = authorizer
        return fetcher
    }
}
