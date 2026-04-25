import Foundation
import Domain

/// Result of scanning a single extension directory.
public struct ExtensionScanResult: Sendable {
    public let manifest: ExtensionManifest
    public let directory: URL

    public init(manifest: ExtensionManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }
}

/// Scans the extensions directory for valid extension manifests.
public final class ExtensionDirectoryScanner: Sendable {
    public init() {}

    /// Scans a directory for subdirectories containing valid manifest.json files.
    public func scan(directory: URL) -> [ExtensionScanResult] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { subDir -> ExtensionScanResult? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: subDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let manifestURL = subDir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? ExtensionManifest.parse(from: data) else {
                return nil
            }

            return ExtensionScanResult(manifest: manifest, directory: subDir)
        }
    }
}
