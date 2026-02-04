import Foundation
import Domain
import os.log

private let logger = Logger(subsystem: "com.claudebar", category: "GeminiProjectRepository")

internal struct GeminiProjectRepository {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private let maxRetries: Int
    private static let projectsEndpoint = "https://cloudresourcemanager.googleapis.com/v1/projects"

    init(
        networkClient: any NetworkClient,
        timeout: TimeInterval,
        maxRetries: Int = 3
    ) {
        self.networkClient = networkClient
        self.timeout = timeout
        self.maxRetries = maxRetries
    }

    /// Fetches the best Gemini project to use for quota checking.
    /// Includes retry logic for cold-start network delays.
    func fetchBestProject(accessToken: String) async -> GeminiProject? {
        guard let projects = await fetchProjects(accessToken: accessToken) else { return nil }
        return projects.bestProjectForQuota
    }

    /// Fetches all available Gemini projects with retry logic.
    /// On cold start, network may not be immediately responsive.
    func fetchProjects(accessToken: String) async -> GeminiProjects? {
        guard let url = URL(string: Self.projectsEndpoint) else {
            logger.error("Invalid projects endpoint URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        // Retry with exponential backoff for cold-start network delays
        var lastError: Error?
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                // Exponential backoff: 200ms, 500ms, 1000ms
                let delay = UInt64(200_000_000 * (attempt + 1))
                logger.debug("Gemini project discovery: retry \(attempt + 1)/\(self.maxRetries) after delay")
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                let (data, response) = try await networkClient.request(request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    logger.warning("Gemini project discovery: invalid response type")
                    continue
                }

                if httpResponse.statusCode == 200 {
                    if let projects = try? JSONDecoder().decode(GeminiProjects.self, from: data) {
                        logger.debug("Gemini project discovery: found \(projects.projects.count) projects")
                        return projects
                    } else {
                        logger.warning("Gemini project discovery: failed to decode response")
                    }
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    // Auth errors won't be fixed by retrying
                    logger.error("Gemini project discovery: auth error \(httpResponse.statusCode)")
                    return nil
                } else {
                    logger.warning("Gemini project discovery: HTTP \(httpResponse.statusCode)")
                }
            } catch let error as URLError where error.code == .timedOut {
                logger.warning("Gemini project discovery: timeout (attempt \(attempt + 1))")
                lastError = error
            } catch {
                logger.warning("Gemini project discovery: \(error.localizedDescription)")
                lastError = error
            }
        }

        if let lastError {
            logger.error("Gemini project discovery failed after \(self.maxRetries) attempts: \(lastError.localizedDescription)")
        }
        return nil
    }
}
