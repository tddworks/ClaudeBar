import Testing
import Foundation
import Quotas
@testable import DataSources

@Suite(.needsTerminal)
struct InteractiveRunnerTests {

    @Test
    func `should show what a CLI printed and its success`() throws {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
        let echo = ShellProgram(sh: "echo hello", powershell: "'hello'")
        let result = try runner.run(
            binary: echo.binary,
            input: "",
            options: .init(timeout: PlatformTerminal.deadline, arguments: echo.arguments)
        )

        #expect(result.exitCode == 0)
        #expect(PlatformTerminal.screen(result.output).contains("hello"))
    }

    @Test
    func `should fail when the CLI isn't installed`() {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
        #expect(throws: InteractiveRunner.RunError.self) {
            try runner.run(binary: "unknown-binary-xyz-123", input: "")
        }
    }

    @Test
    func `should keep every environment value for a CLI unless told otherwise`() {
        let options = InteractiveRunner.Options()
        #expect(options.environmentExclusions.isEmpty)
    }

    @Test
    func `should remember which environment values to keep from a CLI`() {
        let options = InteractiveRunner.Options(
            environmentExclusions: ["CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"]
        )
        #expect(options.environmentExclusions == ["CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"])
    }

    @Test
    func `should start the CLI without the environment values it is told to drop`() throws {
        // The app has a value the call drops.
        let testKey = "CLAUDEBAR_TEST_EXCLUSION_VAR"
        let runner = InteractiveRunner(
            terminal: PlatformTerminal.terminal,
            programs: PlatformTerminal.programs(appEnvironment: ProcessInfo.processInfo.environment
                .merging([testKey: "should_be_stripped"]) { _, new in new })
        )

        // Print the variable with the exclusion — its value should NOT appear
        let env = ShellProgram(sh: "env", powershell: "'\(testKey)=' + $env:\(testKey)")
        let result = try runner.run(
            binary: env.binary,
            input: "",
            options: .init(timeout: PlatformTerminal.deadline, arguments: env.arguments, environmentExclusions: [testKey])
        )

        #expect(!PlatformTerminal.screen(result.output).contains("CLAUDEBAR_TEST_EXCLUSION_VAR=should_be_stripped"))
    }

    @Test
    func `should start the CLI with this app's environment values when none are dropped`() throws {
        let testKey = "CLAUDEBAR_TEST_PRESERVE_VAR"
        let runner = InteractiveRunner(
            terminal: PlatformTerminal.terminal,
            programs: PlatformTerminal.programs(appEnvironment: ProcessInfo.processInfo.environment
                .merging([testKey: "should_be_present"]) { _, new in new })
        )

        // Print the variable without exclusion — its value SHOULD appear
        let env = ShellProgram(sh: "env", powershell: "'\(testKey)=' + $env:\(testKey)")
        let result = try runner.run(
            binary: env.binary,
            input: "",
            options: .init(timeout: PlatformTerminal.deadline, arguments: env.arguments)
        )

        #expect(PlatformTerminal.screen(result.output).contains("CLAUDEBAR_TEST_PRESERVE_VAR=should_be_present"))
    }

    // MARK: - Environment additions (issue #222)

    @Test
    func `should add no environment values for a CLI unless told to`() {
        #expect(InteractiveRunner.Options().environmentAdditions.isEmpty)
    }

    @Test
    func `should start the CLI with the extra environment values it is given (#222)`() throws {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)

        let env = ShellProgram(sh: "env", powershell: "'CLAUDEBAR_PROBE=' + $env:CLAUDEBAR_PROBE")
        let result = try runner.run(
            binary: env.binary,
            input: "",
            options: .init(timeout: PlatformTerminal.deadline, arguments: env.arguments, environmentAdditions: ["CLAUDEBAR_PROBE": "1"])
        )

        #expect(PlatformTerminal.screen(result.output).contains("CLAUDEBAR_PROBE=1"))
    }

    // MARK: - Completion Rule (issue #271)

    @Test
    func `should wait on no screen rule unless one is given`() {
        #expect(InteractiveRunner.Options().completionRule == nil)
    }

    @Test
    func `should remember the screen rule it is given`() {
        let options = InteractiveRunner.Options(completionRule: .claudeUsage)
        #expect(options.completionRule == .claudeUsage)
    }

    @Test
    func `should keep waiting past a quiet spell while Claude's usage screen shows only its placeholder (#271)`() throws {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
        // Paints a placeholder, then goes quiet for longer than the 3s idle
        // cutoff before the real content arrives — exactly how `claude /usage`
        // fills its quota bars in asynchronously.
        let program = ShellProgram(
            sh: "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'",
            powershell: "[Console]::Write('Loading usage data...'); Start-Sleep 5; [Console]::Write('Current session 1% used')"
        )

        let result = try runner.run(
            binary: program.binary,
            input: "",
            options: .init(
                timeout: PlatformTerminal.deadline,
                arguments: program.arguments,
                completionRule: .claudeUsage
            )
        )

        #expect(PlatformTerminal.screen(result.output).contains("Current session"))
    }

    // MARK: - Completion Rule (issue #317)

    @Test
    func `should keep waiting past a quiet spell while the CLI is still booting (#317)`() throws {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
        // The probe launches `claude /usage`, but the CLI only submits the command
        // once it has finished booting. For a few seconds the screen is the boot
        // screen — `/usage` still unsubmitted in the input box, SessionStart hooks
        // running — and nothing on it is a Usage screen. Going idle there ended the
        // capture with nothing to parse (#317).
        let program = ShellProgram(
            sh: """
            printf 'Opus 5 (1M context) with high effort · API Usage Billing\\n'
            printf '~/Library/Application Support/ClaudeBar/Probe\\n'
            printf '\\xe2\\x9d\\xaf /usage\\n'
            printf '✢ Burrowing… (running SessionStart hooks… 2/5 · 0s)\\n'
            printf ' Esc to cancel\\n'
            sleep 5
            printf 'Current session 1%% used\\n'
            """,
            powershell: """
            'Opus 5 (1M context) with high effort - API Usage Billing'
            '~\\AppData\\Roaming\\ClaudeBar\\Probe'
            '> /usage'
            '* Burrowing... (running SessionStart hooks... 2/5 - 0s)'
            ' Esc to cancel'
            Start-Sleep 5
            'Current session 1% used'
            """
        )

        let result = try runner.run(
            binary: program.binary,
            input: "",
            options: .init(
                timeout: PlatformTerminal.deadline,
                arguments: program.arguments,
                completionRule: .claudeUsage
            )
        )

        #expect(PlatformTerminal.screen(result.output).contains("Current session"))
    }

    @Test
    func `should stop at once on a finished usage screen rather than wait out the timeout`() throws {
        let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
        // Over-waiting is its own failure: a finished screen must still stop the
        // capture at the idle cutoff instead of blocking for the whole timeout.
        // `exitCode` is -1 while the process is still running, so this proves the
        // run returned early without depending on the wall clock.
        let program = ShellProgram(
            sh: "printf 'Current session 1%% used'; sleep 15",
            powershell: "[Console]::Write('Current session 1% used'); Start-Sleep 15"
        )

        let result = try runner.run(
            binary: program.binary,
            input: "",
            options: .init(
                timeout: PlatformTerminal.deadline,
                arguments: program.arguments,
                completionRule: .claudeUsage
            )
        )

        #expect(PlatformTerminal.screen(result.output).contains("Current session"))
        #expect(result.exitCode == -1)
    }
}

// MARK: - hasMeaningfulContent Tests

@Suite("hasMeaningfulContent")
struct HasMeaningfulContentTests {
    
    let runner = InteractiveRunner(terminal: PlatformTerminal.terminal, programs: PlatformTerminal.programs)
    
    // MARK: - Empty and Basic Cases
    
    @Test
    func `should treat no output as the CLI having shown nothing yet`() {
        let data = Data()
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat blank space as the CLI having shown nothing yet`() {
        let data = Data("   \n\t\r\n  ".utf8)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat visible text as the CLI having shown something`() {
        let data = Data("Hello, World!".utf8)
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    // MARK: - CSI Sequences (ESC [ ... letter)
    
    @Test
    func `should treat a lone style reset as the CLI having shown nothing yet`() {
        // \x1B[0m = reset all attributes
        let data = Data([0x1B, 0x5B, 0x30, 0x6D])  // ESC [ 0 m
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat showing the cursor as the CLI having shown nothing yet`() {
        // \x1B[?25h = show cursor
        let data = Data([0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])  // ESC [ ? 2 5 h
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat a run of terminal controls as the CLI having shown nothing yet`() {
        // \x1B[0m\x1B[?25h\x1B[2J = reset, show cursor, clear screen
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])        // ESC [ 0 m
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])  // ESC [ ? 2 5 h
        data.append(contentsOf: [0x1B, 0x5B, 0x32, 0x4A])        // ESC [ 2 J
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Charset Sequences (ESC ( or ESC ))
    
    @Test
    func `should treat character-set switches as the CLI having shown nothing yet`() {
        // \x1B(B = ASCII charset, \x1B(0 = line drawing
        var data = Data()
        data.append(contentsOf: [0x1B, 0x28, 0x42])  // ESC ( B
        data.append(contentsOf: [0x1B, 0x28, 0x30])  // ESC ( 0
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - OSC Sequences (ESC ] ... BEL or ST)
    
    @Test
    func `should treat a window title ending in a bell as the CLI having shown nothing yet`() {
        // \x1B]0;Window Title\x07 = set window title
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Window Title".utf8))
        data.append(0x07)  // BEL
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat a window title ending in a string terminator as the CLI having shown nothing yet`() {
        // \x1B]0;Window Title\x1B\\ = set window title (ST = ESC \)
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Window Title".utf8))
        data.append(contentsOf: [0x1B, 0x5C])  // ESC \ (ST)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat a multi-line window title ending in a bell as the CLI having shown nothing yet`() {
        // OSC with newlines in content
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Line1\nLine2\nLine3".utf8))
        data.append(0x07)  // BEL
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat a multi-line window title ending in a string terminator as the CLI having shown nothing yet`() {
        // OSC with newlines in content, ST termination
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Line1\nLine2\nLine3".utf8))
        data.append(contentsOf: [0x1B, 0x5C])  // ESC \ (ST)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Mixed ANSI + Visible Text
    
    @Test
    func `should treat styled visible text as the CLI having shown something`() {
        // \x1B[0mHello\x1B[1mWorld
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])  // ESC [ 0 m
        data.append(Data("Hello".utf8))
        data.append(contentsOf: [0x1B, 0x5B, 0x31, 0x6D])  // ESC [ 1 m
        data.append(Data("World".utf8))
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `should treat text after a window title as the CLI having shown something`() {
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Title".utf8))
        data.append(0x07)  // BEL
        data.append(Data("Actual content".utf8))
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `should treat text among every kind of terminal control as the CLI having shown something`() {
        var data = Data()
        // OSC title
        data.append(contentsOf: [0x1B, 0x5D])
        data.append(Data("0;Title".utf8))
        data.append(0x07)
        // CSI reset
        data.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])
        // Charset
        data.append(contentsOf: [0x1B, 0x28, 0x42])
        // Visible text
        data.append(Data("Usage: 50%".utf8))
        // More CSI
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    // MARK: - Non-UTF8 Binary Data
    
    @Test
    func `should treat bytes that aren't text as the CLI having shown something`() {
        // Invalid UTF-8 sequence
        let data = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81])
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `should treat no bytes at all as the CLI having shown nothing yet, before any decoding`() {
        // This tests the empty check before UTF-8 decode
        let data = Data()
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Edge Cases
    
    @Test
    func `should treat a lone escape character as the CLI having shown nothing yet`() {
        let data = Data([0x1B])
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat several lone escape characters as the CLI having shown nothing yet`() {
        let data = Data([0x1B, 0x1B, 0x1B])
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `should treat the bracket left by an unfinished terminal control as the CLI having shown something`() {
        // ESC [ without terminating letter - the ESC gets stripped, [ remains
        // Actually this leaves "[" which is meaningful
        let data = Data([0x1B, 0x5B])  // ESC [
        #expect(runner.hasMeaningfulContent(data) == true)  // "[" remains
    }
    
    @Test
    func `should treat the controls Claude's CLI writes before its screen as the CLI having shown nothing yet`() {
        // Simulates what Claude CLI outputs before actual content
        // \x1B[?25l\x1B[?2004h\x1B[?25h\x1B[?2004l
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x6C])  // ESC [ ? 2 5 l (hide cursor)
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x68])  // ESC [ ? 2 0 0 4 h
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])  // ESC [ ? 2 5 h (show cursor)
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x6C])  // ESC [ ? 2 0 0 4 l
        #expect(runner.hasMeaningfulContent(data) == false)
    }
}
