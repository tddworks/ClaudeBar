import AppKit
import Diagnostics
import Observation
import UniformTypeIdentifiers

/// Where a report leaves the app: the save panel, the write, the file opened
/// once saved. The card tells it `save(report)` and shows `failure` — it never
/// opens a panel or writes a file itself. A write that fails is kept as the
/// person's to read, not only the log's.
@MainActor
@Observable
final class ReportSaver {
    /// Why the last save failed, until the person dismisses it.
    private(set) var failure: String?

    /// Asks where to save `report`, writes it there and opens it.
    func save(_ report: RecapHTMLReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = report.fileName
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                guard let self, self.write(report, to: url) else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Writes `report` to `url` at once, whole or not at all. A failed write
    /// becomes `failure`; a written one clears it.
    @discardableResult
    func write(_ report: RecapHTMLReport, to url: URL) -> Bool {
        do {
            try report.html.write(to: url, atomically: true, encoding: .utf8)
            failure = nil
            return true
        } catch {
            AppLog.ui.error("The recap report could not be written: \(error.localizedDescription)")
            failure = error.localizedDescription
            return false
        }
    }

    /// The person read why the save failed.
    func dismissFailure() {
        failure = nil
    }
}
