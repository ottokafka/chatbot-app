import SwiftUI
import FSRS

struct LifePathRootView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var chatVM: ChatViewModel
    /// Leave Life Path feature (typically `nav.goHome`).
    var onExit: () -> Void = {}
    /// Compact iOS: reveal the split-view sidebar column (unused when leading is owned by Home/Cancel).
    var onPreferSidebar: () -> Void = {}
    @StateObject private var vm = LifePathViewModel()
    @Environment(\.appLanguage) private var lang
    @State private var showResetConfirm = false
    @State private var songBreakEnabled = LifePathPreferences.songBreakEnabled
    @FocusState private var isPlayFocused: Bool
    #if os(macOS)
    /// Bottom console (same pattern as ChatShellView) for pronunciation / Life Path debug.
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 180
    #endif

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                Group {
                    if vm.showLanguagePicker {
                        languagePicker
                    } else if let error = vm.loadError {
                        errorState(error)
                    } else if vm.sessionFinished && !vm.showLevelUp && !vm.isPlaying {
                        sessionSummary
                    } else if vm.isPlaying {
                        playView
                    } else {
                        homeView
                    }
                }
                .navigationTitle(L10n.lifePathTitle(lang))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if vm.showLanguagePicker {
                            Button(L10n.cancel(lang)) {
                                vm.cancelLanguagePicker()
                            }
                        } else if vm.isPlaying {
                            Button(L10n.lifePathEndRound(lang)) {
                                chatVM.stopPlayback()
                                vm.endSession()
                            }
                        } else {
                            Button(L10n.backToHome(lang)) {
                                onExit()
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if vm.isPlaying {
                            autoPlayToggleButton
                        }
                    }
                }
                // Inside stack so Menu appears on Life Path chrome (K5a); no leading sidebar button
                // — leading already has Home / Cancel / End round.
                .compactFeatureChrome(
                    nav: nav,
                    lang: lang,
                    dueCount: flashcardVM.dueCount,
                    onPreferSidebar: onPreferSidebar,
                    showSidebarButton: false
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            Divider()
            LogConsolePanel(
                viewModel: chatVM,
                isExpanded: $isLogsExpanded,
                height: $logsHeight
            )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.attach(flashcardVM: flashcardVM, dbManager: flashcardVM.dbManager)
            // Route Life Path / pronunciation logs into the shared console with clear tags.
            vm.onLog = { [weak chatVM] message in
                chatVM?.log(message, tag: Self.logTag(for: message))
            }
            vm.onRequestExit = onExit
            vm.pronunciationURLProvider = { [weak chatVM] in
                PronunciationEndpoint.resolvedAssessURL(chatVM?.pronunciationURL)
            }
            vm.sttURLProvider = { [weak chatVM] in chatVM?.sttURL ?? "" }
            vm.onStopPlayback = { [weak chatVM] in chatVM?.stopPlayback() }
            vm.songService.llmURL = chatVM.llmURL
            vm.songService.llmModel = chatVM.llmModel
            vm.songService.onLog = { [weak chatVM] message in
                chatVM?.log(message, tag: Self.logTag(for: message))
            }
            songBreakEnabled = LifePathPreferences.songBreakEnabled
            vm.load()
            #if os(macOS)
            chatVM.log("Life Path: console ready (pronunciation logs use [PRON])", tag: "LIFE")
            #endif
        }
        .onChange(of: chatVM.llmURL) { _, url in
            vm.songService.llmURL = url
        }
        .onChange(of: chatVM.llmModel) { _, model in
            vm.songService.llmModel = model
        }
        .onChange(of: vm.isPlaying) { _, playing in
            if playing {
                autoPlayFrontIfNeeded()
            } else {
                chatVM.stopPlayback()
                vm.cancelPronunciationRecording()
            }
        }
        .onChange(of: vm.songBreakPhase) { _, phase in
            if phase == .presenting {
                chatVM.stopPlayback()
            }
        }
        .onChange(of: vm.sessionIndex) { _, _ in
            guard vm.songBreakPhase == .idle else { return }
            autoPlayFrontIfNeeded()
            // Reset any lingering arm when card changes
            if vm.pronunciationState == .idle, vm.isPronunciationEnabled {
                vm.armAutoRecord()
            }
        }
        .modifier(LifePathSongBreakPresenter(
            isPresented: Binding(
                get: { vm.songBreakPhase == .presenting },
                set: { newValue in
                    if !newValue {
                        vm.dismissSongBreak(continueSession: true)
                    }
                }
            ),
            breakContent: {
                LifePathSongBreakView(
                    service: vm.songService,
                    lang: lang,
                    wordChips: vm.songBreakWordChips,
                    onSkip: { vm.dismissSongBreak(continueSession: true) },
                    onFinished: { vm.dismissSongBreak(continueSession: true) },
                    onEndSession: { vm.dismissSongBreak(continueSession: false) }
                )
            }
        ))
        .onChange(of: chatVM.isFlashcardAutoPlayEnabled) { _, enabled in
            if enabled {
                autoPlayFrontIfNeeded()
            } else {
                chatVM.stopPlayback()
            }
        }
        // Auto-start recording once the front audio finishes playing
        .onChange(of: chatVM.isPlayingAudio) { _, isPlaying in
            guard !isPlaying, vm.isPlaying, !vm.sessionFinished else { return }
            guard let card = vm.currentCard else { return }
            let frontId = frontPlaybackId(for: card)
            // Only trigger if it was the front of THIS card that just stopped
            guard chatVM.currentlyPlayingEphemeralId == nil else { return }
            let wasPlayingFront = !chatVM.isPlayingEphemeralAudio(id: frontId)
                && chatVM.isFlashcardAutoPlayEnabled
            if wasPlayingFront, vm.isPronunciationEnabled {
                vm.triggerAutoRecordIfWaiting(for: card.front)
            }
        }
        .onDisappear {
            chatVM.clearEphemeralAudioCache()
        }
        .sheet(isPresented: $vm.showLevelUp) {
            if let notify = vm.pendingLevelUp {
                LifePathLevelUpView(notify: notify, lang: lang) {
                    vm.dismissLevelUp()
                }
            }
        }
        .alert(
            L10n.lifePathErrorTitle(lang),
            isPresented: Binding(
                get: { vm.actionError != nil },
                set: { if !$0 { vm.actionError = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                vm.actionError = nil
            }
        } message: {
            Text(vm.actionError ?? "")
        }
        .alert(
            L10n.lifePathDevResetTitle(lang),
            isPresented: $showResetConfirm
        ) {
            Button(L10n.cancel(lang), role: .cancel) {}
            Button(L10n.lifePathDevResetConfirm(lang), role: .destructive) {
                chatVM.stopPlayback()
                chatVM.clearEphemeralAudioCache()
                vm.resetProgressForTesting()
            }
        } message: {
            Text(L10n.lifePathDevResetMessage(lang))
        }
    }

    // MARK: - Logging

    /// Maps log message content to console tags (PRON / LIFE / AUDIO / ERROR).
    private static func logTag(for message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("[song]") || lower.hasPrefix("[song") || lower.contains("lp_song") {
            return "SONG"
        }
        if lower.contains("error") || lower.contains("failed") || lower.contains("fail:") {
            // Keep pronunciation errors under PRON so the feature stream stays readable.
            if lower.contains("pronunciation") || lower.contains("phoneme") || lower.contains("assess") {
                return "PRON"
            }
            if lower.contains("[song]") {
                return "SONG"
            }
            return "ERROR"
        }
        if lower.contains("pronunciation")
            || lower.contains("phoneme")
            || lower.contains("assess")
            || lower.contains("[pronunciation]") {
            return "PRON"
        }
        if lower.contains("audio") || lower.contains("playback") || lower.contains("tts") {
            return "AUDIO"
        }
        return "LIFE"
    }

    // MARK: - TTS (shared chat ephemeral speech API)

    private func frontPlaybackId(for entry: LifePathEntry) -> String {
        "lifepath-\(entry.id)-front"
    }

    private func backPlaybackId(for entry: LifePathEntry) -> String {
        "lifepath-\(entry.id)-back"
    }

    /// Speaks the current card's front (learning language form) via configured TTS.
    private func autoPlayFrontIfNeeded() {
        guard chatVM.isFlashcardAutoPlayEnabled else { return }
        guard vm.isPlaying, !vm.sessionFinished else { return }
        guard vm.songBreakPhase == .idle else { return }
        guard let card = vm.currentCard else { return }

        let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }

        let playbackId = frontPlaybackId(for: card)
        if chatVM.isPlayingEphemeralAudio(id: playbackId)
            || chatVM.isGeneratingEphemeralAudio(id: playbackId) {
            return
        }

        // Arm auto-record so it fires once the TTS finishes
        if vm.isPronunciationEnabled {
            vm.armAutoRecord()
        }
        chatVM.playEphemeralSpeech(text: front, playbackId: playbackId)
    }

    private func playFront(_ card: LifePathEntry) {
        let text = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatVM.playEphemeralSpeech(text: text, playbackId: frontPlaybackId(for: card))
    }

    private func playBack(_ card: LifePathEntry) {
        let text = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatVM.playEphemeralSpeech(text: text, playbackId: backPlaybackId(for: card))
    }

    private var autoPlayToggleButton: some View {
        Button {
            chatVM.isFlashcardAutoPlayEnabled.toggle()
        } label: {
            Image(systemName: chatVM.isFlashcardAutoPlayEnabled
                  ? "speaker.wave.2.fill"
                  : "speaker.slash")
                .font(.body)
                .foregroundColor(chatVM.isFlashcardAutoPlayEnabled ? .accentColor : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(L10n.autoPlayAudioHelp(lang))
        .accessibilityLabel(L10n.autoPlayAudio(lang))
        .accessibilityValue(
            chatVM.isFlashcardAutoPlayEnabled
                ? Text(lang == .zh ? "开" : "On")
                : Text(lang == .zh ? "关" : "Off")
        )
        .accessibilityHint(L10n.autoPlayAudioHelp(lang))
    }

    // MARK: - Language

    private var languagePicker: some View {
        VStack(spacing: 20) {
            Text(L10n.lifePathPickLanguage(lang))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(L10n.lifePathPickLanguageHint(lang))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                ForEach(LifePathLanguage.allCases) { pathLang in
                    Button {
                        vm.setLanguage(pathLang)
                    } label: {
                        Text(pathLang.displayName(uiLanguage: lang))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: 320)
        }
        .padding(32)
    }

    // MARK: - Home

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                stageRail
                progressCard
                Button {
                    vm.startRound()
                } label: {
                    Label(L10n.lifePathPlay(lang), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canPlay)

                Toggle(isOn: $songBreakEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.lifePathSongBreakToggle(lang))
                        Text(L10n.lifePathSongBreakToggleHint(lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: songBreakEnabled) { _, enabled in
                    LifePathPreferences.songBreakEnabled = enabled
                }
                .padding(.vertical, 4)

                // Temporary DEV control — remove before shipping.
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label(L10n.lifePathDevReset(lang), systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                wordListSection
            }
            .padding(20)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: stageIcon(vm.profile?.currentStageId ?? "baby"))
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.currentStage?.title(for: lang) ?? "—")
                        .font(.title.weight(.bold))
                    if let sub = vm.currentStage?.subtitle(for: lang) {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Text(L10n.lifePathStageProgressSummary(
                lang,
                mastered: vm.masteredInCurrentStage,
                total: vm.totalInCurrentStage
            ))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            Text(L10n.lifePathDueSummary(lang, due: vm.dueCount, newWords: vm.newCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !vm.dueCountByStage.isEmpty {
                Text(dueBreakdownText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !vm.canPlay, let next = vm.nextDueDate {
                Text(L10n.lifePathNextDue(lang, date: next))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dueBreakdownText: String {
        let parts = vm.stages.compactMap { stage -> String? in
            guard let count = vm.dueCountByStage[stage.id], count > 0 else { return nil }
            return "\(stage.title(for: lang)) \(count)"
        }
        guard !parts.isEmpty else { return "" }
        return L10n.lifePathDueBreakdown(lang, parts: parts.joined(separator: " · "))
    }

    private var stageRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vm.stages) { stage in
                    let unlocked = vm.isStageUnlocked(stage.id)
                    let cleared = vm.isStageCleared(stage.id)
                    let current = vm.profile?.currentStageId == stage.id
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(current ? Color.accentColor : (cleared ? Color.green.opacity(0.25) : Color.platformControlBackground))
                                .frame(width: 44, height: 44)
                            Image(systemName: cleared ? "checkmark" : (unlocked ? stageIcon(stage.id) : "lock.fill"))
                                .foregroundStyle(current ? .white : (unlocked ? .primary : .secondary))
                        }
                        Text(stage.title(for: lang))
                            .font(.caption2.weight(current ? .bold : .regular))
                            .foregroundStyle(unlocked ? .primary : .secondary)
                    }
                    .frame(width: 72)
                    .opacity(unlocked ? 1 : 0.55)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.lifePathStageProgress(lang))
                    .font(.headline)
                Spacer()
                Text("\(vm.masteredInCurrentStage)/\(vm.totalInCurrentStage)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: vm.stageProgress)
                .tint(.accentColor)
            Text(L10n.lifePathMasteryHint(lang))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var wordListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.lifePathWords(lang))
                .font(.headline)
            ForEach(vm.currentStageEntries) { entry in
                let status = vm.listRowsByEntryId[entry.id]?.status ?? .locked
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.front)
                            .font(.body.weight(.medium))
                        Text(entry.back)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let phonics = entry.phonics, !phonics.isEmpty {
                            Text(phonics)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(statusLabel(status))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(status).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(status))
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    // MARK: - Play

    private var playView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.lifePathStageSessionProgress(
                            lang,
                            mastered: vm.masteredInCurrentStage,
                            total: vm.totalInCurrentStage
                        ))
                        .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(vm.sessionCorrect)✓  \(vm.sessionWrong)✗")
                            .font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: vm.stageProgress)
                        .tint(.accentColor)
                    Text(L10n.lifePathSessionQueueProgress(
                        lang,
                        done: vm.sessionDoneCount,
                        remaining: vm.sessionRemainingCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if LifePathPreferences.songBreakEnabled {
                        Text(L10n.lifePathSongWordsUntilBreak(
                            lang,
                            remaining: vm.wordsUntilSongBreak,
                            seen: vm.sessionWordsSeenCount,
                            everyN: LifePathSongConfig.effectiveBreakEveryN
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Pronunciation threshold picker
                HStack {
                    Label("Pass at", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { vm.pronunciationThreshold },
                        set: { vm.pronunciationThreshold = $0 }
                    )) {
                        ForEach(LifePathViewModel.availableThresholds, id: \.self) { t in
                            Text("\(Int(t * 100))%").tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.accentColor)
                    Spacer()
                    Toggle(isOn: Binding(
                        get: { vm.isPronunciationEnabled },
                        set: { vm.isPronunciationEnabled = $0 }
                    )) {
                        Text("Pronounce")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal)

                if let card = vm.currentCard {
                    cardFace(card)
                }

                // Pronunciation mic — listen until correct; results stay on screen after misses
                if vm.isPronunciationEnabled {
                    if let card = vm.currentCard {
                        PronunciationMicButton(
                            pronunciationState: vm.pronunciationState,
                            isArmed: vm.isWaitingToAutoRecord,
                            hasStickyResult: vm.lastPronunciationResult.map { $0.overall_score < vm.pronunciationThreshold } ?? false,
                            threshold: vm.pronunciationThreshold,
                            onStart: { vm.startPronunciationRecording(for: card.front) },
                            onStop: { vm.stopPronunciationRecordingAndAssess() },
                            onCancel: { vm.cancelPronunciationRecording() }
                        )
                        .padding(.horizontal)
                    }

                    // Sticky feedback: latest miss stays visible while we keep listening
                    if let result = vm.lastPronunciationResult {
                        PronunciationFeedbackView(
                            result: result,
                            targetWord: vm.pronunciationTargetWord.isEmpty
                                ? (vm.currentCard?.front ?? "")
                                : vm.pronunciationTargetWord,
                            threshold: vm.pronunciationThreshold,
                            isListeningLoop: !result.isPassing(threshold: vm.pronunciationThreshold)
                                && vm.pronunciationState != .idle,
                            showDismiss: !result.isPassing(threshold: vm.pronunciationThreshold),
                            onDismiss: { vm.cancelPronunciationRecording() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                Divider().padding(.horizontal)

                // Manual FSRS grades (escape hatch when not using pronunciation loop)
                if vm.isAnswerRevealed {
                    HStack(spacing: 10) {
                        lifePathGradeButton(title: L10n.gradeAgain(lang), color: .red) {
                            vm.cancelPronunciationRecording()
                            vm.grade(rating: .again)
                        }
                        lifePathGradeButton(title: L10n.gradeHard(lang), color: .orange) {
                            vm.cancelPronunciationRecording()
                            vm.grade(rating: .hard)
                        }
                        lifePathGradeButton(title: L10n.gradeGood(lang), color: .green, prominent: true) {
                            vm.cancelPronunciationRecording()
                            vm.grade(rating: .good)
                        }
                        lifePathGradeButton(title: L10n.gradeEasy(lang), color: .blue) {
                            vm.cancelPronunciationRecording()
                            vm.grade(rating: .easy)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Button {
                        vm.revealAnswer()
                    } label: {
                        Text(L10n.lifePathShowAnswer(lang))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
                Spacer(minLength: 32)
            }
            .animation(.spring(response: 0.35), value: vm.pronunciationState == .idle)
            .padding(.top, 16)
            .focusable()
            .focused($isPlayFocused)
            .onKeyPress(.space) {
                if !vm.isAnswerRevealed {
                    vm.revealAnswer()
                    return .handled
                } else {
                    vm.cancelPronunciationRecording()
                    vm.grade(rating: .good)
                    return .handled
                }
            }
            .onAppear { isPlayFocused = true }
        }
    }

    @ViewBuilder
    private func lifePathGradeButton(
        title: String,
        color: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .controlSize(.large)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .tint(color)
                .controlSize(.large)
        }
    }

    private func cardFace(_ card: LifePathEntry) -> some View {
        let frontId = frontPlaybackId(for: card)
        let backId = backPlaybackId(for: card)
        let stageTitle = vm.stages.first(where: { $0.id == card.stageId })?.title(for: lang)

        return VStack(spacing: 16) {
            if let stageTitle {
                Text(stageTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
            }

            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let result = vm.lastPronunciationResult {
                        TargetWordDisplay(word: card.front, isCorrect: result.isPassing(threshold: vm.pronunciationThreshold))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(card.front)
                            .font(.system(size: 40, weight: .bold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                }

                MessageAudioButton(
                    accent: .flashcard,
                    isPlaying: chatVM.isPlayingEphemeralAudio(id: frontId),
                    isGenerating: chatVM.isGeneratingEphemeralAudio(id: frontId),
                    action: { playFront(card) }
                )
                .help(L10n.lifePathPlayAudio(lang))
                .accessibilityLabel(L10n.lifePathPlayAudio(lang))
            }

            if let result = vm.lastPronunciationResult {
                Text(result.displayFeedback)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(result.isPassing(threshold: vm.pronunciationThreshold) ? .green : .orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if let phonics = card.phonics, !phonics.isEmpty {
                Text(phonics)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if vm.isAnswerRevealed {
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    Text(card.back)
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    MessageAudioButton(
                        accent: .flashcard,
                        isPlaying: chatVM.isPlayingEphemeralAudio(id: backId),
                        isGenerating: chatVM.isGeneratingEphemeralAudio(id: backId),
                        action: { playBack(card) }
                    )
                    .help(L10n.lifePathPlayAudio(lang))
                    .accessibilityLabel(L10n.lifePathPlayAudio(lang))
                }
            } else {
                Text(L10n.lifePathTapToReveal(lang))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .frame(minHeight: 240)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            if !vm.isAnswerRevealed {
                vm.revealAnswer()
            }
        }
    }

    // MARK: - Summary

    private var sessionSummary: some View {
        VStack(spacing: 20) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(L10n.lifePathRoundComplete(lang))
                .font(.title2.weight(.bold))
            Text(L10n.lifePathRoundStats(lang, correct: vm.sessionCorrect, wrong: vm.sessionWrong))
                .foregroundStyle(.secondary)
            Button {
                // Advance into the next stage's full session (or continue current if still open).
                vm.endSession()
                vm.startRound()
            } label: {
                Text(L10n.lifePathNextLevel(lang))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(L10n.lifePathErrorTitle(lang))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.essentialRetry(lang)) {
                vm.load()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func stageIcon(_ id: String) -> String {
        switch id {
        case "baby": return "figure.and.child.holdinghands"
        case "toddler": return "figure.walk"
        case "preschool": return "figure.play"
        default: return "graduationcap"
        }
    }

    private func statusLabel(_ status: LifePathWordStatus) -> String {
        switch status {
        case .locked: return L10n.lifePathStatusLocked(lang)
        case .new: return L10n.lifePathStatusNew(lang)
        case .learning: return L10n.lifePathStatusLearning(lang)
        case .review: return L10n.lifePathStatusReview(lang)
        case .stable: return L10n.lifePathStatusStable(lang)
        }
    }

    private func statusColor(_ status: LifePathWordStatus) -> Color {
        switch status {
        case .locked: return .secondary
        case .new: return .blue
        case .learning: return .orange
        case .review: return .purple
        case .stable: return .green
        }
    }
}

// MARK: - Level up

struct LifePathLevelUpView: View {
    let notify: LifePathLevelUpNotify
    let lang: AppLanguage
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.up.heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text(notify.title(for: lang))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(notify.body(for: lang))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                onContinue()
            } label: {
                Text(L10n.lifePathContinue(lang))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Spacer()
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(minWidth: 400, minHeight: 480)
        #endif
    }
}

// MARK: - Song break presentation (fullScreenCover iOS / sheet macOS)

/// `fullScreenCover` is unavailable on macOS — use sheet there instead.
private struct LifePathSongBreakPresenter<BreakContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var breakContent: () -> BreakContent

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented, content: breakContent)
        #else
        content.sheet(isPresented: $isPresented, content: breakContent)
        #endif
    }
}
