#if os(macOS)
import Foundation

extension Platform {
    static let macLocalServer: LocalServerFactory = { call, commands, network, processPaths in
        LocalServerFetcher(call: call, commands: commands, network: network, processPaths: processPaths)
    }

    static let macLocalServerCommands: LocalServerCommands = { process in
        [LocalServerFetcher.processQuery(process), LocalServerFetcher.listeningPortsQuery(pid: "{{pid}}")]
    }
}
#endif
