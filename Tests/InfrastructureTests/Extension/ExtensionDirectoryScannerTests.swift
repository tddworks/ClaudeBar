import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite
struct ExtensionDirectoryScannerTests {
    // MARK: - Scanning

    @Test
    func `scans directory and finds valid extensions`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ext-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create two extension directories with manifests
        let ext1Dir = tempDir.appendingPathComponent("my-provider")
        try FileManager.default.createDirectory(at: ext1Dir, withIntermediateDirectories: true)
        let manifest1 = """
        {
            "id": "my-provider",
            "name": "My Provider",
            "version": "1.0.0",
            "sections": [
                {
                    "id": "quotas",
                    "type": "quotaGrid",
                    "probe": { "command": "./probe.sh" }
                }
            ]
        }
        """
        try manifest1.write(to: ext1Dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let ext2Dir = tempDir.appendingPathComponent("another")
        try FileManager.default.createDirectory(at: ext2Dir, withIntermediateDirectories: true)
        let manifest2 = """
        {
            "id": "another",
            "name": "Another Provider",
            "version": "2.0.0",
            "sections": [
                {
                    "id": "status",
                    "type": "statusBanner",
                    "probe": { "command": "./check.sh", "interval": 30 }
                }
            ]
        }
        """
        try manifest2.write(to: ext2Dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let scanner = ExtensionDirectoryScanner()
        let results = scanner.scan(directory: tempDir)

        #expect(results.count == 2)
        let ids = Set(results.map(\.manifest.id))
        #expect(ids.contains("my-provider"))
        #expect(ids.contains("another"))
    }

    @Test
    func `skips directories without manifest json`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ext-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create directory without manifest
        let extDir = tempDir.appendingPathComponent("no-manifest")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        try "just a probe".write(to: extDir.appendingPathComponent("probe.sh"), atomically: true, encoding: .utf8)

        let scanner = ExtensionDirectoryScanner()
        let results = scanner.scan(directory: tempDir)

        #expect(results.isEmpty)
    }

    @Test
    func `skips directories with invalid manifest`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ext-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let extDir = tempDir.appendingPathComponent("bad-ext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        try "{ invalid json".write(to: extDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let scanner = ExtensionDirectoryScanner()
        let results = scanner.scan(directory: tempDir)

        #expect(results.isEmpty)
    }

    @Test
    func `returns empty array when directory does not exist`() {
        let scanner = ExtensionDirectoryScanner()
        let results = scanner.scan(directory: URL(fileURLWithPath: "/nonexistent/path"))

        #expect(results.isEmpty)
    }

    @Test
    func `scan result includes directory URL`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ext-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let extDir = tempDir.appendingPathComponent("my-ext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        let manifest = """
        {
            "id": "my-ext",
            "name": "My Ext",
            "version": "1.0.0",
            "sections": [
                { "id": "q", "type": "quotaGrid", "probe": { "command": "./p.sh" } }
            ]
        }
        """
        try manifest.write(to: extDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let scanner = ExtensionDirectoryScanner()
        let results = scanner.scan(directory: tempDir)

        #expect(results.count == 1)
        #expect(results[0].directory.lastPathComponent == "my-ext")
    }
}
