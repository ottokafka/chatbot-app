import SwiftUI

/// Sidebar: Apps switcher, contextual lists, language + restore prefs.
struct AppSidebarView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    @Binding var selectedFlashcard: Flashcard?
    /// Wire chat audio into speakingVM before DEBUG sheet.
    var configureSpeaking: () -> Void
    /// Compact iOS: show detail column after non-route actions / same-route re-tap.
    var onPreferDetail: () -> Void = {}

    @Environment(\.appLanguage) private var lang
    #if DEBUG
    @State private var isShowingSpeakingDebug = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    ForEach(AppRoute.allCases) { route in
                        sidebarRouteRow(
                            route,
                            title: AppRouteChrome.title(
                                route,
                                lang: lang,
                                dueCount: route == .flashcards ? flashcardVM.dueCount : nil
                            ),
                            systemImage: AppRouteChrome.systemImage(route)
                        )
                    }
                } header: {
                    Text(L10n.appsSection(lang))
                }

                switch nav.route {
                case .home, .lifePath:
                    EmptyView()
                case .flashcards:
                    flashcardsSection
                case .chat:
                    conversationsSection
                }
            }
            .listStyle(.sidebar)

            Divider()
                .padding(.horizontal)

            LanguageToggle(language: $viewModel.appLanguage)
                .padding(.horizontal)
                .padding(.top, 8)

            Toggle(isOn: $nav.restoreLastRouteOnLaunch) {
                Text(L10n.restoreLastApp(lang))
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .help(L10n.restoreLastAppHelp(lang))

            #if DEBUG
            Button {
                configureSpeaking()
                isShowingSpeakingDebug = true
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                    Text("Speak Debug")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .help("DEBUG: Speaking with AI (typed + voice STT/TTS)")
            #endif
        }
        .navigationTitle(sidebarTitle)
        .frame(minWidth: 200, idealWidth: 240)
        #if DEBUG
        .sheet(isPresented: $isShowingSpeakingDebug) {
            SpeakingSessionDebugView(speakingVM: speakingVM)
        }
        #endif
    }

    private var sidebarTitle: String {
        AppRouteChrome.title(nav.route, lang: lang)
    }

    @ViewBuilder
    private var flashcardsSection: some View {
        Section {
            ForEach(flashcardVM.flashcardsForSelectedKind) { card in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front)
                            .lineLimit(1)
                            .font(.body)
                        Text(flashcardVM.dueLabel(for: card, language: lang))
                            .font(.caption2)
                            .foregroundColor(flashcardVM.isDue(card) ? .orange : .secondary)
                    }
                    Spacer()
                    Button {
                        flashcardVM.deleteFlashcard(card)
                        if selectedFlashcard?.id == card.id {
                            selectedFlashcard = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.deleteFlashcardHelp(lang))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFlashcard = card
                    onPreferDetail()
                }
                .listRowBackground(
                    selectedFlashcard?.id == card.id
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
            }
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        Section {
            Button {
                viewModel.startNewConversation()
                onPreferDetail()
            } label: {
                Label(L10n.newChat(lang), systemImage: "plus.bubble")
                    .font(.headline)
            }
            ForEach(viewModel.conversations) { conversation in
                HStack {
                    Image(systemName: "message")
                        .foregroundColor(.secondary)
                    Text(conversation.title)
                        .lineLimit(1)
                        .font(.body)
                    Spacer()
                    Button {
                        viewModel.deleteConversation(conversation)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.deleteConversation(lang))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectConversation(conversation)
                    onPreferDetail()
                }
                .listRowBackground(
                    viewModel.activeConversation?.id == conversation.id
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
            }
        }
    }

    @ViewBuilder
    private func sidebarRouteRow(_ route: AppRoute, title: String, systemImage: String) -> some View {
        Button {
            if nav.route == route {
                // navigate() no-ops; onChange will not fire — still show detail on compact.
                onPreferDetail()
            } else {
                nav.navigate(to: route, source: .switcher)
                // preferDetail also runs from ContentView onChange(route) after successful navigate
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fontWeight(nav.route == route ? .semibold : .regular)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            nav.route == route
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
    }
}
