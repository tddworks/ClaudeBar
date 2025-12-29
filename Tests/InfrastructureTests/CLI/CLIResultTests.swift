import Testing
import Foundation
@testable import Infrastructure

@Suite
struct CLIResultTests {

    // MARK: - Initialization Tests

    @Test
    func `creates result with output and exit code`() {
        // Given
        let output = "Hello, World!"
        let exitCode: Int32 = 0

        // When
        let result = CLIResult(output: output, exitCode: exitCode)

        // Then
        #expect(result.output == "Hello, World!")
        #expect(result.exitCode == 0)
    }

    @Test
    func `creates result with default exit code of zero`() {
        // Given
        let output = "Success output"

        // When
        let result = CLIResult(output: output)

        // Then
        #expect(result.output == "Success output")
        #expect(result.exitCode == 0)
    }

    @Test
    func `creates result with non-zero exit code`() {
        // Given
        let output = "Error: command failed"
        let exitCode: Int32 = 1

        // When
        let result = CLIResult(output: output, exitCode: exitCode)

        // Then
        #expect(result.output == "Error: command failed")
        #expect(result.exitCode == 1)
    }

    @Test
    func `creates result with empty output`() {
        // Given & When
        let result = CLIResult(output: "", exitCode: 0)

        // Then
        #expect(result.output.isEmpty)
        #expect(result.exitCode == 0)
    }

    @Test
    func `creates result with multiline output`() {
        // Given
        let output = """
        Line 1
        Line 2
        Line 3
        """

        // When
        let result = CLIResult(output: output)

        // Then
        #expect(result.output.contains("Line 1"))
        #expect(result.output.contains("Line 2"))
        #expect(result.output.contains("Line 3"))
    }

    // MARK: - Equatable Tests

    @Test
    func `results with same output and exit code are equal`() {
        // Given
        let result1 = CLIResult(output: "test", exitCode: 0)
        let result2 = CLIResult(output: "test", exitCode: 0)

        // Then
        #expect(result1 == result2)
    }

    @Test
    func `results with different output are not equal`() {
        // Given
        let result1 = CLIResult(output: "test1", exitCode: 0)
        let result2 = CLIResult(output: "test2", exitCode: 0)

        // Then
        #expect(result1 != result2)
    }

    @Test
    func `results with different exit codes are not equal`() {
        // Given
        let result1 = CLIResult(output: "test", exitCode: 0)
        let result2 = CLIResult(output: "test", exitCode: 1)

        // Then
        #expect(result1 != result2)
    }
}
