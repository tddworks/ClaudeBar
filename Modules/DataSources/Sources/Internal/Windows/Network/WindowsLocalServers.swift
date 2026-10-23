#if os(Windows)
import CWinHTTP
import Foundation
import WinSDK
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What Windows answers about an app's own server, without running a
/// program: the processes from the kernel's list, each one's command line
/// from its process information, its listening ports from the TCP table,
/// and one request through WinHTTP with the certificate checks off on that
/// request alone and no redirect followed. `URLSession` can't be asked to
/// trust one server here: swift-corelibs-foundation has no server trust.
struct WindowsLocalServers: RunningPrograms, ProgramCommandLines, ListeningPorts, LoopbackRequests {
    /// The executable paths of the processes running now. A process this user
    /// can't open (a service, the system) is left out.
    func paths() -> [String] {
        var paths: [String] = []
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        for id in Self.processIDs() {
            guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, id) else { continue }
            defer { CloseHandle(process) }
            var length = DWORD(buffer.count)
            if QueryFullProcessImageNameW(process, 0, &buffer, &length) {
                paths.append(String(decoding: buffer.prefix(Int(length)), as: UTF16.self))
            }
        }
        return paths
    }

    /// Read from each process this user can open; the rest are left out.
    func commandLines(naming names: [String]) async -> [ProgramLine] {
        let names = names.map { $0.lowercased() }
        return Self.processIDs().compactMap { id in
            guard let text = Self.commandLine(of: id) else { return nil }
            let lower = text.lowercased()
            return names.contains(where: { lower.contains($0) }) ? ProgramLine(pid: Int(id), text: text) : nil
        }
    }

    func command(naming names: [String]) -> [String]? { nil }

    func ports(of pid: Int) async -> [Int] {
        var ports = Set<Int>()
        for family in [AF_INET, AF_INET6] {
            var size: DWORD = 0
            _ = GetExtendedTcpTable(nil, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_LISTENER, 0)
            guard size > 0 else { continue }
            let table = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
            defer { table.deallocate() }
            guard GetExtendedTcpTable(table, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_LISTENER, 0) == NO_ERROR else { continue }
            let count = Int(table.load(as: DWORD.self))
            // The port is the low 16 bits, in network order.
            func port(_ local: DWORD) -> Int { Int(UInt16(truncatingIfNeeded: local).byteSwapped) }
            if family == AF_INET {
                let rows = (table + MemoryLayout<MIB_TCPTABLE_OWNER_PID>.offset(of: \.table)!)
                    .assumingMemoryBound(to: MIB_TCPROW_OWNER_PID.self)
                for index in 0..<count where rows[index].dwOwningPid == DWORD(pid) { ports.insert(port(rows[index].dwLocalPort)) }
            } else {
                let rows = (table + MemoryLayout<MIB_TCP6TABLE_OWNER_PID>.offset(of: \.table)!)
                    .assumingMemoryBound(to: MIB_TCP6ROW_OWNER_PID.self)
                for index in 0..<count where rows[index].dwOwningPid == DWORD(pid) { ports.insert(port(rows[index].dwLocalPort)) }
            }
        }
        return ports.sorted()
    }

    func command(pid: String) -> [String]? { nil }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // WinHTTP's calls block; they run off the cooperative pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try WinHTTPRequest(request).send() }) }
        }
    }

    /// Every process ID the kernel lists now.
    private static func processIDs() -> [DWORD] {
        var ids = [DWORD](repeating: 0, count: 4096)
        var returned: DWORD = 0
        while true {
            let size = DWORD(ids.count * MemoryLayout<DWORD>.size)
            guard K32EnumProcesses(&ids, size, &returned) else { return [] }
            if returned < size { break }
            ids = [DWORD](repeating: 0, count: ids.count * 2)
        }
        return ids.prefix(Int(returned) / MemoryLayout<DWORD>.size).filter { $0 != 0 }
    }

    private typealias QueryInformationProcess = @convention(c) (
        HANDLE?, Int32, UnsafeMutableRawPointer?, ULONG, UnsafeMutablePointer<ULONG>?
    ) -> LONG

    /// `NtQueryInformationProcess`, which ntdll exports but no import library links.
    private static let queryInformation: QueryInformationProcess? = {
        guard let ntdll = GetModuleHandleW(Array("ntdll.dll".utf16) + [0]),
              let address = GetProcAddress(ntdll, "NtQueryInformationProcess") else { return nil }
        return unsafeBitCast(address, to: QueryInformationProcess.self)
    }()

    /// `ProcessCommandLineInformation`: the command line as the process was started.
    private static let processCommandLineInformation: Int32 = 60

    private static func commandLine(of id: DWORD) -> String? {
        guard let query = queryInformation,
              let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, id) else { return nil }
        defer { CloseHandle(process) }
        var needed: ULONG = 0
        _ = query(process, processCommandLineInformation, nil, 0, &needed)
        guard needed >= ULONG(MemoryLayout<UNICODE_STRING>.size) else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(needed), alignment: 16)
        defer { buffer.deallocate() }
        guard query(process, processCommandLineInformation, buffer, needed, &needed) >= 0 else { return nil }
        let text = buffer.load(as: UNICODE_STRING.self)
        guard let characters = text.Buffer else { return "" }
        return String(decoding: UnsafeBufferPointer(start: characters, count: Int(text.Length) / 2), as: UTF16.self)
    }
}

/// One WinHTTP request, sent as `URLRequest` says, to the host in its URL.
private struct WinHTTPRequest {
    let request: URLRequest

    init(_ request: URLRequest) { self.request = request }

    func send() throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let secure = url.scheme?.lowercased() == "https"
        let port = url.port ?? (secure ? 443 : 80)
        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { target += "?" + query }

        guard let session = WinHttpOpen(Self.wide("ClaudeBar"), DWORD(WINHTTP_ACCESS_TYPE_NO_PROXY), nil, nil, 0) else { throw Self.failure() }
        defer { WinHttpCloseHandle(session) }
        let timeout = Int32(max(1, min(request.timeoutInterval, 600)) * 1000)
        _ = WinHttpSetTimeouts(session, timeout, timeout, timeout, timeout)
        guard let connection = WinHttpConnect(session, Self.wide(host), INTERNET_PORT(port), 0) else { throw Self.failure() }
        defer { WinHttpCloseHandle(connection) }
        guard let handle = WinHttpOpenRequest(connection, Self.wide(request.httpMethod ?? "GET"), Self.wide(target), nil, nil, nil,
                                              secure ? DWORD(WINHTTP_FLAG_SECURE) : 0) else { throw Self.failure() }
        defer { WinHttpCloseHandle(handle) }

        var features = DWORD(WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES)
        guard WinHttpSetOption(handle, DWORD(WINHTTP_OPTION_DISABLE_FEATURE), &features, DWORD(MemoryLayout<DWORD>.size)) else {
            throw Self.failure()
        }
        if secure {
            // On this request only: the server on this machine signs its own certificate.
            var ignored = DWORD(SECURITY_FLAG_IGNORE_UNKNOWN_CA | SECURITY_FLAG_IGNORE_CERT_CN_INVALID
                                | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID | SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE)
            guard WinHttpSetOption(handle, DWORD(WINHTTP_OPTION_SECURITY_FLAGS), &ignored, DWORD(MemoryLayout<DWORD>.size)) else {
                throw Self.failure()
            }
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).map { "\($0.key): \($0.value)\r\n" }.joined()
        var body = [UInt8](request.httpBody ?? Data())
        let sent = Self.wide(headers).withUnsafeBufferPointer { headerText in
            body.withUnsafeMutableBytes { bytes in
                WinHttpSendRequest(handle, headers.isEmpty ? nil : headerText.baseAddress, headers.isEmpty ? 0 : DWORD(UInt32.max),
                                   bytes.baseAddress, DWORD(bytes.count), DWORD(bytes.count), 0)
            }
        }
        guard sent, WinHttpReceiveResponse(handle, nil) else { throw Self.failure() }

        var status: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        guard WinHttpQueryHeaders(handle, DWORD(WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER), nil, &status, &size, nil) else {
            throw Self.failure()
        }
        var data = Data()
        while true {
            var available: DWORD = 0
            guard WinHttpQueryDataAvailable(handle, &available) else { throw Self.failure() }
            guard available > 0 else { break }
            var chunk = [UInt8](repeating: 0, count: Int(available))
            var read: DWORD = 0
            guard WinHttpReadData(handle, &chunk, available, &read) else { throw Self.failure() }
            guard read > 0 else { break }
            data.append(contentsOf: chunk.prefix(Int(read)))
        }
        guard let response = HTTPURLResponse(url: url, statusCode: Int(status), httpVersion: "HTTP/1.1",
                                             headerFields: Self.headerFields(of: handle)) else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    /// The response's headers, by name; the status line is left out.
    private static func headerFields(of handle: HINTERNET) -> [String: String] {
        var size: DWORD = 0
        _ = WinHttpQueryHeaders(handle, DWORD(WINHTTP_QUERY_RAW_HEADERS_CRLF), nil, nil, &size, nil)
        guard size > 0 else { return [:] }
        var buffer = [WCHAR](repeating: 0, count: Int(size) / MemoryLayout<WCHAR>.size + 1)
        guard WinHttpQueryHeaders(handle, DWORD(WINHTTP_QUERY_RAW_HEADERS_CRLF), nil, &buffer, &size, nil) else { return [:] }
        let text = String(decoding: buffer.prefix(Int(size) / MemoryLayout<WCHAR>.size), as: UTF16.self)
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[name] = fields[name].map { "\($0), \(value)" } ?? value
        }
        return fields
    }

    private static func wide(_ text: String) -> [WCHAR] { Array(text.utf16) + [0] }

    /// The last WinHTTP error, as `URLSession` would name it.
    private static func failure() -> URLError {
        switch GetLastError() {
        case 12002: URLError(.timedOut)  // ERROR_WINHTTP_TIMEOUT
        case 12175: URLError(.secureConnectionFailed)  // ERROR_WINHTTP_SECURE_FAILURE
        default: URLError(.cannotConnectToHost)
        }
    }
}
#endif
