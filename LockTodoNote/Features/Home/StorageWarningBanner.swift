import SwiftUI

/// Shown when an edit did not reach disk. Without it a failed write looks
/// identical to a successful one until the app is relaunched and the change is
/// gone — the worst way for a user to discover a storage problem.
struct StorageWarningBanner: View {
    @EnvironmentObject private var cardStore: CardStore
    @Environment(\.palette) private var palette

    var body: some View {
        if let error = cardStore.storeError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message(for: error))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                    Text(error.detail)
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceSoft)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(height: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func message(for error: CardStore.StoreError) -> String {
        error.isWriteFailure
            ? appString(localized: "storage.writeFailed",
                defaultValue: "This change could not be saved. Reopen the app before making more edits."
            )
            : appString(localized: "storage.readFailed",
                defaultValue: "Your saved items could not be loaded. They have not been deleted."
            )
    }
}
