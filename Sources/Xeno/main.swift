import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL

public struct Config {
    /// This needs to be a positive number above 0
    /// 0 Causes issues with firewalls on certain Linux system configurations ( Looking at you ubuntu >:| )
    static let backlogSize: Int32 = 256
}

final class HTTP1TestServer: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buff = self.unwrapInboundIn(data)
        switch (buff) {
        case HTTPPart.head(let head):
            break
        case HTTPPart.body(let body):
            break
        case HTTPPart.end(_):
            return
        }

        // Insert an event loop tick here. This more accurately represents real workloads in SwiftNIO, which will not
        // re-entrantly write their response frames.
        context.eventLoop.execute {
            context.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var headers = HTTPHeaders()
                headers.add(name: "content-length", value: "5")
                headers.add(name: "server", value: "Xeno")
                headers.add(name: "x-stream-id", value: String(Int(streamID)))
                context.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: nil)

                var buffer = context.channel.allocator.buffer(capacity: 12)
                buffer.writeStaticString("Hello :o")
                context.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                return context.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
            }.whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[ ERROR ] \(error)")
        context.close(promise: nil)
    }
}

public final class Xeno {
    private let host: String
    private let port: Int
    private let eventGroup: MultiThreadedEventLoopGroup

    public init(host: String = "::1", port: Int = 7050) {
        self.host = host
        self.port = port
        self.eventGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    deinit {
        try! eventGroup.syncShutdownGracefully()
    }

    public func run() throws {
        let bootstrap = ServerBootstrap(group: eventGroup)
        _ = bootstrap.serverChannelOption(ChannelOptions.backlog, value: Config.backlogSize)

        // Without we would sometimes not be able to re-use the port in quick restarts
        // when the resources haven't been fully free'd in the kernel yet.
        _ = bootstrap.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        var configuration = TLSConfiguration.forServer(
            certificateChain: try NIOSSLCertificate.fromPEMFile("/Users/a.vanhoudt/Certificates/local.dev.pem").map { .certificate($0) },
            privateKey: .file("/Users/a.vanhoudt/Certificates/local.dev-key.pem")
        )
        configuration.applicationProtocols.append("h2")
        configuration.applicationProtocols.append("http/1.1")
        let sslContext = try NIOSSLContext(configuration: configuration)

        _ = bootstrap.childChannelInitializer { channel -> EventLoopFuture<Void> in
            let handler = try! NIOSSLServerHandler(context: sslContext)
            _ = channel.pipeline.addHandler(handler)
            return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
                streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(HTTP1TestServer())
                }.flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(ErrorHandler())
                }
            }.flatMap { (_: HTTP2StreamMultiplexer) in
                channel.pipeline.addHandler(ErrorHandler())
            }
        }

        _ = bootstrap.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        _ = bootstrap.childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        _ = bootstrap.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try bootstrap.bind(host: host, port: port).wait()
        print("[ INFO  ] Bound to \(host) \(port)")
        try channel.closeFuture.wait()
    }
}

do {
    try Xeno().run()
} catch {
    print("Error: \(error)")
}
