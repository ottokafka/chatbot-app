import SwiftUI

/// App root: window-scoped VMs, navigation split, feature shells, and shared sheets (D21).
public struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var flashcardVM = FlashcardViewModel()
    @StateObject private var speakingVM = SpeakingSessionViewModel()
    @StateObject private var nav = AppNavigationModel(defaultRoute: .home)

    public init() {}

    @State private var isShowingPromptModal = false
    @State private var isShowingEndpointModal = false
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 160
    @State private var selectedFlashcard: Flashcard?
    #if os(iOS)
    /// Compact iOS only: which column to show. Unbound on macOS.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    #endif

    public var body: some View {
        #if os(iOS)
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            sidebar
        } detail: {
            detailColumn
        }
        .environment(\.appLanguage, viewModel.appLanguage)
        #else
        // macOS: keep unbound split — avoid behavioral drift from binding column state
        NavigationSplitView {
            sidebar
        } detail: {
            detailColumn
        }
        .environment(\.appLanguage, viewModel.appLanguage)
        .frame(minWidth: 800, minHeight: 600)
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        AppSidebarView(
            nav: nav,
            viewModel: viewModel,
            flashcardVM: flashcardVM,
            speakingVM: speakingVM,
            selectedFlashcard: $selectedFlashcard,
            configureSpeaking: { configureSpeakingFromChat() },
            onPreferDetail: { preferDetailColumn() }
        )
    }

    // MARK: - Detail

    private var detailColumn: some View {
        Group {
            switch nav.route {
            case .home:
                HomeHubView(
                    nav: nav,
                    flashcardVM: flashcardVM,
                    chatVM: viewModel,
                    onPreferSidebar: { preferSidebarColumn() }
                )
            case .lifePath:
                LifePathRootView(
                    nav: nav,
                    flashcardVM: flashcardVM,
                    chatVM: viewModel,
                    onExit: { nav.goHome(source: .done) },
                    onPreferSidebar: { preferSidebarColumn() }
                )
            case .flashcards:
                FlashcardsShellView(
                    nav: nav,
                    flashcardVM: flashcardVM,
                    speakingVM: speakingVM,
                    llmEndpoint: viewModel.llmURL,
                    llmModel: viewModel.llmModel,
                    configureSpeaking: { configureSpeakingFromChat() },
                    dismissPracticeForSpeaking: { dismissPracticeForSpeaking() },
                    endSpeakingForPractice: { endSpeakingForPractice() },
                    onPreferSidebar: { preferSidebarColumn() }
                )
            case .chat:
                ChatShellView(
                    nav: nav,
                    viewModel: viewModel,
                    flashcardVM: flashcardVM,
                    isShowingPromptModal: $isShowingPromptModal,
                    isShowingEndpointModal: $isShowingEndpointModal,
                    isLogsExpanded: $isLogsExpanded,
                    logsHeight: $logsHeight,
                    onPreferSidebar: { preferSidebarColumn() }
                )
            }
        }
        .modifier(ContentViewSheets(
            viewModel: viewModel,
            flashcardVM: flashcardVM,
            speakingVM: speakingVM,
            isShowingPromptModal: $isShowingPromptModal,
            isShowingEndpointModal: $isShowingEndpointModal,
            configureSpeaking: { configureSpeakingFromChat() },
            dismissPracticeForSpeaking: { dismissPracticeForSpeaking() },
            endSpeakingForPractice: { endSpeakingForPractice() }
        ))
        .onAppear {
            flashcardVM.onLog = { message in
                viewModel.log(message, tag: "DB")
            }
            flashcardVM.loadFlashcards()
            nav.persistCurrentRouteIfNeeded()
            if nav.didRestoreRouteOnLaunch {
                viewModel.log(
                    "Nav: cold start restored \(nav.route.rawValue)",
                    tag: "NAV"
                )
            }
            // Always prefer detail on cold start (initial route does not fire onChange).
            preferDetailColumn()
        }
        .onChange(of: nav.route) { oldRoute, newRoute in
            prepareRouteChange(from: oldRoute, to: newRoute)
            preferDetailColumn()
        }
        .onChange(of: flashcardVM.flashcards) { _, _ in
            if let selected = selectedFlashcard,
               !flashcardVM.flashcards.contains(where: { $0.id == selected.id }) {
                selectedFlashcard = nil
            }
        }
        .onChange(of: flashcardVM.isGeneratingPractice) { _, generating in
            if generating { endSpeakingForPractice() }
        }
        .onChange(of: flashcardVM.isShowingPracticePreview) { _, showing in
            if showing { endSpeakingForPractice() }
        }
        .onChange(of: flashcardVM.isShowingPracticeSession) { _, showing in
            if showing { endSpeakingForPractice() }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Compact column presentation (iOS only)

    /// NAV tag logger for column presentation (preferDetail / preferSidebar).
    private func logNavPresentation(_ message: String) {
        viewModel.log(message, tag: "NAV")
    }

    /// Show the detail column on compact width. No-op on macOS.
    /// Logs `Nav: preferDetail` (or `Nav: preferSidebar` under DEBUG sidebar-first) on each call.
    private func preferDetailColumn() {
        #if os(iOS)
        #if DEBUG
        // Force sidebar-first for repro of the original compact bug.
        // When set, the real prefer-detail path never runs — easy to mis-report QA.
        if UserDefaults.standard.bool(forKey: "app.navigation.debugCompactSidebarFirst") {
            if !Self.didLogDebugSidebarFirst {
                Self.didLogDebugSidebarFirst = true
                viewModel.log(
                    "Nav: debugCompactSidebarFirst active — forcing sidebar (preferDetail skipped)",
                    tag: "NAV"
                )
            }
            AppNavigationPresentation.preferSidebar(
                column: $preferredCompactColumn,
                onLog: logNavPresentation
            )
            return
        }
        #endif
        AppNavigationPresentation.preferDetail(
            column: $preferredCompactColumn,
            onLog: logNavPresentation
        )
        #endif
    }

    #if os(iOS) && DEBUG
    /// Once-per-process notice so QA sees the override without log spam.
    private static var didLogDebugSidebarFirst = false
    #endif

    // PR-2: CompactFeatureChrome toolbar/back will call this to reveal the sidebar.
    /// Reveal the sidebar column on compact width. No-op on macOS.
    /// Logs `Nav: preferSidebar` on each call.
    private func preferSidebarColumn() {
        #if os(iOS)
        AppNavigationPresentation.preferSidebar(
            column: $preferredCompactColumn,
            onLog: logNavPresentation
        )
        #endif
    }

    // MARK: - Route transitions

    private func releaseSharedAudioHardware() {
        viewModel.yieldAudioHardwareForExternalSession()
    }

    private func prepareRouteChange(from: AppRoute, to: AppRoute) {
        releaseSharedAudioHardware()

        switch from {
        case .flashcards:
            endSpeakingForPractice()
            if flashcardVM.isShowingPracticePreview
                || flashcardVM.isShowingPracticeSession
                || flashcardVM.pendingPracticeSessionStart
                || flashcardVM.isGeneratingPractice {
                flashcardVM.discardPracticePack()
            }
            if flashcardVM.isShowingReviewSession {
                flashcardVM.endReviewSession()
            }
            if flashcardVM.isShowingCreateSheet {
                flashcardVM.isShowingCreateSheet = false
                if flashcardVM.draft != nil {
                    flashcardVM.cancelDraft()
                }
            }
            flashcardVM.isShowingEssentialVocab = false

        case .lifePath:
            viewModel.clearEphemeralAudioCache()

        case .chat, .home:
            break
        }

        if to == .flashcards || to == .home {
            flashcardVM.loadFlashcards()
        }

        let source = nav.lastTransition?.source.rawValue ?? "?"
        viewModel.log("Nav: \(from.rawValue) → \(to.rawValue) (via \(source))", tag: "NAV")

        #if DEBUG
        assert(!speakingVM.isShowingSession && !speakingVM.isShowingSetup,
               "Speak UI still presented after leaving \(from)")
        assert(!viewModel.isPlayingAudio,
               "Shared player still active after leaving \(from)")
        if let id = viewModel.currentlyPlayingEphemeralId, id.hasPrefix("lifepath-") {
            assertionFailure("Life Path ephemeral id still set after leave: \(id)")
        }
        #endif
    }

    // MARK: - Speaking wiring (D11, D14, D21)

    private func configureSpeakingFromChat() {
        speakingVM.configureEndpoints(
            llmURL: viewModel.llmURL,
            llmModel: viewModel.llmModel,
            sttURL: viewModel.sttURL,
            ttsURL: viewModel.ttsURL,
            ttsVoice: viewModel.ttsVoice,
            appLanguage: viewModel.appLanguage,
            sttLanguage: viewModel.sttLanguage,
            onLog: { viewModel.log($0) }
        )
        let chat = viewModel
        speakingVM.configureChatAudio(
            yieldHardware: {
                chat.yieldAudioHardwareForExternalSession()
            },
            playEphemeralSpeech: { text, playbackId in
                chat.playEphemeralSpeech(text: text, playbackId: playbackId)
            },
            isGeneratingEphemeral: { id in
                chat.isGeneratingEphemeralAudio(id: id)
            },
            isPlayingEphemeral: { id in
                chat.isPlayingEphemeralAudio(id: id)
            },
            stopPlayback: {
                chat.stopPlayback()
            }
        )
    }

    private func dismissPracticeForSpeaking() {
        if flashcardVM.isShowingPracticePreview
            || flashcardVM.isShowingPracticeSession
            || flashcardVM.pendingPracticeSessionStart
            || flashcardVM.isGeneratingPractice {
            flashcardVM.discardPracticePack()
        }
    }

    private func endSpeakingForPractice() {
        if speakingVM.isShowingSetup
            || speakingVM.isShowingSession
            || speakingVM.pendingSessionStart
            || speakingVM.isStartingSession
            || speakingVM.session != nil
            || speakingVM.pendingConfig != nil {
            speakingVM.endSession()
            speakingVM.discardSession()
        }
    }
}

// MARK: - Shared feature sheets (kept on root for D21 presentation)

private struct ContentViewSheets: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    @Binding var isShowingPromptModal: Bool
    @Binding var isShowingEndpointModal: Bool
    var configureSpeaking: () -> Void
    var dismissPracticeForSpeaking: () -> Void
    var endSpeakingForPractice: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingPromptModal) {
                SystemPromptModalView(viewModel: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $isShowingEndpointModal) {
                EndpointConfigModalView(viewModel: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingCreateSheet, onDismiss: {
                if flashcardVM.draft != nil {
                    flashcardVM.cancelDraft()
                }
            }) {
                FlashcardCreateSheet(flashcardVM: flashcardVM)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingEssentialVocab) {
                EssentialVocabListView(flashcardVM: flashcardVM)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingReviewSession, onDismiss: {
                flashcardVM.endReviewSession()
                if speakingVM.pendingSetupAfterHostDismiss {
                    speakingVM.pendingSetupAfterHostDismiss = false
                    if speakingVM.pendingConfig != nil {
                        speakingVM.isShowingSetup = true
                    }
                }
            }) {
                FlashcardReviewView(
                    flashcardVM: flashcardVM,
                    chatVM: viewModel,
                    speakingVM: speakingVM,
                    configureSpeaking: configureSpeaking,
                    dismissPracticeForSpeaking: dismissPracticeForSpeaking
                )
                .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingPracticePreview, onDismiss: {
                if flashcardVM.pendingPracticeSessionStart {
                    flashcardVM.presentPendingPracticeSessionIfNeeded()
                } else if !flashcardVM.isShowingPracticeSession {
                    flashcardVM.discardPracticePack()
                }
            }) {
                PracticePreviewSheet(flashcardVM: flashcardVM)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingPracticeSession, onDismiss: {
                flashcardVM.discardPracticePack()
            }) {
                PracticeSessionView(flashcardVM: flashcardVM, chatVM: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $speakingVM.isShowingSetup, onDismiss: {
                if speakingVM.pendingSessionStart {
                    speakingVM.presentPendingSessionIfNeeded()
                } else if !speakingVM.isShowingSession && speakingVM.session == nil {
                    speakingVM.discardSession()
                }
            }) {
                SpeakingSetupSheet(speakingVM: speakingVM, flashcardVM: flashcardVM)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $speakingVM.isShowingSession, onDismiss: {
                speakingVM.endSession()
            }) {
                SpeakingSessionView(
                    speakingVM: speakingVM,
                    chatVM: viewModel,
                    flashcardVM: flashcardVM
                )
                .environment(\.appLanguage, viewModel.appLanguage)
            }
    }
}
