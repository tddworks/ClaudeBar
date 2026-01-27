import Testing
import Foundation
@testable import Infrastructure

@Suite
struct GeminiProjectTests {

    // MARK: - isCLIProject Tests

    @Test
    func `isCLIProject returns true for gen-lang-client prefix`() {
        // Given
        let project = GeminiProject(projectId: "gen-lang-client-123456", labels: nil)

        // Then
        #expect(project.isCLIProject == true)
    }

    @Test
    func `isCLIProject returns true for gen-lang-client with longer suffix`() {
        // Given
        let project = GeminiProject(projectId: "gen-lang-client-0123456789-abcdef", labels: nil)

        // Then
        #expect(project.isCLIProject == true)
    }

    @Test
    func `isCLIProject returns false for other project IDs`() {
        // Given
        let project = GeminiProject(projectId: "my-awesome-project", labels: nil)

        // Then
        #expect(project.isCLIProject == false)
    }

    @Test
    func `isCLIProject returns false for similar but different prefix`() {
        // Given
        let project = GeminiProject(projectId: "gen-lang-server-123456", labels: nil)

        // Then
        #expect(project.isCLIProject == false)
    }

    // MARK: - hasGenerativeLanguageLabel Tests

    @Test
    func `hasGenerativeLanguageLabel returns true when label exists`() {
        // Given
        let project = GeminiProject(
            projectId: "my-project",
            labels: ["generative-language": "true"]
        )

        // Then
        #expect(project.hasGenerativeLanguageLabel == true)
    }

    @Test
    func `hasGenerativeLanguageLabel returns true regardless of label value`() {
        // Given
        let project = GeminiProject(
            projectId: "my-project",
            labels: ["generative-language": "any-value"]
        )

        // Then
        #expect(project.hasGenerativeLanguageLabel == true)
    }

    @Test
    func `hasGenerativeLanguageLabel returns false when label missing`() {
        // Given
        let project = GeminiProject(
            projectId: "my-project",
            labels: ["other-label": "value"]
        )

        // Then
        #expect(project.hasGenerativeLanguageLabel == false)
    }

    @Test
    func `hasGenerativeLanguageLabel returns false when labels nil`() {
        // Given
        let project = GeminiProject(projectId: "my-project", labels: nil)

        // Then
        #expect(project.hasGenerativeLanguageLabel == false)
    }

    @Test
    func `hasGenerativeLanguageLabel returns false when labels empty`() {
        // Given
        let project = GeminiProject(projectId: "my-project", labels: [:])

        // Then
        #expect(project.hasGenerativeLanguageLabel == false)
    }
}

@Suite
struct GeminiProjectsTests {

    // MARK: - bestProjectForQuota Tests

    @Test
    func `bestProjectForQuota prefers CLI project`() {
        // Given
        let cliProject = GeminiProject(projectId: "gen-lang-client-123", labels: nil)
        let labeledProject = GeminiProject(
            projectId: "other-project",
            labels: ["generative-language": "true"]
        )
        let projects = GeminiProjects(projects: [labeledProject, cliProject])

        // When
        let best = projects.bestProjectForQuota

        // Then
        #expect(best?.projectId == "gen-lang-client-123")
    }

    @Test
    func `bestProjectForQuota falls back to labeled project when no CLI project`() {
        // Given
        let labeledProject = GeminiProject(
            projectId: "labeled-project",
            labels: ["generative-language": "true"]
        )
        let regularProject = GeminiProject(projectId: "regular-project", labels: nil)
        let projects = GeminiProjects(projects: [regularProject, labeledProject])

        // When
        let best = projects.bestProjectForQuota

        // Then
        #expect(best?.projectId == "labeled-project")
    }

    @Test
    func `bestProjectForQuota falls back to any project when no CLI or labeled project`() {
        // Given
        let regularProject = GeminiProject(projectId: "regular-project", labels: nil)
        let projects = GeminiProjects(projects: [regularProject])

        // When
        let best = projects.bestProjectForQuota

        // Then - should return the regular project as a fallback
        #expect(best?.projectId == "regular-project")
    }

    @Test
    func `bestProjectForQuota returns nil for empty projects`() {
        // Given
        let projects = GeminiProjects(projects: [])

        // When
        let best = projects.bestProjectForQuota

        // Then
        #expect(best == nil)
    }

    @Test
    func `bestProjectForQuota returns first CLI project when multiple exist`() {
        // Given
        let cliProject1 = GeminiProject(projectId: "gen-lang-client-111", labels: nil)
        let cliProject2 = GeminiProject(projectId: "gen-lang-client-222", labels: nil)
        let projects = GeminiProjects(projects: [cliProject1, cliProject2])

        // When
        let best = projects.bestProjectForQuota

        // Then
        #expect(best?.projectId == "gen-lang-client-111")
    }

    @Test
    func `bestProjectForQuota CLI project takes precedence over labeled project`() {
        // Given - labeled project comes first in array
        let labeledProject = GeminiProject(
            projectId: "labeled-first",
            labels: ["generative-language": "true"]
        )
        let cliProject = GeminiProject(projectId: "gen-lang-client-123", labels: nil)
        let projects = GeminiProjects(projects: [labeledProject, cliProject])

        // When
        let best = projects.bestProjectForQuota

        // Then - CLI project should still win
        #expect(best?.projectId == "gen-lang-client-123")
    }
}
