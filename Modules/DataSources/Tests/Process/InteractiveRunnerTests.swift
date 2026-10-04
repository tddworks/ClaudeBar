import Testing
import Foundation
import Quotas
@testable import DataSources

@Suite
struct InteractiveRunnerTests {

    @Test
    func `run executes command and returns output`() throws {
        let runner = InteractiveRunner()
        // Use absolute path since 'echo' is a shell built-in
        let result = try runner.run(
            binary: "/bin/echo",
            input: "",
            options: .init(arguments: ["hello"])
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("hello"))
    }

    @Test
    func `run throws when binary not found`() {
        let runner = InteractiveRunner()
        #expect(throws: InteractiveRunner.RunError.self) {
            try runner.run(binary: "unknown-binary-xyz-123", input: "")
        }
    }

    @Test
    func `Options defaults environmentExclusions to empty`() {
        let options = InteractiveRunner.Options()
        #expect(options.environmentExclusions.isEmpty)
    }

    @Test
    func `Options stores environmentExclusions`() {
        let options = InteractiveRunner.Options(
            environmentExclusions: ["CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"]
        )
        #expect(options.environmentExclusions == ["CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"])
    }

    @Test
    func `run with environmentExclusions strips env vars from subprocess`() throws {
        let runner = InteractiveRunner()
        // Set a test env var that we'll verify is excluded
        let testKey = "CLAUDEBAR_TEST_EXCLUSION_VAR"
        setenv(testKey, "should_be_stripped", 1)
        defer { unsetenv(testKey) }

        // Run env command with the exclusion — the var should NOT appear in output
        let result = try runner.run(
            binary: "/usr/bin/env",
            input: "",
            options: .init(environmentExclusions: [testKey])
        )

        #expect(!result.output.contains("CLAUDEBAR_TEST_EXCLUSION_VAR=should_be_stripped"))
    }

    @Test
    func `run without environmentExclusions preserves env vars in subprocess`() throws {
        let runner = InteractiveRunner()
        let testKey = "CLAUDEBAR_TEST_PRESERVE_VAR"
        setenv(testKey, "should_be_present", 1)
        defer { unsetenv(testKey) }

        // Run env command without exclusion — the var SHOULD appear in output
        let result = try runner.run(
            binary: "/usr/bin/env",
            input: "",
            options: .init()
        )

        #expect(result.output.contains("CLAUDEBAR_TEST_PRESERVE_VAR=should_be_present"))
    }

    // MARK: - Environment additions (issue #222)

    @Test
    func `Options defaults environmentAdditions to empty`() {
        #expect(InteractiveRunner.Options().environmentAdditions.isEmpty)
    }

    @Test
    func `run with environmentAdditions passes env vars to subprocess`() throws {
        let runner = InteractiveRunner()

        let result = try runner.run(
            binary: "/usr/bin/env",
            input: "",
            options: .init(environmentAdditions: ["CLAUDEBAR_PROBE": "1"])
        )

        #expect(result.output.contains("\("CLAUDEBAR_PROBE")=1"))
    }

    // MARK: - Completion Rule (issue #271)

    @Test
    func `Options defaults completionRule to nil`() {
        #expect(InteractiveRunner.Options().completionRule == nil)
    }

    @Test
    func `Options stores completionRule`() {
        let options = InteractiveRunner.Options(completionRule: .claudeUsage)
        #expect(options.completionRule == .claudeUsage)
    }

    @Test
    func `run keeps waiting while the output is still a pending placeholder`() throws {
        let runner = InteractiveRunner()
        // Paints a placeholder, then goes quiet for longer than the 3s idle
        // cutoff before the real content arrives — exactly how `claude /usage`
        // fills its quota bars in asynchronously.
        let script = "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'"

        let result = try runner.run(
            binary: "/bin/sh",
            input: "",
            options: .init(
                timeout: 20.0,
                arguments: ["-c", script],
                completionRule: .claudeUsage
            )
        )

        #expect(result.output.contains("Current session"))
    }

    // MARK: - Completion Rule (issue #317)

    @Test
    func `run keeps waiting past a boot screen that never reached the Usage tab`() throws {
        let runner = InteractiveRunner()
        // The probe launches `claude /usage`, but the CLI only submits the command
        // once it has finished booting. For a few seconds the screen is the boot
        // screen — `/usage` still unsubmitted in the input box, SessionStart hooks
        // running — and nothing on it is a Usage screen. Going idle there ended the
        // capture with nothing to parse (#317).
        let script = """
        printf 'Opus 5 (1M context) with high effort · API Usage Billing\\n'
        printf '~/Library/Application Support/ClaudeBar/Probe\\n'
        printf '\\xe2\\x9d\\xaf /usage\\n'
        printf '✢ Burrowing… (running SessionStart hooks… 2/5 · 0s)\\n'
        printf ' Esc to cancel\\n'
        sleep 5
        printf 'Current session 1%% used\\n'
        """

        let result = try runner.run(
            binary: "/bin/sh",
            input: "",
            options: .init(
                timeout: 20.0,
                arguments: ["-c", script],
                completionRule: .claudeUsage
            )
        )

        #expect(result.output.contains("Current session"))
    }

    @Test
    func `a settled usage screen still ends the capture before the timeout`() throws {
        let runner = InteractiveRunner()
        // Over-waiting is its own failure: a finished screen must still stop the
        // capture at the idle cutoff instead of blocking for the whole timeout.
        // `exitCode` is -1 while the process is still running, so this proves the
        // run returned early without depending on the wall clock.
        let script = "printf 'Current session 1%% used'; sleep 15"

        let result = try runner.run(
            binary: "/bin/sh",
            input: "",
            options: .init(
                timeout: 20.0,
                arguments: ["-c", script],
                completionRule: .claudeUsage
            )
        )

        #expect(result.output.contains("Current session"))
        #expect(result.exitCode == -1)
    }
}

// MARK: - hasMeaningfulContent Tests

@Suite("hasMeaningfulContent")
struct HasMeaningfulContentTests {
    
    let runner = InteractiveRunner()
    
    // MARK: - Empty and Basic Cases
    
    @Test
    func `empty data returns false`() {
        let data = Data()
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `whitespace only returns false`() {
        let data = Data("   \n\t\r\n  ".utf8)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `visible text returns true`() {
        let data = Data("Hello, World!".utf8)
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    // MARK: - CSI Sequences (ESC [ ... letter)
    
    @Test
    func `CSI reset sequence only returns false`() {
        // \x1B[0m = reset all attributes
        let data = Data([0x1B, 0x5B, 0x30, 0x6D])  // ESC [ 0 m
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `CSI cursor show sequence only returns false`() {
        // \x1B[?25h = show cursor
        let data = Data([0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])  // ESC [ ? 2 5 h
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `multiple CSI sequences only returns false`() {
        // \x1B[0m\x1B[?25h\x1B[2J = reset, show cursor, clear screen
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])        // ESC [ 0 m
        data.append(contentsOf: [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68])  // ESC [ ? 2 5 h
        data.append(contentsOf: [0x1B, 0x5B, 0x32, 0x4A])        // ESC [ 2 J
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Charset Sequences (ESC ( or ESC ))
    
    @Test
    func `charset designation sequence only returns false`() {
        // \x1B(B = ASCII charset, \x1B(0 = line drawing
        var data = Data()
        data.append(contentsOf: [0x1B, 0x28, 0x42])  // ESC ( B
        data.append(contentsOf: [0x1B, 0x28, 0x30])  // ESC ( 0
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - OSC Sequences (ESC ] ... BEL or ST)
    
    @Test
    func `OSC sequence with BEL termination returns false`() {
        // \x1B]0;Window Title\x07 = set window title
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Window Title".utf8))
        data.append(0x07)  // BEL
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `OSC sequence with ST termination returns false`() {
        // \x1B]0;Window Title\x1B\\ = set window title (ST = ESC \)
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Window Title".utf8))
        data.append(contentsOf: [0x1B, 0x5C])  // ESC \ (ST)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `OSC sequence spanning multiple lines with BEL returns false`() {
        // OSC with newlines in content
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Line1\nLine2\nLine3".utf8))
        data.append(0x07)  // BEL
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `OSC sequence spanning multiple lines with ST returns false`() {
        // OSC with newlines in content, ST termination
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Line1\nLine2\nLine3".utf8))
        data.append(contentsOf: [0x1B, 0x5C])  // ESC \ (ST)
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Mixed ANSI + Visible Text
    
    @Test
    func `ANSI sequences with visible text returns true`() {
        // \x1B[0mHello\x1B[1mWorld
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])  // ESC [ 0 m
        data.append(Data("Hello".utf8))
        data.append(contentsOf: [0x1B, 0x5B, 0x31, 0x6D])  // ESC [ 1 m
        data.append(Data("World".utf8))
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `OSC sequence followed by visible text returns true`() {
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])  // ESC ]
        data.append(Data("0;Title".utf8))
        data.append(0x07)  // BEL
        data.append(Data("Actual content".utf8))
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `complex mix of all escape types with visible text returns true`() {
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
    func `non-UTF8 binary data returns true`() {
        // Invalid UTF-8 sequence
        let data = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81])
        #expect(runner.hasMeaningfulContent(data) == true)
    }
    
    @Test
    func `empty non-UTF8 is still false`() {
        // This tests the empty check before UTF-8 decode
        let data = Data()
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    // MARK: - Edge Cases
    
    @Test
    func `lone ESC character only returns false`() {
        let data = Data([0x1B])
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `multiple lone ESC characters returns false`() {
        let data = Data([0x1B, 0x1B, 0x1B])
        #expect(runner.hasMeaningfulContent(data) == false)
    }
    
    @Test
    func `incomplete CSI sequence is stripped as lone ESC`() {
        // ESC [ without terminating letter - the ESC gets stripped, [ remains
        // Actually this leaves "[" which is meaningful
        let data = Data([0x1B, 0x5B])  // ESC [
        #expect(runner.hasMeaningfulContent(data) == true)  // "[" remains
    }
    
    @Test
    func `real world Claude CLI escape sequences only returns false`() {
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