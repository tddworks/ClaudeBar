import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct GeminiAPIProbeTests {

    // MARK: - Helpers

    private func makeTemporaryHomeDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createCredentialsFile(in homeDirectory: URL, accessToken: String = "test-token") throws {
        let dotGemini = homeDirectory.appendingPathComponent(".gemini")
        try FileManager.default.createDirectory(at: dotGemini, withIntermediateDirectories: true)
        
        let credsURL = dotGemini.appendingPathComponent("oauth_creds.json")
        let json: [String: Any] = [
            "access_token": accessToken,
            "expiry_date": Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: credsURL)
    }
    
    // MARK: - Tests
    
    @Test
    func `probe fails when credentials missing`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        let mockService = MockNetworkClient()
        
        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe discovers project id and fetches quota`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()

        // Setup mocks
        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        let quotaResponse = """
        {
            "buckets": [
                {
                    "modelId": "gemini-pro",
                    "remainingFraction": 0.8,
                    "resetTime": "2025-12-21T12:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("projects") {
                    return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                } else {
                    return (quotaResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            }

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1
        )
        
        let snapshot = try await probe.probe()
        
        // Verify quota
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
        
        // Verify project ID was included in quota request
        verify(mockService)
            .request(.matching { request in
                guard let url = request.url?.absoluteString else { return false }
                
                // Check if this is the quota request
                if url.contains("retrieveUserQuota") {
                    // Check body for project ID
                    if let body = request.httpBody,
                       let bodyStr = String(data: body, encoding: .utf8) {
                        return bodyStr.contains("gen-lang-client-123456")
                    }
                }
                return false
            })
            .called(1)
    }
    
    @Test
    func `probe parses reset time into Date and human readable text`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()

        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        // Use a reset time 2 hours in the future
        let futureDate = Date().addingTimeInterval(2 * 3600 + 15 * 60) // 2h 15m from now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let resetTimeString = formatter.string(from: futureDate)

        let quotaResponse = """
        {
            "buckets": [
                {
                    "modelId": "gemini-pro",
                    "remainingFraction": 0.8,
                    "resetTime": "\(resetTimeString)"
                }
            ]
        }
        """.data(using: .utf8)!

        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("projects") {
                    return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                } else {
                    return (quotaResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            }

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1
        )

        let snapshot = try await probe.probe()
        let quota = try #require(snapshot.quotas.first)

        // resetsAt should be a parsed Date, not nil
        let resetsAt = try #require(quota.resetsAt)
        let timeDiff = abs(resetsAt.timeIntervalSince(futureDate))
        #expect(timeDiff < 2) // Within 2 seconds tolerance

        // resetText should be human-readable, not raw ISO 8601
        let resetText = try #require(quota.resetText)
        #expect(resetText.contains("Resets in"))
        #expect(!resetText.contains("T"))  // Should NOT contain ISO 8601 'T' separator
    }

    @Test
    func `probe handles api error gracefully`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()
        
        given(mockService)
            .request(.any)
            .willProduce { _ in
                (Data(), HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            }
            
        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1
        )

        await #expect(throws: ProbeError.executionFailed("HTTP 500")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe refreshes token and retries after 401`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()
        let mockExecutor = MockCLIExecutor()

        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        let quotaResponse = """
        {
            "buckets": [
                {
                    "modelId": "gemini-pro",
                    "remainingFraction": 0.8,
                    "resetTime": "2025-12-21T12:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        var quotaCalls = 0
        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("retrieveUserQuota") {
                    quotaCalls += 1
                    if quotaCalls == 1 {
                        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                    }
                    return (quotaResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

        given(mockExecutor).locate(.value("gemini")).willReturn("/usr/local/bin/gemini")
        given(mockExecutor).execute(
            binary: .value("gemini"),
            args: .value([]),
            input: .value("/quit\n"),
            timeout: .value(15.0),
            workingDirectory: .value(nil),
            autoResponses: .value([:])
        ).willReturn(CLIResult(output: ""))

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1,
            cliExecutor: mockExecutor
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
        verify(mockExecutor).execute(
            binary: .value("gemini"),
            args: .value([]),
            input: .value("/quit\n"),
            timeout: .value(15.0),
            workingDirectory: .value(nil),
            autoResponses: .value([:])
        ).called(1)
    }

    @Test
    func `probe returns authentication required when refresh cli is missing`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()
        let mockExecutor = MockCLIExecutor()

        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("retrieveUserQuota") {
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                }
                return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

        given(mockExecutor).locate(.value("gemini")).willReturn(nil)

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1,
            cliExecutor: mockExecutor
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe returns authentication required when retry still 401`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()
        let mockExecutor = MockCLIExecutor()

        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        var quotaCalls = 0
        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("retrieveUserQuota") {
                    quotaCalls += 1
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                }
                return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

        given(mockExecutor).locate(.value("gemini")).willReturn("/usr/local/bin/gemini")
        given(mockExecutor).execute(
            binary: .value("gemini"),
            args: .value([]),
            input: .value("/quit\n"),
            timeout: .value(15.0),
            workingDirectory: .value(nil),
            autoResponses: .value([:])
        ).willReturn(CLIResult(output: ""))

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1,
            cliExecutor: mockExecutor
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe returns error when retry fails with http error`() async throws {
        let homeDir = try makeTemporaryHomeDirectory()
        try createCredentialsFile(in: homeDir)
        let mockService = MockNetworkClient()
        let mockExecutor = MockCLIExecutor()

        let projectsResponse = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123456" }
            ]
        }
        """.data(using: .utf8)!

        var quotaCalls = 0
        given(mockService)
            .request(.any)
            .willProduce { request in
                let url = request.url?.absoluteString ?? ""
                if url.contains("retrieveUserQuota") {
                    quotaCalls += 1
                    if quotaCalls == 1 {
                        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                    }
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
                }
                return (projectsResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

        given(mockExecutor).locate(.value("gemini")).willReturn("/usr/local/bin/gemini")
        given(mockExecutor).execute(
            binary: .value("gemini"),
            args: .value([]),
            input: .value("/quit\n"),
            timeout: .value(15.0),
            workingDirectory: .value(nil),
            autoResponses: .value([:])
        ).willReturn(CLIResult(output: ""))

        let probe = GeminiAPIProbe(
            homeDirectory: homeDir.path,
            timeout: 1.0,
            networkClient: mockService,
            maxRetries: 1,
            cliExecutor: mockExecutor
        )

        await #expect(throws: ProbeError.executionFailed("HTTP 500")) {
            try await probe.probe()
        }
    }
}
