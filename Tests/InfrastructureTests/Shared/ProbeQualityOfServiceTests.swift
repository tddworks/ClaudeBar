import Domain
import Foundation
import Testing

@testable import Infrastructure

/// Guards the issue-#204 behaviour through the async `CLIExecutor` boundary.
///
/// `ProbeExecutionContext.qualityOfService` is a task local, and task locals do
/// not survive a hop onto a plain thread or GCD queue. `DefaultCLIExecutor` now
/// makes exactly that hop to keep blocking PTY work off the cooperative pool, so
/// the QoS must be captured into `Options` beforehand — otherwise background
/// refreshes silently spawn at `.default` and the idle heat #204 fixed returns.
@Suite("Probe quality of service")
struct ProbeQualityOfServiceTests {

    @Test("Options capture the ambient probe QoS at construction")
    func optionsCaptureAmbientQoS() async {
        await ProbeExecutionContext.$qualityOfService.withValue(.utility) {
            let options = InteractiveRunner.Options()
            #expect(options.qualityOfService == .utility)
        }
    }

    @Test("Options default to .default outside a bound scope")
    func optionsDefaultOutsideScope() {
        let options = InteractiveRunner.Options()
        #expect(options.qualityOfService == .default)
    }

    @Test("An explicit QoS overrides the ambient value")
    func explicitQoSWins() async {
        await ProbeExecutionContext.$qualityOfService.withValue(.utility) {
            let options = InteractiveRunner.Options(qualityOfService: .userInitiated)
            #expect(options.qualityOfService == .userInitiated)
        }
    }

    @Test("Captured QoS survives the hop off the cooperative pool")
    func qosSurvivesThreadHop() async throws {
        // Reading the task local from the queue the executor dispatches to would
        // yield `.default`; reading the captured copy must still yield `.utility`.
        let captured: QualityOfService = await ProbeExecutionContext.$qualityOfService
            .withValue(.utility) {
                let options = InteractiveRunner.Options()
                return await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        continuation.resume(returning: options.qualityOfService)
                    }
                }
            }

        #expect(captured == .utility)
    }

    @Test("The task local itself is lost across the same hop")
    func taskLocalIsLostAcrossHop() async {
        // Documents *why* the capture exists: this is the value the runner would
        // have read had it kept consulting the task local directly.
        let observed: QualityOfService = await ProbeExecutionContext.$qualityOfService
            .withValue(.utility) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        continuation.resume(returning: ProbeExecutionContext.qualityOfService)
                    }
                }
            }

        #expect(observed == .default)
    }
}
