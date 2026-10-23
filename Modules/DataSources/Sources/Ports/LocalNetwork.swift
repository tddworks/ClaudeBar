import Foundation
import Mockable
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// What an OS answers about an app's own server on this machine (MODULAR_DESIGN
// §10), one question each. A platform's adapter answers all four;
// `LocalServers`, `LocalServerFetcher` and `LoopbackClient` above them find
// the app and ask it the same way on every platform.

/// The programs running now.
@Mockable
protocol RunningPrograms: Sendable {
    /// Their executable paths.
    func paths() -> [String]
}

/// A program running now, as its command line reads.
struct ProgramLine: Sendable, Equatable {
    let pid: Int
    /// The command line it was started with: its program and arguments.
    let text: String
}

/// The command lines of the programs running now.
@Mockable
protocol ProgramCommandLines: Sendable {
    /// Those whose command line names one of `names`, ignoring case. None
    /// when none runs or they can't be read.
    func commandLines(naming names: [String]) async -> [ProgramLine]
    /// The command that reads them, for Import's disclosure; `nil` when
    /// reading them runs no program.
    func command(naming names: [String]) -> [String]?
}

/// The TCP ports a program listens on.
@Mockable
protocol ListeningPorts: Sendable {
    /// Each once, in order. None when it listens on none or they can't be read.
    func ports(of pid: Int) async -> [Int]
    /// The command that reads them for `pid` (a placeholder in a disclosure);
    /// `nil` when reading them runs no program.
    func command(pid: String) -> [String]?
}

/// One request to a server on this machine.
@Mockable
protocol LoopbackRequests: Sendable {
    /// Sends `request` as it is, trusting the certificate the server presents
    /// and following no redirect: a redirect is the response. A host off this
    /// machine (`LoopbackClient.isLoopback`) throws `URLError(.unsupportedURL)`
    /// before anything is sent.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
