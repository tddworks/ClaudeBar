import SwiftUI
import Infrastructure
import UniformTypeIdentifiers

/// Import button for terminal color scheme files.
///
/// Currently supports `.itermcolors` (iTerm2 export format, compatible with 450+ schemes
/// from [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)).
/// The architecture supports adding more formats via new parsers.
struct ThemeImportButton: View {
    @Environment(\.appTheme) private var theme
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importedThemeName: String?

    var body: some View {
        VStack(spacing: 6) {
            Button {
                isImporting = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Import Theme")
                        .font(theme.font(size: 11, weight: .medium))
                }
                .foregroundStyle(theme.isOutlined ? theme.textPrimary : theme.accentPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: theme.isOutlined ? 999 : 8)
                        .fill(theme.isOutlined ? theme.glassBackground : theme.accentPrimary.opacity(0.1))
                        .themeShadow(theme, scale: 0.6)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.isOutlined ? 999 : 8)
                                .stroke(theme.isOutlined ? theme.glassBorder : theme.accentPrimary.opacity(0.3), lineWidth: theme.cardBorderWidth)
                        )
                )
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "itermcolors") ?? .propertyList],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }

            if let error = importError {
                Text(error)
                    .font(theme.font(size: 9))
                    .foregroundStyle(theme.statusCritical)
            }

            if let name = importedThemeName {
                Text("Imported: \(name)")
                    .font(theme.font(size: 9))
                    .foregroundStyle(theme.statusHealthy)
            }
        }
    }

    @MainActor private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        importedThemeName = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let importedTheme = try ThemeRegistry.shared.importItermcolors(from: url)
                importedThemeName = importedTheme.displayName
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
