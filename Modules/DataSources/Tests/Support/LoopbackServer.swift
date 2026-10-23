import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#endif

/// A plain-HTTP server on 127.0.0.1, on a port the OS picks, for a test that
/// asks a real server on this machine. Each connection is read until its
/// headers and body have arrived, kept, and given the next answer, a raw
/// HTTP response; one with no answer left is closed.
final class LoopbackServer: @unchecked Sendable {
    let port: Int
    private let listener: Socket.Handle
    private let lock = NSLock()
    private var answers: [String]
    private var received: [String] = []
    private var closing = false

    /// The requests asked so far, each as it arrived.
    var requests: [String] { lock.withLock { received } }

    init(answers: [String]) throws {
        Socket.start()
        self.answers = answers
        let listener = Socket.open()
        var address = Socket.loopback(port: 0)
        var length = Socket.addressLength
        guard listener != Socket.invalid,
              withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) } }) == 0,
              listen(listener, 8) == 0,
              withUnsafeMutablePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }) == 0
        else {
            if listener != Socket.invalid { Socket.close(listener) }
            throw CocoaError(.fileWriteUnknown)
        }
        self.listener = listener
        port = Int(UInt16(bigEndian: address.sin_port))
        Thread.detachNewThread { [self] in serve() }
    }

    /// Stops listening. A connection made to wake the waiting accept is the last.
    func close() {
        lock.withLock { closing = true }
        let waker = Socket.open()
        var address = Socket.loopback(port: UInt16(port))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(waker, $0, Socket.addressLength) }
        }
        Socket.close(waker)
    }

    private func serve() {
        while true {
            let connection = accept(listener, nil, nil)
            if lock.withLock({ closing }) || connection == Socket.invalid {
                if connection != Socket.invalid { Socket.close(connection) }
                Socket.close(listener)
                return
            }
            let request = Self.read(connection)
            let answer: String? = lock.withLock {
                received.append(request)
                return answers.isEmpty ? nil : answers.removeFirst()
            }
            if let answer { Socket.send(Array(answer.utf8), on: connection) }
            Socket.close(connection)
        }
    }

    /// The request's headers, and as much body as its `Content-Length` says.
    private static func read(_ connection: Socket.Handle) -> String {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Socket.receive(into: &buffer, on: connection)
            guard count > 0 else { break }
            bytes += buffer.prefix(count)
            let text = String(decoding: bytes, as: UTF8.self)
            guard let end = text.range(of: "\r\n\r\n") else { continue }
            let length = text[..<end.lowerBound].split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            if text[end.upperBound...].utf8.count >= length { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Reserve an OS-picked port and release it before the next program binds.
    /// Do not start an accept thread: close() wakes that thread asynchronously,
    /// so its listener can still own the port when the next program starts.
    static func freePort() throws -> Int {
        Socket.start()
        let socket = Socket.open()
        guard socket != Socket.invalid else { throw CocoaError(.fileWriteUnknown) }
        defer { Socket.close(socket) }
        var address = Socket.loopback(port: 0)
        var length = Socket.addressLength
        guard withUnsafePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, length) }
        }) == 0,
        withUnsafeMutablePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

/// The few socket calls the server makes, as each OS spells them.
private enum Socket {
    #if os(Windows)
    typealias Handle = SOCKET
    static let invalid = INVALID_SOCKET
    static let addressLength = Int32(MemoryLayout<sockaddr_in>.size)
    private static let started: Void = {
        var data = WSADATA()
        _ = WSAStartup(0x0202, &data)
    }()
    static func start() { _ = started }
    static func open() -> Handle { socket(AF_INET, SOCK_STREAM, 0) }
    static func close(_ handle: Handle) { closesocket(handle) }
    static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        return address
    }
    static func receive(into buffer: inout [UInt8], on handle: Handle) -> Int {
        buffer.withUnsafeMutableBytes { Int(recv(handle, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0)) }
    }
    static func send(_ bytes: [UInt8], on handle: Handle) {
        bytes.withUnsafeBytes { _ = WinSDK.send(handle, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0) }
    }
    #else
    typealias Handle = Int32
    static let invalid: Handle = -1
    static let addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    static func start() {}
    #if canImport(Glibc)
    static func open() -> Handle { socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0) }
    static func close(_ handle: Handle) { _ = Glibc.close(handle) }
    #else
    static func open() -> Handle { socket(AF_INET, SOCK_STREAM, 0) }
    static func close(_ handle: Handle) { _ = Darwin.close(handle) }
    #endif
    static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        return address
    }
    static func receive(into buffer: inout [UInt8], on handle: Handle) -> Int {
        buffer.withUnsafeMutableBytes { recv(handle, $0.baseAddress, $0.count, 0) }
    }
    static func send(_ bytes: [UInt8], on handle: Handle) {
        #if canImport(Glibc)
        bytes.withUnsafeBytes { _ = Glibc.send(handle, $0.baseAddress, $0.count, 0) }
        #else
        bytes.withUnsafeBytes { _ = Darwin.send(handle, $0.baseAddress, $0.count, 0) }
        #endif
    }
    #endif
}
