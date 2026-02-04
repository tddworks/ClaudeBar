import Foundation

internal struct GeminiProject: Decodable, Sendable {
    let projectId: String
    let labels: [String: String]?
    
    var isCLIProject: Bool {
        projectId.hasPrefix("gen-lang-client")
    }
    
    var hasGenerativeLanguageLabel: Bool {
        labels?["generative-language"] != nil
    }
}

internal struct GeminiProjects: Decodable, Sendable {
    let projects: [GeminiProject]
    
    var bestProjectForQuota: GeminiProject? {
        // Prefer CLI-created projects (gen-lang-client-*)
        if let cliProject = projects.first(where: { $0.isCLIProject }) {
            return cliProject
        }
        // Fallback to any project with the generative-language label
        if let labeledProject = projects.first(where: { $0.hasGenerativeLanguageLabel }) {
            return labeledProject
        }
        // Final fallback: use any available project
        // This handles users who don't have a CLI-created project but have other GCP projects
        return projects.first
    }
}
