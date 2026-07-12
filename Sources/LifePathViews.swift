import SwiftUI

struct LifePathRootView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var chatVM: ChatViewModel
    @StateObject private var vm = LifePathViewModel()
    @Environment(\.appLanguage) private var lang
    @State private var showResetConfirm = false

    var body: some View {
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
                        Button(L10n.done(lang)) {
                            chatVM.stopPlayback()
                            flashcardVM.isShowingLifePath = false
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if vm.isPlaying {
                        autoPlayToggleButton
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .onAppear {
            vm.attach(flashcardVM: flashcardVM, dbManager: flashcardVM.dbManager)
            vm.onLog = flashcardVM.onLog
            vm.load()
        }
        .onChange(of: vm.isPlaying) { _, playing in
            if playing {
                autoPlayFrontIfNeeded()
            } else {
                chatVM.stopPlayback()
            }
        }
        .onChange(of: vm.sessionIndex) { _, _ in
            autoPlayFrontIfNeeded()
        }
        .onChange(of: chatVM.isFlashcardAutoPlayEnabled) { _, enabled in
            if enabled {
                autoPlayFrontIfNeeded()
            } else {
                chatVM.stopPlayback()
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
        guard let card = vm.currentCard else { return }

        let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }

        let playbackId = frontPlaybackId(for: card)
        if chatVM.isPlayingEphemeralAudio(id: playbackId)
            || chatVM.isGeneratingEphemeralAudio(id: playbackId) {
            return
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
                .disabled(vm.totalInCurrentStage == 0)

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
        }
        .padding(16)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 14))
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
                Text(L10n.lifePathSessionRemaining(lang, remaining: vm.sessionRemainingCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if let card = vm.currentCard {
                cardFace(card)
            }

            if vm.isAnswerRevealed {
                HStack(spacing: 16) {
                    Button {
                        vm.gradeWrong()
                    } label: {
                        Label(L10n.lifePathAgain(lang), systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)

                    Button {
                        vm.gradeCorrect()
                    } label: {
                        Label(L10n.lifePathGotIt(lang), systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
                .padding(.horizontal)
            } else {
                Button {
                    vm.revealAnswer()
                } label: {
                    Text(L10n.lifePathShowAnswer(lang))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 16)
    }

    private func cardFace(_ card: LifePathEntry) -> some View {
        let frontId = frontPlaybackId(for: card)
        let backId = backPlaybackId(for: card)

        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(card.front)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)

                MessageAudioButton(
                    accent: .flashcard,
                    isPlaying: chatVM.isPlayingEphemeralAudio(id: frontId),
                    isGenerating: chatVM.isGeneratingEphemeralAudio(id: frontId),
                    action: { playFront(card) }
                )
                .help(L10n.lifePathPlayAudio(lang))
                .accessibilityLabel(L10n.lifePathPlayAudio(lang))
            }

            if let phonics = card.phonics, !phonics.isEmpty {
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
                vm.endSession()
            } label: {
                Text(L10n.lifePathBackHome(lang))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                vm.endSession()
                vm.startRound()
            } label: {
                Text(L10n.lifePathPlayAgain(lang))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
        case .available: return L10n.lifePathStatusNew(lang)
        case .learning: return L10n.lifePathStatusLearning(lang)
        case .mastered: return L10n.lifePathStatusMastered(lang)
        }
    }

    private func statusColor(_ status: LifePathWordStatus) -> Color {
        switch status {
        case .locked: return .secondary
        case .available: return .blue
        case .learning: return .orange
        case .mastered: return .green
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
        .frame(minWidth: 400, minHeight: 480)
    }
}
