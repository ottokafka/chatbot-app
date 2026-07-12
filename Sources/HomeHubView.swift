import SwiftUI

/// Cold-start feature selection hub (Life Path, Flashcards, Chat).
struct HomeHubView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var chatVM: ChatViewModel
    /// Compact iOS: reveal the split-view sidebar column.
    var onPreferSidebar: () -> Void = {}
    @Environment(\.appLanguage) private var lang

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 16)]
    }

    private var chatSubtitle: String {
        if let title = chatVM.activeConversation?.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return L10n.startNewChat(lang)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.homeTitle(lang))
                    .font(.largeTitle.weight(.bold))
                Text(L10n.homeSubtitle(lang))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 16) {
                    featureCard(
                        title: L10n.lifePathTitle(lang),
                        subtitle: L10n.lifePathBrowseHelp(lang),
                        systemImage: AppRouteChrome.systemImage(.lifePath),
                        route: .lifePath
                    )
                    featureCard(
                        title: L10n.flashcards(lang),
                        subtitle: L10n.flashcardsWithDue(lang, due: flashcardVM.dueCount),
                        systemImage: AppRouteChrome.systemImage(.flashcards),
                        route: .flashcards
                    )
                    featureCard(
                        title: L10n.conversations(lang),
                        subtitle: chatSubtitle,
                        systemImage: AppRouteChrome.systemImage(.chat),
                        route: .chat
                    )
                }

                restoreLastAppSection
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground)
        .compactFeatureChrome(
            nav: nav,
            lang: lang,
            dueCount: flashcardVM.dueCount,
            onPreferSidebar: onPreferSidebar
        )
    }

    private var restoreLastAppSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $nav.restoreLastRouteOnLaunch) {
                Text(L10n.restoreLastApp(lang))
                    .font(.body)
            }
            .toggleStyle(.switch)
            .help(L10n.restoreLastAppHelp(lang))

            Text(L10n.restoreLastAppHelp(lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.platformWindowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func featureCard(
        title: String,
        subtitle: String,
        systemImage: String,
        route: AppRoute
    ) -> some View {
        Button {
            nav.navigate(to: route, source: .homeTile)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(height: 32)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.platformWindowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.featureCardOpen(lang))
    }
}
