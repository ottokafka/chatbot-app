import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Voice-first Speak with AI session UI: transcript, coverage chips, mic, typed input, save highlight.
struct SpeakingSessionView: View {
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var draftInput: String = ""
    @State private var showSummary = false
    @State private var selectedTurnId: String?
    @State private var saveBack: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var isTranslatingSave = false
    /// Turn ids whose on-demand help (meaning/phonics) is expanded.
    @State private var expandedHelpTurnIds: Set<String> = []
    /// Turn currently being translated for on-demand meaning.
    @State private var meaningTurnId: String?
    @State private var isTranslatingMeaning = false

    #if canImport(Translation) && !targetEnvironment(simulator)
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var meaningTranslationConfiguration: TranslationSession.Configuration?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider()

            if showSummary || speakingVM.session?.status == .ended {
                summaryView
            } else if let session = speakingVM.session {
                activeSessionBody(session)
            } else {
                Text(L10n.speakNoSeeds(lang))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(Color.platformControlBackground)
        .onAppear {
            // Default selection for save: last assistant turn (D20).
            if selectedTurnId == nil {
                selectedTurnId = speakingVM.session?.turns.last(where: { $0.role == .assistant })?.id
                    ?? speakingVM.session?.turns.last?.id
            }
        }
        .onChange(of: speakingVM.session?.turns.count) { _, _ in
            if selectedTurnId == nil
                || !(speakingVM.session?.turns.contains(where: { $0.id == selectedTurnId }) ?? false) {
                selectedTurnId = speakingVM.session?.turns.last(where: { $0.role == .assistant })?.id
                    ?? speakingVM.session?.turns.last?.id
            }
        }
        .onDisappear {
            // Ensure STT/mic are down if the sheet leaves for any reason.
            if speakingVM.isSpeakingMicActive || speakingVM.isSpeakingSTTConnected {
                speakingVM.finishConversation()
            }
            chatVM.clearEphemeralAudioCache()
        }
        .alert(
            L10n.speakSessionTitle(lang),
            isPresented: Binding(
                get: { saveMessage != nil },
                set: { if !$0 { saveMessage = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                saveMessage = nil
            }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            Text(L10n.speakSessionTitle(lang))
                .font(.headline)

            if let session = speakingVM.session, !showSummary {
                Text(
                    L10n.speakCoverageSummary(
                        lang,
                        covered: session.coveredTargetFronts.count,
                        total: session.config.targetFronts.count
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            if !showSummary {
                Toggle(isOn: $speakingVM.autoPlayTTS) {
                    Image(systemName: speakingVM.autoPlayTTS
                          ? "speaker.wave.2.fill"
                          : "speaker.slash")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(L10n.speakAutoTTS(lang))

                micBadge

                Button(L10n.speakDone(lang)) {
                    // Keep sheet open for summary + save highlights.
                    speakingVM.finishConversation()
                    showSummary = true
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private var micBadge: some View {
        Label(
            speakingVM.isSpeakingMicActive
                ? L10n.speakMicOn(lang)
                : L10n.speakMicOff(lang),
            systemImage: speakingVM.isSpeakingMicActive ? "mic.fill" : "mic.slash"
        )
        .font(.caption)
        .foregroundStyle(speakingVM.isSpeakingMicActive ? Color.green : Color.secondary)
    }

    // MARK: - Active session

    @ViewBuilder
    private func activeSessionBody(_ session: SpeakingSession) -> some View {
        VStack(spacing: 0) {
            coverageChips(session)
                .padding(.horizontal)
                .padding(.vertical, 8)

            if session.turns.count >= SpeakingSessionLimits.softLengthHintTurns {
                Text(L10n.speakLengthHint(lang, turns: SpeakingSessionLimits.softLengthHintTurns))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            if let err = session.lastError, !err.isEmpty {
                errorBanner(err, session: session)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            transcriptList(session)
            Divider()
            statusAndInput(session)
        }
        #if canImport(Translation) && !targetEnvironment(simulator)
        .translationTask(meaningTranslationConfiguration) { translationSession in
            guard let turnId = meaningTurnId,
                  let turn = speakingVM.session?.turns.first(where: { $0.id == turnId }) else {
                await MainActor.run { isTranslatingMeaning = false }
                return
            }
            let text = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                await MainActor.run { isTranslatingMeaning = false }
                return
            }
            do {
                let response = try await translationSession.translate(text)
                await MainActor.run {
                    speakingVM.setTurnHelp(turnId: turnId, translation: response.targetText)
                    isTranslatingMeaning = false
                    meaningTurnId = nil
                }
            } catch {
                await MainActor.run {
                    isTranslatingMeaning = false
                    meaningTurnId = nil
                }
            }
        }
        #endif
    }

    private func coverageChips(_ session: SpeakingSession) -> some View {
        let covered = Set(
            session.coveredTargetFronts.map { PracticeScaffolding.normalizeFrontKey($0) }
        )
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.config.targetFronts, id: \.self) { front in
                    let isCovered = covered.contains(PracticeScaffolding.normalizeFrontKey(front))
                    Text(front + (isCovered ? " ✓" : ""))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isCovered ? Color.green.opacity(0.25) : Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func errorBanner(_ message: String, session: SpeakingSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            HStack {
                if session.status == .ready {
                    Button(L10n.speakRetryOpening(lang)) {
                        Task { await speakingVM.retryOpening() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if speakingVM.pendingUserText != nil, session.status == .waitingUser {
                    Button(L10n.speakRetryLastReply(lang)) {
                        Task { await speakingVM.retryLastReply() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transcriptList(_ session: SpeakingSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.turns) { turn in
                        turnBubble(turn)
                            .id(turn.id)
                    }
                }
                .padding()
            }
            .onChange(of: session.turns.count) { _, _ in
                if let lastId = session.turns.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func turnBubble(_ turn: SpeakingTurn) -> some View {
        let isSelected = selectedTurnId == turn.id
        let helpExpanded = expandedHelpTurnIds.contains(turn.id)
        let isTranslatingThis = isTranslatingMeaning && meaningTurnId == turn.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(turn.role == .user ? L10n.speakYou(lang) : L10n.speakAI(lang))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if turn.role == .assistant {
                    Button {
                        chatVM.playEphemeralSpeech(
                            text: turn.content,
                            playbackId: "speaking-replay-\(turn.id)"
                        )
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.speakAutoTTS(lang))
                }
            }
            Text(turn.content)
                .font(.body)
                .textSelection(.enabled)
            if let raw = turn.rawASR, !raw.isEmpty, raw != turn.content {
                Text("ASR: \(raw)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let tip = turn.tutorFeedback, !tip.isEmpty {
                Text("↳ \(tip)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !turn.targetHits.isEmpty {
                Text(turn.targetHits.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            // On-demand meaning / phonics (PR4).
            if helpExpanded {
                if let phonics = FlashcardTranslator.displayPhonics(
                    for: turn.content,
                    storedPhonics: turn.phonics
                ) {
                    Text(phonics)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                }
                if isTranslatingThis {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(L10n.speakMeaningLoading(lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let translation = turn.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button(L10n.speakHideMeaning(lang)) {
                    expandedHelpTurnIds.remove(turn.id)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            } else {
                Button(L10n.speakShowMeaning(lang)) {
                    showMeaning(for: turn)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    turn.role == .user
                        ? Color.blue.opacity(isSelected ? 0.16 : 0.08)
                        : Color.gray.opacity(isSelected ? 0.16 : 0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            selectedTurnId = turn.id
            saveBack = ""
            updateSaveTranslationConfiguration()
        }
    }

    /// Expand help chrome and fill phonics / TranslationSession meaning for a turn.
    private func showMeaning(for turn: SpeakingTurn) {
        expandedHelpTurnIds.insert(turn.id)

        // Phonics immediately when useful (CJK); store on turn for reuse / save.
        let autoPhonics = FlashcardTranslator.autoFillPhonics(for: turn.content)
        if !autoPhonics.isEmpty, turn.phonics == nil {
            speakingVM.setTurnHelp(turnId: turn.id, phonics: autoPhonics)
        }

        // Already have a translation — just expand.
        if let existing = turn.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return
        }

        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(macOS 15.0, iOS 17.4, *) {
            let text = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let pair = FlashcardTranslator.translationConfiguration(for: text) else {
                return
            }
            meaningTurnId = turn.id
            isTranslatingMeaning = true
            // Force a new translationTask run when switching turns.
            if meaningTranslationConfiguration != nil {
                meaningTranslationConfiguration?.invalidate()
            }
            meaningTranslationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.source),
                target: Locale.Language(identifier: pair.target)
            )
            return
        }
        #endif
    }

    private func statusAndInput(_ session: SpeakingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusLabel(for: session.status))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField(
                    session.status == .waitingUser
                        ? L10n.speakTypePlaceholder(lang)
                        : statusLabel(for: session.status),
                    text: $draftInput
                )
                .textFieldStyle(.roundedBorder)
                .disabled(session.status != .waitingUser)
                .onSubmit {
                    sendDraft()
                }

                Button(L10n.speakSend(lang)) {
                    sendDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.status != .waitingUser
                        || draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private func sendDraft() {
        let text = draftInput
        draftInput = ""
        Task { await speakingVM.sendTypedText(text) }
    }

    private func statusLabel(for status: SpeakingSessionStatus) -> String {
        switch status {
        case .ready:
            return L10n.speakStatusReady(lang)
        case .waitingUser:
            return speakingVM.isSpeakingMicActive
                ? L10n.speakStatusListening(lang)
                : L10n.speakMicOff(lang)
        case .correctingSpeech:
            return L10n.speakStatusCorrecting(lang)
        case .generatingReply:
            return L10n.speakStatusThinking(lang)
        case .playingTTS:
            return L10n.speakStatusSpeaking(lang)
        case .ended:
            return L10n.speakStatusEnded(lang)
        }
    }

    // MARK: - Summary + save

    private var summaryView: some View {
        let session = speakingVM.session
        let covered = session?.coveredTargetFronts.count ?? 0
        let total = session?.config.targetFronts.count ?? 0
        let turnCount = session?.turns.count ?? 0
        let uncovered = session?.uncoveredTargetFronts ?? []

        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.speakSummaryTitle(lang))
                .font(.title2)
                .fontWeight(.bold)

            Text(L10n.speakSummarySubtitle(lang))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(L10n.speakSummaryCoverage(lang, covered: covered, total: total))
                .font(.body)

            if !uncovered.isEmpty, covered < total {
                Text(L10n.speakSummaryUncovered(lang, words: uncovered))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(L10n.speakSummaryTurns(lang, count: turnCount))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if turnCount >= SpeakingSessionLimits.softLengthHintTurns {
                Text(L10n.speakLengthHint(lang, turns: SpeakingSessionLimits.softLengthHintTurns))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let session, !session.turns.isEmpty {
                saveHighlightSection(session)
            }

            Spacer()

            // Single exit control (matches Practice completion). Saves already applied to Examples;
            // session transcript remains ephemeral either way.
            HStack {
                Spacer()
                Button(L10n.done(lang)) {
                    speakingVM.discardSession()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func saveHighlightSection(_ session: SpeakingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.speakSelectPhrase(lang))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { selectedTurnId ?? session.turns.last?.id ?? "" },
                set: { newId in
                    selectedTurnId = newId
                    saveBack = ""
                    updateSaveTranslationConfiguration()
                }
            )) {
                ForEach(session.turns) { turn in
                    let role = turn.role == .user ? L10n.speakYou(lang) : L10n.speakAI(lang)
                    let preview = turn.content.count > 40
                        ? String(turn.content.prefix(40)) + "…"
                        : turn.content
                    Text("\(role): \(preview)").tag(turn.id)
                }
            }
            .labelsHidden()

            if let turn = session.turns.first(where: { $0.id == selectedTurnId }) {
                Text(turn.content)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.platformControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(L10n.speakMeaningLabel(lang))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    if isTranslatingSave {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.translating(lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                TextField(L10n.speakMeaningPlaceholder(lang), text: $saveBack)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: saveBack) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isTranslatingSave = false
                        }
                    }

                Button {
                    saveSelectedPhrase(turn: turn, session: session)
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.speakSaveHighlight(lang), systemImage: "tray.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isTranslatingSave)
                .help(L10n.speakSaveHighlightHelp(lang))
            }
        }
        .onAppear {
            updateSaveTranslationConfiguration()
        }
        #if canImport(Translation) && !targetEnvironment(simulator)
        .translationTask(translationConfiguration) { session in
            guard let turn = speakingVM.session?.turns.first(where: { $0.id == selectedTurnId }) else {
                await MainActor.run { isTranslatingSave = false }
                return
            }
            let front = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, saveBack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run { isTranslatingSave = false }
                return
            }
            await MainActor.run { isTranslatingSave = true }
            do {
                let response = try await session.translate(front)
                await MainActor.run {
                    if saveBack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        saveBack = response.targetText
                    }
                    isTranslatingSave = false
                }
            } catch {
                await MainActor.run {
                    isTranslatingSave = false
                }
            }
        }
        #endif
    }

    private func saveSelectedPhrase(turn: SpeakingTurn, session: SpeakingSession) {
        let front = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = saveBack.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }
        guard !back.isEmpty else {
            saveMessage = L10n.speakMeaningRequired(lang)
            return
        }

        isSaving = true
        let parentId = inferredParentId(for: front, session: session)
        let phonics = FlashcardTranslator.autoFillPhonics(for: front)
        let result = flashcardVM.saveExamplePhrase(
            front: front,
            back: back,
            phonics: phonics.isEmpty ? nil : phonics,
            parentId: parentId
        )
        isSaving = false

        if result.savedCount > 0 {
            saveMessage = L10n.speakSaveSuccess(lang)
        } else if result.duplicateCount > 0 {
            saveMessage = L10n.speakSaveDuplicate(lang)
        } else if result.skippedEmptyCount > 0 {
            saveMessage = L10n.speakMeaningRequired(lang)
        } else {
            saveMessage = L10n.speakSaveFailed(lang)
        }
    }

    /// Parent link when exactly one target front is a clear hit in the phrase (D17 / design).
    private func inferredParentId(for phrase: String, session: SpeakingSession) -> String? {
        let hits = SpeakingTargetTracker.hits(
            in: phrase,
            targets: session.config.targetFronts,
            script: session.config.script
        )
        guard hits.count == 1,
              let front = hits.first,
              let card = session.config.targetCards.first(where: {
                  PracticeScaffolding.normalizeFrontKey($0.front)
                      == PracticeScaffolding.normalizeFrontKey(front)
              }) else {
            return nil
        }
        return card.id
    }

    private func updateSaveTranslationConfiguration() {
        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(macOS 15.0, iOS 17.4, *) {
            guard let turn = speakingVM.session?.turns.first(where: { $0.id == selectedTurnId }) else {
                clearSaveTranslation()
                return
            }
            let front = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty,
                  saveBack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let pair = FlashcardTranslator.translationConfiguration(for: front) else {
                clearSaveTranslation()
                return
            }
            // Show spinner only when a translation task will run; task clears the flag on
            // every early-return / cancel / completion path (never leave Save permanently disabled).
            isTranslatingSave = true
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.source),
                target: Locale.Language(identifier: pair.target)
            )
        }
        #endif
    }

    private func clearSaveTranslation() {
        #if canImport(Translation) && !targetEnvironment(simulator)
        translationConfiguration = nil
        #endif
        isTranslatingSave = false
    }
}
