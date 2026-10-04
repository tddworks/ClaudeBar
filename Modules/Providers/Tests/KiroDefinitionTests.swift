import Testing
import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas

/// Kiro as data: `kiro-cli` given `/usage` on stdin, read by `kiro-usage.js`
/// — the old probe's screens, with each added account in its own home.
@MainActor @Suite("Kiro definition")
struct KiroDefinitionTests {
    private func make(_ output: String, located: Bool = true, workHome: String? = nil, now: Date = Date()) throws -> Provider {
        let definition = try Providers.builtIn("kiro")
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(located ? "/usr/local/bin/kiro-cli" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, args, input, timeout, directory, _ in
                #expect(args.isEmpty)
                #expect(input == "/usage\n/quit\n")
                #expect(timeout == 30)
                #expect(directory == nil)
                return CLIResult(output: output)
            }
        let work = MockCLIExecutor()
        given(work).locate(.any).willReturn("/usr/local/bin/kiro-cli")
        given(work).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "Credits (40 of 50 covered in plan)"))
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, makeCLIExecutor: { _ in cli }, makeCommandExecutor: { @Sendable environment in
                if let home = environment.set["HOME"] {
                    #expect(home == workHome)
                    #expect(environment.set["KIRO_HOME"] == home + "/.kiro")
                    #expect(environment.set["XDG_DATA_HOME"] == home + "/.local/share")
                    #expect(environment.unset.contains("KIRO_API_KEY"))
                    return work
                }
                return cli
            }, network: MockNetworkClient(),
                makeTransport: { _,_,_,_ in MockRPCTransport() }, security: { _ in (1, "") }, scripts: Providers.builtInScripts, secrets: nil,
                browserCookies: SystemBrowserCookies(), environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { now })
        }, paths: DiskPaths())
    }
    private func parse(_ output: String) async throws -> UsageSnapshot { try await make(output).defaultAccount.refresh() }

    
    @Test
    func `parse normal output with both bonus and regular credits`() async throws {
        let output = """
        Estimated Usage | resets on 03/01 | KIRO FREE
        
        🎁 Bonus credits: 122.54/500 credits used, expires in 29 days
        
        Credits (0.00 of 50 covered in plan)
        ████████████████████████████████████████████████████████████████████████████████ 0%
        """
        
        let snapshot = try await parse(output)
        
        #expect(snapshot.providerId == "kiro")
        #expect(snapshot.quotas.count == 2)
        
        // Bonus credits: a grant that expires, with no window of its own
        let bonus = snapshot.quotas.first { $0.quotaType == .timeLimit("Bonus credits") }
        #expect(bonus != nil)
        if let bonus = bonus {
            #expect(abs(bonus.percentRemaining - 75.492) < 0.01)
            #expect(bonus.resetsAt != nil)
            #expect(bonus.resetText == "Expires in 29 days")
        }
        
        // Regular credits (monthly)
        let regular = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        #expect(regular != nil)
        if let regular = regular {
            #expect(abs(regular.percentRemaining - 100.0) < 0.01)
            #expect(regular.resetsAt != nil)
            #expect(regular.resetText == "Resets on 03/01")
        }
    }
    
    @Test
    func `parse bonus credits only`() async throws {
        let output = """
        🎁 Bonus credits: 250.0/500 credits used, expires in 15 days
        """
        
        let snapshot = try await parse(output)
        
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Bonus credits"))
        #expect(abs(snapshot.quotas[0].percentRemaining - 50.0) < 0.01)
    }
    
    @Test
    func `parse regular credits only`() async throws {
        let output = """
        Credits (25.0 of 50 covered in plan)
        resets on 03/15
        """
        
        let snapshot = try await parse(output)
        
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
        #expect(abs(snapshot.quotas[0].percentRemaining - 50.0) < 0.01)
    }
    
    @Test
    func `parse empty output throws error`() async {
        let output = ""
        
        await #expect(throws: UsageError.self) {
            try await parse(output)
        }
    }
    
    @Test
    func `parse malformed output throws error`() async {
        let output = "Some random text without quota data"
        
        await #expect(throws: UsageError.self) {
            try await parse(output)
        }
    }
    
    @Test
    func `parse zero total credits throws error`() async {
        let output = """
        🎁 Bonus credits: 0.0/0 credits used, expires in 10 days
        Credits (0.00 of 0 covered in plan)
        """
        
        // Should not crash with division by zero
        // Should skip quotas with zero total
        await #expect(throws: UsageError.self) {
            try await parse(output)
        }
    }
    
    @Test
    func `parse without reset info`() async throws {
        let output = """
        🎁 Bonus credits: 100.0/500 credits used
        Credits (10.0 of 50 covered in plan)
        """
        
        let snapshot = try await parse(output)
        
        #expect(snapshot.quotas.count == 2)
        
        // Both should have nil resetsAt and resetText
        for quota in snapshot.quotas {
            #expect(quota.resetsAt == nil)
            #expect(quota.resetText == nil)
        }
    }
    
    @Test
    func `parse with ANSI escape codes`() async throws {
        let output = """
        \u{001B}[38;5;141mEstimated Usage\u{001B}[0m | resets on 03/01 | \u{001B}[38;5;141mKIRO FREE\u{001B}[0m
        
        \u{001B}[1m🎁 Bonus credits:\u{001B}[0m \u{001B}[1m122.54/500\u{001B}[0m credits used, expires in \u{001B}[1m29\u{001B}[0m days
        
        \u{001B}[1mCredits\u{001B}[0m (0.00 of 50 covered in plan)
        """
        
        let snapshot = try await parse(output)
        
        #expect(snapshot.quotas.count == 2)
        #expect(abs(snapshot.quotas[0].percentRemaining - 75.492) < 0.01)
        #expect(abs(snapshot.quotas[1].percentRemaining - 100.0) < 0.01)
    }
    @Test func `separate home profiles produce separate usage`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let provider = try make("Credits (10 of 50 covered in plan)", workHome: home.path)
        let work = try provider.addAccount(filling: ["home":home.path])
        #expect(work.isEnabled)
        #expect(try await work.refresh().quotas.first?.percentRemaining == 20)
        #expect(try await provider.defaultAccount.refresh().quotas.first?.percentRemaining == 80)
        try FileManager.default.removeItem(at: home)
        await #expect(throws: UsageError.authenticationRequired) { try await work.refresh() }
        #expect(try await provider.defaultAccount.refresh().quotas.first?.percentRemaining == 80)
    }
    @Test func `missing binary preserves the CLI error`() async throws {
        let account = try make("", located: false).defaultAccount
        #expect(!(await account.isAvailable()))
        await #expect(throws: UsageError.cliNotFound("kiro-cli")) { try await account.refresh() }
    }

    @Test func `reset dates retain relative expiry and next-year rollover`() async throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year:2026,month:3,day:15,hour:12)))
        let snapshot = try await make("Bonus credits: 100/500 used, expires in 29 days\nCredits (10 of 50 covered in plan) resets on 03/15", now:now).defaultAccount.refresh()
        let bonus = snapshot.quota(for: .timeLimit("Bonus credits"))
        #expect(bonus?.resetsAt == now.addingTimeInterval(29*86400))
        #expect(bonus?.window?.length == nil) // an expiring grant is not a 7-day window
        let reset = try #require(Calendar.current.date(from: DateComponents(year:2027,month:3,day:15)))
        let monthBefore = try #require(Calendar.current.date(from: DateComponents(year:2027,month:2,day:15)))
        #expect(snapshot.quota(for: .timeLimit("Monthly"))?.resetsAt == reset)
        // The month that ends on the reset date — its real length, not a 30-day guess.
        #expect(snapshot.quota(for: .timeLimit("Monthly"))?.windowDuration == reset.timeIntervalSince(monthBefore))
    }

}
