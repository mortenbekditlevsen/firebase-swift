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

#if canImport(NIOTransportServices) && canImport(Network)
import Foundation
import Network
import NIOCore
import NIOTransportServices

/// WebSocket connections over Network.framework, through SwiftNIO
/// (swift-nio-transport-services), with the system's TLS.
///
/// Network.framework knows about the device's network paths: when a better
/// path is available (Wi-Fi after cellular, say), the connection is closed so
/// the client reconnects on it.
public struct NIOTSDatabaseTransport: DatabaseTransport {
    private let group: NIOTSEventLoopGroup
    private let connectTimeout: TimeAmount
    private let reconnectsOnBetterPath: Bool
    private let waitsForConnectivity: Bool
    private let tlsOptions: @Sendable () -> NWProtocolTLS.Options

    /// - Parameters:
    ///   - eventLoopGroup: The group connections run on.
    ///   - connectTimeout: How long connecting (and waiting for connectivity)
    ///     may take.
    ///   - reconnectsOnBetterPath: Whether to reconnect when the system finds a
    ///     better network path.
    ///   - waitsForConnectivity: Whether connecting waits (up to the timeout)
    ///     while there's no route to the server, instead of failing. It also
    ///     waits when the server refuses the connection, so by default it
    ///     doesn't: the client backs off and retries, and retries at once when
    ///     the network changes.
    ///   - tlsOptions: The TLS options for `wss` connections (by default, the
    ///     system's trust evaluation).
    public init(
        eventLoopGroup: NIOTSEventLoopGroup = .singleton,
        connectTimeout: TimeAmount = .seconds(30),
        reconnectsOnBetterPath: Bool = true,
        waitsForConnectivity: Bool = false,
        tlsOptions: @escaping @Sendable () -> NWProtocolTLS.Options = { NWProtocolTLS.Options() }
    ) {
        group = eventLoopGroup
        self.connectTimeout = connectTimeout
        self.reconnectsOnBetterPath = reconnectsOnBetterPath
        self.waitsForConnectivity = waitsForConnectivity
        self.tlsOptions = tlsOptions
    }

    public func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (NIODatabaseTransport.Connection) async throws -> sending Result
    ) async throws -> sending Result {
        let target = try WebSocketTarget(request)
        var bootstrap = NIOTSConnectionBootstrap(group: group)
            .connectTimeout(connectTimeout)
            .channelOption(NIOTSChannelOptions.waitForActivity, value: waitsForConnectivity)
        if target.secure {
            bootstrap = bootstrap.tlsOptions(tlsOptions())
        }
        let reconnectsOnBetterPath = reconnectsOnBetterPath
        let pending = try await bootstrap.connect(host: target.host, port: target.port) { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(
                    NetworkEventHandler(reconnectsOnBetterPath: reconnectsOnBetterPath)
                )
                return try configureWebSocketClient(channel, head: target.head)
            }
        }
        return try await withWebSocket(pending, body)
    }
}

/// Acts on Network.framework's events about the connection's path.
private final class NetworkEventHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let reconnectsOnBetterPath: Bool

    init(reconnectsOnBetterPath: Bool) {
        self.reconnectsOnBetterPath = reconnectsOnBetterPath
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is NIOTSNetworkEvents.BetterPathAvailable:
            FFLog("I-RDB083030", "A better network path is available\(reconnectsOnBetterPath ? "; reconnecting" : "")")
            if reconnectsOnBetterPath {
                context.close(promise: nil)
            }
        case let update as NIOTSNetworkEvents.ViabilityUpdate:
            FFLog("I-RDB083031", "The connection is \(update.isViable ? "viable" : "not viable")")
        case let change as NIOTSNetworkEvents.PathChanged:
            FFLog("I-RDB083032", "The connection's network path changed: \(change.newPath)")
        case is NIOTSNetworkEvents.WaitingForConnectivity:
            FFLog("I-RDB083033", "Waiting for connectivity to connect")
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }
}
#endif
