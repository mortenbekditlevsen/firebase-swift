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

import FirebaseAuth
import FirebaseCore
@testable import FirebaseFunctions
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

// Ported from upstream's FirebaseFunctions/Tests/Integration/IntegrationTests.swift.
// The callable functions are in Tests/Emulator/functions/index.js, which is
// upstream's FirebaseFunctions/Backend/index.js plus `authTest`. Upstream's
// completion-handler, main-thread and FCM token tests have no counterpart:
// this port only has the async API and no Messaging.

struct DataTestRequest: Encodable {
  var bool: Bool
  var int: Int32
  var long: Int64
  var string: String
  var array: [Int32]
  // Synthesized Encodable skips nil optionals; the function expects an explicit null.
  @NullEncodable var null: Bool?
}

@propertyWrapper
struct NullEncodable<T>: Encodable where T: Encodable {
  var wrappedValue: T?

  init(wrappedValue: T?) {
    self.wrappedValue = wrappedValue
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch wrappedValue {
    case let .some(value): try container.encode(value)
    case .none: try container.encodeNil()
    }
  }
}

struct DataTestResponse: Decodable, Equatable {
  var message: String
  var long: Int64
  var code: Int32
}

private struct EmptyRequest: Encodable, Sendable {}

private struct Location: Codable, Equatable, Sendable {
  let name: String
}

private struct WeatherForecast: Decodable, Equatable, Sendable {
  enum Conditions: String, Decodable {
    case sunny
    case rainy
    case snowy
  }

  let location: Location
  let temperature: Int
  let conditions: Conditions
}

private struct WeatherForecastReport: Decodable, Equatable, Sendable {
  let forecasts: [WeatherForecast]
}

private let forecasts = [
  WeatherForecast(location: Location(name: "Toronto"), temperature: 25, conditions: .snowy),
  WeatherForecast(location: Location(name: "London"), temperature: 50, conditions: .rainy),
  WeatherForecast(location: Location(name: "Dubai"), temperature: 75, conditions: .sunny),
]

@Suite(.enabled(if: Emulators.functions != nil && Emulators.auth != nil,
                "Needs the Functions and Auth emulators"),
       .timeLimit(.minutes(1)))
struct FunctionsIntegrationTests {
  let emulatorApp: EmulatorApp
  let functions: Functions

  init() throws {
    emulatorApp = try EmulatorApp()
    functions = try emulatorApp.functions()
  }

  private func url(_ name: String) throws -> URL {
    let address = try #require(Emulators.functions)
    return try #require(URL(string: "http://\(address.host):\(address.port)/" +
        "\(Emulators.projectID)/us-central1/\(name)"))
  }

  /// The function referenced by name and by URL, which build the URL differently.
  private func callables<Request, Response>(
    _ name: String,
    requestAs: Request.Type = Request.self,
    responseAs: Response.Type = Response.self
  ) throws -> [Callable<Request, Response>] {
    try [
      functions.httpsCallable(name, requestAs: requestAs, responseAs: responseAs),
      functions.httpsCallable(url(name), requestAs: requestAs, responseAs: responseAs),
    ]
  }

  /// The error `body` throws, as callers see it.
  private func callError(_ body: () async throws -> Void) async throws -> NSError {
    let error = try #require(await #expect(throws: (any Error).self) { try await body() })
    return error as NSError
  }

  /// The error a stream throws, once it has been read to the end.
  private func streamError<Element>(
    _ stream: AsyncThrowingStream<Element, Error>
  ) async throws -> FunctionsError {
    try #require(await #expect(throws: FunctionsError.self) {
      for try await _ in stream {}
    })
  }

  // MARK: - Calls

  @Test func data() async throws {
    let data = DataTestRequest(bool: true, int: 2, long: 9_876_543_210, string: "four",
                               array: [5, 6], null: nil)
    for function in try callables("dataTest",
                                  requestAs: DataTestRequest.self,
                                  responseAs: DataTestResponse.self) {
      let response = try await function.call(data)
      #expect(response == DataTestResponse(message: "stub response", long: 420, code: 42))
    }
  }

  @Test func scalar() async throws {
    for function in try callables("scalarTest", requestAs: Int16.self, responseAs: Int.self) {
      #expect(try await function.call(17) == 76)
    }
  }

  @Test func inferredTypesAndCallAsFunction() async throws {
    let function: Callable<Int16, Int> = functions.httpsCallable("scalarTest")
    #expect(try await function(17) == 76)
  }

  @Test func untypedCall() async throws {
    // A 64-bit Int would be sent as a wrapped Int64Value, which scalarTest rejects.
    let result = try await functions.httpsCallable("scalarTest").call(Int32(17))
    #expect((result.data as? NSNumber)?.intValue == 76)
  }

  @Test func null() async throws {
    for function in try callables("nullTest", requestAs: Int?.self, responseAs: Int?.self) {
      #expect(try await function.call(nil) == nil)
    }
  }

  // MARK: - Auth

  @Test func sendsTheAuthToken() async throws {
    // tokenTest checks the header for exactly "Bearer token".
    let functions = Functions(projectID: Emulators.projectID,
                              region: "us-central1",
                              customDomain: nil,
                              auth: FixedTokenAuth(token: "token"),
                              appCheck: nil)
    let address = try #require(Emulators.functions)
    functions.useEmulator(withHost: address.host, port: address.port)
    let function = functions.httpsCallable("tokenTest",
                                           requestAs: [String: Int].self,
                                           responseAs: [String: Int].self)
    #expect(try await function.call([:]) == [:])
  }

  /// A client with a token, for a host that isn't loopback, over plain HTTP.
  private func insecureFunctions() -> Functions {
    let functions = Functions(projectID: Emulators.projectID,
                              region: "us-central1",
                              customDomain: nil,
                              auth: FixedTokenAuth(token: "token"),
                              appCheck: nil)
    // A non-routable address: nothing must be sent there.
    functions.useEmulator(withHost: "10.255.255.1", port: 5001)
    return functions
  }

  @Test func tokensAreNotSentOverHTTPToOtherHosts() async throws {
    var call: Callable<Int16, Int> = insecureFunctions().httpsCallable("scalarTest")
    call.timeoutInterval = 2
    let error = try await callError { _ = try await call.call(17) }
    #expect(error.code == FunctionsErrorCode.unauthenticated.rawValue)

    let stream: Callable<EmptyRequest, String> = insecureFunctions().httpsCallable("genStream")
    let streamError = try await streamError(stream.stream())
    #expect(streamError.code == .invalidArgument)
    #expect((streamError.errorUserInfo[NSUnderlyingErrorKey] as? FunctionsError)?.code
      == .unauthenticated)
  }

  #if DEBUG
    @Test func insecureTokenAttachmentCanBeAllowedForDebugging() async throws {
      let functions = insecureFunctions()
      functions.allowInsecureTokenAttachment = true
      var call: Callable<Int16, Int> = functions.httpsCallable("scalarTest")
      call.timeoutInterval = 1
      // The request is sent, so it fails on the network instead.
      let error = try await callError { _ = try await call.call(17) }
      #expect(error.code != FunctionsErrorCode.unauthenticated.rawValue)
    }
  #endif

  @Test func passesTheSignedInUserToTheFunction() async throws {
    struct AuthResponse: Decodable { let uid: String? }
    let function = functions.httpsCallable("authTest",
                                           requestAs: EmptyRequest.self,
                                           responseAs: AuthResponse.self)
    #expect(try await function.call(EmptyRequest()).uid == nil)

    let user = try await emulatorApp.auth.signInAnonymously().user
    #expect(try await function.call(EmptyRequest()).uid == user.uid)

    try emulatorApp.auth.signOut()
    #expect(try await function.call(EmptyRequest()).uid == nil)
  }

  // MARK: - Errors

  @Test func missingResult() async throws {
    for function in try callables("missingResultTest", requestAs: Int?.self, responseAs: Int?.self) {
      let error = try await callError { _ = try await function.call(nil) }
      #expect(error.domain == FunctionsErrorDomain)
      #expect(error.code == FunctionsErrorCode.internal.rawValue)
      #expect(error.localizedDescription == "Response is missing data field.")
    }
  }

  @Test(arguments: ["unhandledErrorTest", "unknownErrorTest"])
  func errorsTheClientShouldntSeeAreInternal(name: String) async throws {
    for function in try callables(name, requestAs: [Int].self, responseAs: Int.self) {
      let error = try await callError { _ = try await function.call([]) }
      #expect(error.code == FunctionsErrorCode.internal.rawValue)
      #expect(error.localizedDescription == "INTERNAL")
    }
  }

  @Test func explicitError() async throws {
    for function in try callables("explicitErrorTest", requestAs: [Int].self, responseAs: Int.self) {
      let error = try await callError { _ = try await function.call([]) }
      #expect(error.code == FunctionsErrorCode.outOfRange.rawValue)
      #expect(error.localizedDescription == "explicit nope")
      let details = try #require(error.userInfo[FunctionsErrorDetailsKey] as? [String: Any])
      #expect((details["start"] as? NSNumber)?.intValue == 10)
      #expect((details["end"] as? NSNumber)?.intValue == 20)
      #expect((details["long"] as? NSNumber)?.int64Value == 30)
    }
  }

  @Test func httpError() async throws {
    for function in try callables("httpErrorTest", requestAs: [Int].self, responseAs: Int.self) {
      let error = try await callError { _ = try await function.call([]) }
      #expect(error.code == FunctionsErrorCode.invalidArgument.rawValue)
    }
  }

  @Test func thrownHttpsError() async throws {
    for function in try callables("throwTest", requestAs: [Int].self, responseAs: Int.self) {
      let error = try await callError { _ = try await function.call([]) }
      #expect(error.code == FunctionsErrorCode.invalidArgument.rawValue)
      #expect(error.localizedDescription == "Invalid test requested.")
    }
  }

  @Test func timeout() async throws {
    // Upstream uses timeoutTest with 0.05 s; Linux only supports whole seconds.
    for var function in try callables("slowTest", requestAs: [Int].self, responseAs: Int.self) {
      function.timeoutInterval = 1
      let error = try await callError { _ = try await function.call([]) }
      #expect(error.code == FunctionsErrorCode.deadlineExceeded.rawValue)
      #expect(error.localizedDescription == "DEADLINE EXCEEDED")
      #expect(error.userInfo[FunctionsErrorDetailsKey] == nil)
    }
  }

  // MARK: - Streaming

  @Test func streamsMessages() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("genStream")
    let messages: [String] = try await callable.stream().reduce([]) { $0 + [$1] }
    #expect(messages == ["hello", "world", "this", "is", "cool"])
  }

  @Test func streamResponseIncludesTheResult() async throws {
    let callable: Callable<EmptyRequest, StreamResponse<String, String>> =
      functions.httpsCallable("genStream")
    var contents: [String] = []
    for try await response in try callable.stream() {
      switch response {
      case let .message(message): contents.append(message)
      case let .result(result): contents.append(result)
      }
    }
    #expect(contents == ["hello", "world", "this", "is", "cool", "hello world this is cool"])
  }

  @Test func streamsCodableObjects() async throws {
    let callable: Callable<[Location], StreamResponse<WeatherForecast, WeatherForecastReport>> =
      functions.httpsCallable("genStreamWeather")
    var messages: [WeatherForecast] = []
    var report: WeatherForecastReport?
    for try await response in try callable.stream(forecasts.map(\.location)) {
      switch response {
      case let .message(message): messages.append(message)
      case let .result(result): report = result
      }
    }
    #expect(messages == forecasts)
    #expect(report == WeatherForecastReport(forecasts: forecasts))
  }

  @Test func streamMessagesThatDontDecodeAreDataLoss() async throws {
    let callable: Callable<[Location], StreamResponse<WeatherForecast, WeatherForecastReport>> =
      functions.httpsCallable("genStreamWeatherError")
    let error = try await streamError(callable.stream([Location(name: "Toronto")]))
    #expect(error.code == .dataLoss)
    #expect(error.errorUserInfo[NSUnderlyingErrorKey] is DecodingError)
  }

  @Test func streamResultsThatDontDecodeAreDataLoss() async throws {
    let callable: Callable<[Location], StreamResponse<WeatherForecast, String>> =
      functions.httpsCallable("genStreamWeather")
    let error = try await streamError(callable.stream([Location(name: "Toronto")]))
    #expect(error.code == .dataLoss)
    #expect(error.errorUserInfo[NSUnderlyingErrorKey] is DecodingError)
  }

  @Test func streamMessagesOfTheWrongTypeAreDataLoss() async throws {
    let callable: Callable<EmptyRequest, Int> = functions.httpsCallable("genStream")
    let error = try await streamError(callable.stream())
    #expect(error.code == .dataLoss)
    #expect(error.errorUserInfo[NSUnderlyingErrorKey] is DecodingError)
  }

  @Test func streamingANonexistentFunctionIsNotFound() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("nonexistentFunction")
    let error = try await streamError(callable.stream())
    #expect(error.code == .notFound)
    #expect(error.localizedDescription == "NOT FOUND")
  }

  @Test func streamErrorsAreInternal() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("genStreamError")
    let error = try await streamError(callable.stream())
    #expect(error.code == .internal)
    #expect(error.localizedDescription == "INTERNAL")
  }

  @Test func streamRequestsThatDontEncodeAreInvalidArguments() throws {
    struct Unencodable: Encodable, Sendable {
      func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue("", .init(codingPath: [], debugDescription: ""))
      }
    }
    let callable: Callable<Unencodable, String> = functions.httpsCallable("genStream")
    let error = try #require(throws: FunctionsError.self) { _ = try callable.stream(Unencodable()) }
    #expect(error.code == .invalidArgument)
    #expect(error.errorUserInfo[NSUnderlyingErrorKey] is EncodingError)
  }

  @Test func streamingANonStreamingFunctionIsDataLoss() async throws {
    let callable: Callable<Int16, Int> = functions.httpsCallable("scalarTest")
    let error = try await streamError(callable.stream(17))
    #expect(error.code == .dataLoss)
    #expect(error.localizedDescription == "Unexpected format for streamed response.")
  }

  @Test func emptyStream() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("genStreamEmpty")
    let messages: [String] = try await callable.stream().reduce([]) { $0 + [$1] }
    #expect(messages.isEmpty)
  }

  @Test func resultOnlyStreamYieldsNoMessages() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("genStreamResultOnly")
    let messages: [String] = try await callable.stream().reduce([]) { $0 + [$1] }
    #expect(messages.isEmpty)
  }

  @Test func resultOnlyStreamResponse() async throws {
    struct EmptyResponse: Decodable, Sendable {}
    let callable: Callable<EmptyRequest, StreamResponse<EmptyResponse, String>> =
      functions.httpsCallable("genStreamResultOnly")
    var result: String?
    for try await response in try callable.stream() {
      switch response {
      case .message: Issue.record("The stream shouldn't yield messages")
      case let .result(value): result = value
      }
    }
    #expect(result == "Only a result")
  }

  @Test func streamTimeoutIsUnavailable() async throws {
    var callable: Callable<EmptyRequest, String> = functions.httpsCallable("slowTest")
    callable.timeoutInterval = 1
    let error = try await streamError(callable.stream())
    #expect(error.code == .unavailable)
    #expect(error.errorUserInfo[NSUnderlyingErrorKey] is URLError)
  }

  @Test func streamsIgnoreHeartbeatComments() async throws {
    let callable: Callable<EmptyRequest, StreamResponse<String, String>> =
      functions.httpsCallable("genStreamHeartbeat")
    var contents: [String] = []
    for try await response in try callable.stream() {
      switch response {
      case let .message(message): contents.append(message)
      case let .result(result): contents.append(result)
      }
    }
    #expect(contents == ["after the pings", "done"])
  }

  @Test func streamsLargeData() async throws {
    let callable: Callable<EmptyRequest, String> = functions.httpsCallable("genStreamLargeData")
    let data: String = try await callable.stream().reduce("") { $0 + $1 }
    #expect(data == String(repeating: "A", count: 10000))
  }
}

/// Always hands out the same token, like upstream's `AuthTokenProvider`.
private final class FixedTokenAuth: AuthInterop {
  let token: String

  init(token: String) {
    self.token = token
  }

  func getToken(forcingRefresh _: Bool) async throws -> String? {
    token
  }

  func getUserID() -> String? {
    "fake user"
  }
}
