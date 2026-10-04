import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// One session shared by every run of a CLI call (#132).
///
/// The definition carries only the vendor's facts — the args that create and
/// resume the session, the output that says it is gone, and the output that
/// says this CLI build rejects the flags. Which session a worker is in is its
/// own memory: create once, resume after, recreate when gone, fall back to the
/// plain invocation when the flags are refused.
@Suite("Session reuse on a CLI call (#132)")
struct CLISessionTests {

    // MARK: - Helpers


    /// Thread-safe recorder of every `execute` run's args, in order.
    private final class Launches: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String]] = []
        func record(_ args: [String]) { lock.withLock { all.append(args) } }
        var recorded: [[String]] { lock.withLock { all } }
    }

    private func call(
        args: [String] = ["/usage", "--allowed-tools", ""],
        session: CLICall.Session,
        workingDirectory: WorkingDirectory? = nil
    ) -> CLICall {
        CLICall(cli: "claude", args: args, timeout: 20, workingDirectory: workingDirectory, session: session)
    }

    /// Thread-safe queue of ids the runner hands out, in order.
    private final class IDQueue: @unchecked Sendable {
        private let lock = NSLock()
        private let ids: [String]
        private var index = 0
        init(_ ids: [String]) { self.ids = ids }
        func next() -> String {
            lock.withLock {
                defer { index += 1 }
                guard index < ids.count else { return "unexpected-id-\(index)" }
                return ids[index]
            }
        }
    }

    private func runner(
        _ call: CLICall,
        executor: MockCLIExecutor,
        launches: Launches? = nil,
        ids: [String] = [],
        memory: SessionMemory = SessionMemory()
    ) -> CLISessionRunner {
        let queue = IDQueue(ids)
        return CLISessionRunner(
            call: call,
            session: call.session ?? session(),
            directory: nil,
            makeExecutor: { _ in executor },
            memory: memory,
            nextID: { queue.next() }
        )
    }

    private func screen(_ text: String, exitCode: Int32 = 0, executor: MockCLIExecutor, launches: Launches) {
        given(executor).locate(.any).willReturn("/usr/local/bin/claude")
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: text, exitCode: exitCode)
        }
    }

    private let usageScreen = """
    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m
    """

    private func session() -> CLICall.Session {
        CLICall.Session(
            create: ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"],
            resume: ["--resume", "{{id}}"],
            recreateOn: ["no conversation found", "no session found"],
            unsupportedOn: ["unknown option '--session-id'", "unknown option '--resume'", "unknown option '--name'"]
        )
    }

    // MARK: - The definition side

    @Test
    func `a session block decodes with its templates and tokens`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data("""
        {"cli":"claude","args":["/usage"],
         "session":{"create":["--session-id","{{id}}","--name","ClaudeBar Probe"],
                    "resume":["--resume","{{id}}"],
                    "recreateOn":["no conversation found"],
                    "unsupportedOn":["unknown option '--session-id'"]}}
        """.utf8))

        let session = try #require(call.session)
        #expect(session.create == ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"])
        #expect(session.resume == ["--resume", "{{id}}"])
        #expect(session.recreateOn == ["no conversation found"])
        #expect(session.unsupportedOn == ["unknown option '--session-id'"])
    }

    @Test
    func `the match lists default to empty`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data("""
        {"cli":"claude","session":{"create":["--session-id","{{id}}"],"resume":["--resume","{{id}}"]}}
        """.utf8))
        #expect(call.session?.recreateOn.isEmpty == true)
        #expect(call.session?.unsupportedOn.isEmpty == true)
    }

    @Test
    func `a call without a session block encodes none`() throws {
        let call = CLICall(cli: "claude", args: ["/usage"])
        let json = String(data: try JSONEncoder().encode(call), encoding: .utf8)!

        #expect(json.contains("session") == false)
        #expect(try JSONDecoder().decode(CLICall.self, from: Data(json.utf8)) == call)
    }

    @Test
    func `a call with a session block survives the round trip`() throws {
        let call = call(session: session())
        let again = try JSONDecoder().decode(CLICall.self, from: JSONEncoder().encode(call))

        #expect(again == call)
    }

    // MARK: - The plan loop

    @Test
    func `the first run creates the session, names it, and remembers its id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let memory = SessionMemory()
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            memory: memory
        )

        let result = try await runner.run()

        #expect(result.output == usageScreen)
        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0] == ["/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe"])
        #expect(await memory.id == "11111111-2222-3333-4444-555555555555")
    }

    @Test
    func `the next run resumes the session it created`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let memory = SessionMemory()
        let runner = self.runner(call(session: session()), executor: executor,
                                 ids: ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"], memory: memory)

        _ = try await runner.run()
        _ = try await runner.run()
        _ = try await runner.run()

        #expect(launches.recorded.count == 3)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        #expect(launches.recorded[2] == ["/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        #expect(await memory.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    @Test
    func `a vanished session is recreated under a fresh id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let gone = "No conversation found with session ID aaaaaaaaaa"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--resume") ? gone : usageScreen, exitCode: 0)
        }
        let memory = SessionMemory()
        await memory.remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            memory: memory
        )

        let result = try await runner.run()

        #expect(result.output == usageScreen)
        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--resume"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe"])
        #expect(await memory.id == "11111111-2222-3333-4444-555555555555")
    }

    @Test
    func `a CLI that rejects the flags falls back to the plain run for good`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let refused = "error: unknown option '--session-id'"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--session-id") || args.contains("--resume") ? refused : usageScreen, exitCode: 1)
        }
        let memory = SessionMemory()
        let runner = self.runner(call(session: session()), executor: executor, ids: ["11111111-2222-3333-4444-555555555555"], memory: memory)

        let first = try await runner.run()
        let second = try await runner.run()

        #expect(first.output == usageScreen)
        #expect(second.output == usageScreen)
        // Create refused → plain retry; the memory keeps every later run plain.
        #expect(launches.recorded.count == 3)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", ""])
        #expect(launches.recorded[2] == ["/usage", "--allowed-tools", ""])
        #expect(await memory.id == nil)
        #expect(await memory.isRefused)
    }

    @Test
    func `a refusal while resuming also falls back, and drops the stale id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let refused = "error: unknown option '--resume'"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--resume") ? refused : usageScreen, exitCode: 1)
        }
        let memory = SessionMemory()
        await memory.remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let runner = self.runner(call(session: session()), executor: executor, memory: memory)

        _ = try await runner.run()

        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--resume"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", ""])
        #expect(await memory.id == nil)
    }

    @Test
    func `an unknown-option phrase on a successful screen is not a refusal`() async throws {
        // A SessionStart hook or transcript can carry the words; only a failed
        // run proves the CLI build rejects the flags.
        let launches = Launches()
        let executor = MockCLIExecutor()
        let chatty = """
        Tip: passing an unknown option '--session-id' used to error out.
        \(usageScreen)
        """
        screen(chatty, executor: executor, launches: launches)
        let memory = SessionMemory()
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            memory: memory
        )

        _ = try await runner.run()

        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(await memory.id == "11111111-2222-3333-4444-555555555555")
    }

    // MARK: - The detection rules

    @Test
    func `a refusal needs a non-zero exit and a token`() {
        let refused = CLIResult(output: "error: unknown option '--session-id'", exitCode: 1)

        #expect(CLISessionRunner.isRefused(refused, tokens: session().unsupportedOn))
        #expect(CLISessionRunner.isRefused(CLIResult(output: "error: unknown option '--session-id'", exitCode: 0), tokens: session().unsupportedOn) == false)
        #expect(CLISessionRunner.isRefused(CLIResult(output: "boom", exitCode: 1), tokens: session().unsupportedOn) == false)
        #expect(CLISessionRunner.isRefused(refused, tokens: []) == false)
    }

    @Test
    func `a refusal matches the token case-insensitively`() {
        let refused = CLIResult(output: "ERROR: UNKNOWN OPTION '--session-id'", exitCode: 1)

        #expect(CLISessionRunner.isRefused(refused, tokens: ["unknown option '--session-id'"]))
    }

    @Test
    func `gone tokens match case-insensitively`() {
        #expect(CLISessionRunner.isGone("No Conversation Found With Session ID x", tokens: ["no conversation found"]))
        #expect(CLISessionRunner.isGone("all good", tokens: ["no conversation found"]) == false)
        #expect(CLISessionRunner.isGone("all good", tokens: []) == false)
    }

    // MARK: - The memory

    @Test
    func `refusing the flags under concurrency forgets the session once and for good`() async {
        let memory = SessionMemory()
        await memory.remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(await memory.isRefused == false)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { await memory.refuse() }
            }
        }

        #expect(await memory.isRefused)
        #expect(await memory.id == nil)
    }

    // MARK: - The fetcher wiring

    @Test
    func `a fetcher with a session block creates once then resumes`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fetcher = CLIFetcher(
            call: call(session: CLICall.Session(
                create: ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"],
                resume: ["--resume", "{{id}}"],
                recreateOn: [],
                unsupportedOn: []
            )),
            makeExecutor: { _ in executor }
        )

        _ = try await fetcher.fetch(with: nil)
        _ = try await fetcher.fetch(with: nil)

        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(launches.recorded[1].contains("--resume"))
    }

    @Test
    func `two workers — two logins — keep two sessions`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let plan = CLICall.Session(create: ["--session-id", "{{id}}"], resume: ["--resume", "{{id}}"])
        let mine = CLIFetcher(call: call(session: plan), makeExecutor: { _ in executor })
        let work = CLIFetcher(call: call(session: plan), makeExecutor: { _ in executor })

        _ = try await mine.fetch(with: nil)
        _ = try await work.fetch(with: nil)

        let created = launches.recorded.compactMap { args in args.firstIndex(of: "--session-id").map { args[$0 + 1] } }
        #expect(created.count == 2)
        #expect(Set(created).count == 2)
    }

    @Test
    func `a fetcher without a session block runs its plain args`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fetcher = CLIFetcher(
            call: CLICall(cli: "claude", args: ["/usage", "--allowed-tools", ""], timeout: 20),
            makeExecutor: { _ in executor }
        )

        let response = try await fetcher.fetch(with: nil)

        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0] == ["/usage", "--allowed-tools", ""])
        #expect(response.text.contains("65% left"))
    }
}
