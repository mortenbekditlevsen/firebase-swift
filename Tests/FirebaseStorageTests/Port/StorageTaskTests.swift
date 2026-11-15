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

import FirebaseCore
@testable import FirebaseStorage
import Foundation
import Testing
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif os(Windows)
  import WinSDK
#endif

private func rootReference() -> StorageReference {
  var options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
  options.projectID = "project"
  options.apiKey = "key"
  options.storageBucket = "bucket"
  let app = FirebaseApp(options: options, name: "storage-\(UUID().uuidString)")
  return Storage.storage(app: app).reference()
}

private func label<T>(_ snapshot: StorageTaskSnapshot<T>) -> String {
  switch snapshot.status {
  case .resume: "resume"
  case .progress: "progress"
  case .pause: "pause"
  case .success: "success"
  case .failure: "failure"
  }
}

/// Collects everything a stream delivers until it ends.
private func collect<T>(_ stream: AsyncThrowingStream<StorageTaskSnapshot<T>, Error>) async
  -> [String] {
  var seen: [String] = []
  do {
    for try await snapshot in stream {
      seen.append(label(snapshot))
    }
  } catch {
    seen.append("threw")
  }
  return seen
}

struct StorageTaskTests {
  @Test func downloadURLsEscapeTheBucket() throws {
    // Upstream's testInitializeDownloadURLEscapesBucket: a bucket with "#" or
    // "/" in it must not break or rewrite the URL's path.
    let dictionary = [
      "bucket": "bucket#/o/other",
      "downloadTokens": "12345,ignored",
      "name": "path/to/object",
    ]
    let escapedBucket = StorageUtils.GCSEscapedString(dictionary["bucket"]!)
    let escapedPath = StorageUtils.GCSEscapedString(dictionary["name"]!)
    let url = StorageGetDownloadURLTask.downloadURLFromMetadataDictionary(dictionary,
                                                                         rootReference())
    #expect(url?.absoluteString ==
      "https://firebasestorage.googleapis.com:443/v0/b/\(escapedBucket)/o/\(escapedPath)?alt=media&token=12345")
  }

  @StorageActor
  @Test func newObserversDontRepeatEventsToExistingOnes() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    let first = observer.observe(handle: "first")
    observer.fire(state: .progress)
    _ = observer.observe(handle: "second")
    _ = observer.observe(handle: "third")
    observer.succeed(with: Data())

    // The first observer sees its initial state, the progress and the
    // outcome, once each, however many observers joined later.
    #expect(await collect(first) == ["resume", "progress", "success"])
  }

  @StorageActor
  @Test func lateObserversGetTheOutcomeOnce() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    observer.succeed(with: Data())
    #expect(await collect(observer.observe(handle: "late")) == ["success"])
  }

  @StorageActor
  @Test func finishedTasksStayFinished() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    let stream = observer.observe(handle: "observer")
    observer.fire(state: .cancelled(StorageError.cancelled))
    // A fetch completing or reporting progress after `cancel()` changes nothing.
    observer.fire(state: .progress)
    observer.succeed(with: Data())
    observer.setState(.running)

    #expect(await collect(stream) == ["resume", "failure", "threw"])
    guard case .cancelled = observer.base.state else {
      Issue.record("Expected the task to stay cancelled, got \(observer.base.state)")
      return
    }
  }

  @Test func appsWithTheSameNameGetTheirOwnFetcherServices() async {
    // Upstream keys the services by app name, so a second app with the name (such as one
    // configured again after `delete()`) would send requests with the first app's credentials.
    let first = rootReference().storage
    let second = Storage.storage(app: FirebaseApp(options: first.app.options,
                                                  name: first.app.name))
    let firstService = await StorageFetcherService.shared.service(first)
    #expect(await StorageFetcherService.shared.service(first) === firstService)
    #expect(await StorageFetcherService.shared.service(second) !== firstService)
  }

  // Upstream 13.2.0 (#11786): the async APIs cancel the transfer when the calling task is
  // cancelled, and throw `StorageError.cancelled`.
  @Test(arguments: ["putData", "putFile", "getData", "write"])
  func cancellingTheCallingTaskCancelsTheTransfer(_ api: String) async throws {
    let server = try SilentServer()
    defer { server.stop() }
    var options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
    options.projectID = "project"
    options.storageBucket = "bucket"
    let storage = Storage.storage(app: FirebaseApp(options: options, name: "storage-\(UUID().uuidString)"))
    storage.useEmulator(withHost: "127.0.0.1", port: server.port)
    let ref = storage.reference().child("object")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("data".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let transfer = Task {
      switch api {
      case "putData": _ = try await ref.putData(Data("data".utf8))
      case "putFile": _ = try await ref.putFile(from: file)
      case "getData": _ = try await ref.getData(maxSize: 1024)
      default: _ = try await ref.write(toFile: file.appendingPathExtension("download"))
      }
    }
    try await Task.sleep(for: .milliseconds(200))
    let start = ContinuousClock.now
    transfer.cancel()
    let result = await transfer.result
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(throws: StorageError.self) { try result.get() }
    if case .failure(let error) = result, let error = error as? StorageError {
      guard case .cancelled = error else {
        Issue.record("Expected StorageError.cancelled, got \(error)")
        return
      }
    }
  }
}

/// Accepts connections and never answers them: a listening socket whose
/// backlog the kernel fills, as for a server that hangs.
private final class SilentServer: Sendable {
  #if os(Windows)
    private typealias Descriptor = SOCKET
    private typealias SocketAddressIn = SOCKADDR_IN
    private typealias SocketAddress = SOCKADDR
  #else
    private typealias Descriptor = Int32
    private typealias SocketAddressIn = sockaddr_in
    private typealias SocketAddress = sockaddr
  #endif

  // Not POSIXError: Windows's POSIX error codes lack EADDRNOTAVAIL.
  enum Failure: Error {
    case socket, bind
  }

  private let descriptor: Descriptor
  let port: Int

  init() throws {
    #if os(Windows)
      var data = WSADATA()
      guard WSAStartup(0x0202, &data) == 0 else { throw Failure.socket }
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      guard fd != INVALID_SOCKET else { throw Failure.socket }
    #elseif canImport(Glibc)
      let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
      guard fd >= 0 else { throw Failure.socket }
    #else
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      guard fd >= 0 else { throw Failure.socket }
    #endif
    var address = SocketAddressIn()
    let loopback = UInt32(0x7F00_0001).bigEndian
    #if os(Windows)
      address.sin_family = ADDRESS_FAMILY(AF_INET)
      address.sin_addr.S_un.S_addr = loopback
    #else
      address.sin_family = sa_family_t(AF_INET)
      address.sin_addr.s_addr = loopback
    #endif
    address.sin_port = 0
    var length = socklen_t(MemoryLayout<SocketAddressIn>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: SocketAddress.self, capacity: 1) {
        bind(fd, $0, length) == 0 && listen(fd, 16) == 0 && getsockname(fd, $0, &length) == 0
      }
    }
    guard bound else {
      Self.close(fd)
      throw Failure.bind
    }
    descriptor = fd
    port = Int(UInt16(bigEndian: address.sin_port))
  }

  func stop() {
    Self.close(descriptor)
  }

  private static func close(_ descriptor: Descriptor) {
    #if os(Windows)
      closesocket(descriptor)
    #elseif canImport(Darwin)
      Darwin.close(descriptor)
    #elseif canImport(Glibc)
      Glibc.close(descriptor)
    #else
      Android.close(descriptor)
    #endif
  }
}
