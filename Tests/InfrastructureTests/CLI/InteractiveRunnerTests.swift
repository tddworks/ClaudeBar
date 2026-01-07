import Testing
import Foundation
@testable import Infrastructure

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