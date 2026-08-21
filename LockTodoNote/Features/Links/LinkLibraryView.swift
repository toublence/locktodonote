import SwiftUI
import LockTodoNoteShared

/// Everything shared into the app from the share sheet.
struct LinkLibraryView: View {
    @EnvironmentObject private var linkStore: LinkStore
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if linkStore.links.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(linkStore.links) { link in
                        LinkRow(link: link) {
                            guard let destination = link.destination else { return }
                            openURL(destination)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            linkStore.delete(id: linkStore.links[index].id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(palette.background)
        .navigationTitle(appString(localized: "links.title", defaultValue: "Saved links"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { linkStore.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(palette.textTertiary)
            Text(appString(localized: "links.empty", defaultValue: "Nothing saved yet"))
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Text(
                appString(localized: "links.emptyDetail",
                    defaultValue: "Share a link or some text to LockTodoNote and it will appear here."
                )
            )
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LinkRow: View {
    let link: SavedLink
    let onOpen: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: link.isTextOnly ? "text.quote" : "link")
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !link.domain.isEmpty {
                        Text(link.domain)
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                if !link.isTextOnly {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(link.isTextOnly)
        .accessibilityElement(children: .combine)
    }
}
