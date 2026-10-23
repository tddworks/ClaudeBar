import Foundation

/// An app's own server on this machine, as a `localServer` fetch reaches it:
/// the programs running, their command lines and listening ports, and a
/// client that asks only this machine (MODULAR_DESIGN §10). The OS answers
/// four facts; finding the app and asking it are this one copy.
struct LocalServers: Sendable {
    let running: any RunningPrograms
    let commandLines: any ProgramCommandLines
    let ports: any ListeningPorts
    /// Asks a server on this machine: `LoopbackClient` over the OS's
    /// requests, unless a test hands its own.
    let network: any NetworkClient

    /// This OS's answers, asked through the one loopback client.
    init(_ os: some RunningPrograms & ProgramCommandLines & ListeningPorts & LoopbackRequests) {
        self.init(running: os, commandLines: os, ports: os, network: LoopbackClient(requests: os))
    }

    init(running: any RunningPrograms, commandLines: any ProgramCommandLines, ports: any ListeningPorts,
         network: any NetworkClient) {
        self.running = running
        self.commandLines = commandLines
        self.ports = ports
        self.network = network
    }

    /// The programs `running` as handed in, each server asked through
    /// `network`: what the factory's stubbed `make` hands a fetch.
    init(handing running: [RunningProgram], network: any NetworkClient) {
        let handed = Handed(programs: running)
        self.init(running: handed, commandLines: handed, ports: handed, network: network)
    }

    func fetcher(for call: LocalServerCall) -> LocalServerFetcher {
        LocalServerFetcher(call: call, servers: self)
    }

    /// The commands finding `process` runs, for Import's disclosure: none
    /// where the OS reads it without running a program.
    func commands(for process: LocalServerCall.Process) -> [[String]] {
        [commandLines.command(naming: process.names), ports.command(pid: "{{pid}}")].compactMap { $0 }
    }
}

/// A program running on this machine, as a test hands it to the stubbed
/// `DataSources.make`: where it is, what it was started with, and the ports
/// it listens on.
public struct RunningProgram: Sendable {
    public let pid: Int
    public let path: String
    public let commandLine: String
    public let ports: [Int]

    public init(pid: Int, path: String, commandLine: String, ports: [Int] = []) {
        self.pid = pid
        self.path = path
        self.commandLine = commandLine
        self.ports = ports
    }
}

/// The programs running, as handed in; reading them runs nothing.
private struct Handed: RunningPrograms, ProgramCommandLines, ListeningPorts {
    let programs: [RunningProgram]

    func paths() -> [String] { programs.map(\.path) }

    func commandLines(naming names: [String]) async -> [ProgramLine] {
        programs.filter { program in names.contains { program.commandLine.lowercased().contains($0.lowercased()) } }
            .map { ProgramLine(pid: $0.pid, text: $0.commandLine) }
    }

    func command(naming names: [String]) -> [String]? { nil }

    func ports(of pid: Int) async -> [Int] { programs.first { $0.pid == pid }?.ports ?? [] }

    func command(pid: String) -> [String]? { nil }
}
