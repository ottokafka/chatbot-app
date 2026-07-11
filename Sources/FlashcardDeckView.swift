import SwiftUI

struct FlashcardDeckView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    /// Active text-gen endpoint used for AI practice generation.
    var llmEndpoint: String
    var llmModel: String
    /// Wire chat endpoints / audio hooks into speakingVM before launch.
    var configureSpeaking: () -> Void
    /// D21: dismiss practice sheets before presenting Speak.
    var dismissPracticeForSpeaking: () -> Void
    /// D21: end speaking session/setup before Practice starts.
    var endSpeakingForPractice: () -> Void
    @Environment(\.appLanguage) private var lang

    @State private var selectionLimitMessage: String?
    @State private var speakingError: String?

    var body: some View {
        VStack(spacing: 0) {
            deckHeader

            Divider()

            kindPicker

            if flashcardVM.flashcardsForSelectedKind.isEmpty {
                emptyState
            } else {
                searchBar
                if flashcardVM.isSelectingVocabForPractice {
                    selectionToolbar
                }
                if flashcardVM.filteredFlashcards.isEmpty {
                    noSearchResultsState
                } else {
                    flashcardList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground)
        .alert(
            L10n.practiceInfoTitle(lang),
            isPresented: Binding(
                get: { selectionLimitMessage != nil },
                set: { if !$0 { selectionLimitMessage = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                selectionLimitMessage = nil
            }
        } message: {
            Text(selectionLimitMessage ?? "")
        }
    }

    private var deckHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.flashcards(lang))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                if flashcardVM.isSelectingVocabForPractice {
                    selectionModeHeaderActions
                } else {
                    defaultHeaderActions
                }
            }
        }
        .padding()
        .background(Color.platformWindowBackground)
        .alert(
            L10n.practiceErrorTitle(lang),
            isPresented: Binding(
                get: { flashcardVM.practiceError != nil },
                set: { if !$0 { flashcardVM.practiceError = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                flashcardVM.practiceError = nil
            }
        } message: {
            Text(flashcardVM.practiceError ?? "")
        }
        .alert(
            L10n.speakWithAI(lang),
            isPresented: Binding(
                get: { speakingError != nil },
                set: { if !$0 { speakingError = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                speakingError = nil
            }
        } message: {
            Text(speakingError ?? "")
        }
    }

    @ViewBuilder
    private var defaultHeaderActions: some View {
        if flashcardVM.selectedDeckKind == .vocab,
           !flashcardVM.flashcardsForSelectedKind.isEmpty {
            Button {
                flashcardVM.beginVocabPracticeSelection()
            } label: {
                Label(L10n.practiceSelectCards(lang), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(flashcardVM.isGeneratingPractice)
            .help(L10n.practiceSelectCardsHelp(lang))
        }

        // Style applies to Practice with AI (vocab seeds) on any deck tab; keep adjacent to the control.
        PracticeSentenceStylePicker(
            style: $flashcardVM.practiceSentenceStyle,
            lang: lang,
            disabled: flashcardVM.isGeneratingPractice,
            maxWidth: 160
        )

        practiceWithAIControl

        if SpeakingFeature.isEnabled {
            speakWithAIControl
        }

        Button(action: {
            flashcardVM.startReviewSession(kind: flashcardVM.selectedDeckKind)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                Text(L10n.studyNow(lang, count: flashcardVM.dueCountForSelectedKind))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(flashcardVM.dueCountForSelectedKind == 0)
    }

    /// Primary Practice control: single button, or split menu when due + last session both exist.
    @ViewBuilder
    private var practiceWithAIControl: some View {
        let label = practiceWithAILabel
        if flashcardVM.showsPracticeSeedMenu {
            Menu {
                ForEach(flashcardVM.availableDeckPracticeSeedSources, id: \.analyticsName) { source in
                    Button {
                        startDeckPractice(source: source)
                    } label: {
                        Text(practiceSeedMenuTitle(for: source))
                    }
                }
            } label: {
                label
            } primaryAction: {
                startDeckPractice(source: flashcardVM.preferredDeckPracticeSeedSource)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!flashcardVM.canStartPractice)
            .help(L10n.practiceWithAIMenuHelp(lang))
        } else {
            Button {
                startDeckPractice(source: flashcardVM.preferredDeckPracticeSeedSource)
            } label: {
                label
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!flashcardVM.canStartPractice)
            .help(
                L10n.practiceWithAIHelp(
                    lang,
                    hasDueVocab: flashcardVM.vocabDueCount > 0,
                    lastSessionCount: flashcardVM.lastStudySessionSeedCount
                )
            )
        }
    }

    private var practiceWithAILabel: some View {
        HStack(spacing: 6) {
            if flashcardVM.isGeneratingPractice {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
            Text(flashcardVM.isGeneratingPractice
                 ? L10n.practiceGenerating(lang)
                 : L10n.practiceWithAI(lang))
            if flashcardVM.showsPracticeSeedMenu && !flashcardVM.isGeneratingPractice {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func startDeckPractice(source: PracticeSeedSource) {
        // D21: end speaking before practice starts.
        endSpeakingForPractice()
        flashcardVM.beginPracticeGeneration(
            appLanguage: lang,
            llmEndpoint: llmEndpoint,
            llmModel: llmModel,
            seedSource: source
        )
    }

    /// Speak ▾ mirrors Practice sources (`availableDeckPracticeSeedSources`).
    @ViewBuilder
    private var speakWithAIControl: some View {
        let label = speakWithAILabel
        if flashcardVM.showsPracticeSeedMenu {
            Menu {
                ForEach(flashcardVM.availableDeckPracticeSeedSources, id: \.analyticsName) { source in
                    Button {
                        startDeckSpeaking(source: source)
                    } label: {
                        Text(speakSeedMenuTitle(for: source))
                    }
                }
            } label: {
                label
            } primaryAction: {
                startDeckSpeaking(source: flashcardVM.preferredDeckPracticeSeedSource)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!flashcardVM.canStartSpeaking)
            .help(L10n.speakWithAIMenuHelp(lang))
        } else {
            Button {
                startDeckSpeaking(source: flashcardVM.preferredDeckPracticeSeedSource)
            } label: {
                label
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!flashcardVM.canStartSpeaking)
            .help(
                L10n.speakWithAIHelp(
                    lang,
                    hasDueVocab: flashcardVM.vocabDueCount > 0,
                    lastSessionCount: flashcardVM.lastStudySessionSeedCount
                )
            )
        }
    }

    private var speakWithAILabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
            Text(L10n.speakWithAI(lang))
            if flashcardVM.showsPracticeSeedMenu {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func startDeckSpeaking(source: PracticeSeedSource) {
        guard SpeakingFeature.isEnabled else { return }
        guard let resolved = flashcardVM.resolveSpeakingLaunch(seedSource: source) else {
            speakingError = L10n.speakNoSeeds(lang)
            return
        }
        configureSpeaking()
        dismissPracticeForSpeaking()
        speakingVM.prepareSetup(
            seedSource: source,
            targets: resolved.targets,
            knownFronts: resolved.knownFronts,
            topicHint: "",
            encourageTargetCoverage: true
        )
        speakingVM.isShowingSetup = true
    }

    private func startSpeakingFromSelection() {
        guard SpeakingFeature.isEnabled else { return }
        let seeds = flashcardVM.resolveSelectedVocabForSpeaking()
        guard !seeds.isEmpty else {
            speakingError = L10n.speakNoSeeds(lang)
            return
        }
        let source = PracticeSeedSource.selectedVocab(ids: seeds.map(\.id))
        guard let resolved = flashcardVM.resolveSpeakingLaunch(seedSource: source) else {
            speakingError = L10n.speakNoSeeds(lang)
            return
        }
        configureSpeaking()
        dismissPracticeForSpeaking()
        speakingVM.prepareSetup(
            seedSource: source,
            targets: resolved.targets,
            knownFronts: resolved.knownFronts,
            topicHint: "",
            encourageTargetCoverage: true
        )
        // Exit multi-select like Practice does after launch.
        flashcardVM.cancelVocabPracticeSelection()
        speakingVM.isShowingSetup = true
    }

    private func practiceSeedMenuTitle(for source: PracticeSeedSource) -> String {
        let count = flashcardVM.practiceSeedCount(for: source)
        switch source {
        case .dueVocab:
            return L10n.practiceFromDueVocab(lang, count: count)
        case .lastStudySession:
            return L10n.practiceFromLastStudySession(lang, count: count)
        case .selectedVocab:
            return L10n.practiceSelectedWithAI(lang, count: count)
        }
    }

    private func speakSeedMenuTitle(for source: PracticeSeedSource) -> String {
        let count = flashcardVM.practiceSeedCount(for: source)
        switch source {
        case .dueVocab:
            return L10n.speakFromDueVocab(lang, count: count)
        case .lastStudySession:
            return L10n.speakFromLastStudySession(lang, count: count)
        case .selectedVocab:
            return L10n.speakSelectedWithAI(lang, count: count)
        }
    }

    @ViewBuilder
    private var selectionModeHeaderActions: some View {
        Button {
            flashcardVM.cancelVocabPracticeSelection()
        } label: {
            Text(L10n.practiceCancelSelection(lang))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(flashcardVM.isGeneratingPractice)

        Button {
            endSpeakingForPractice()
            flashcardVM.beginPracticeFromSelectedVocab(
                appLanguage: lang,
                llmEndpoint: llmEndpoint,
                llmModel: llmModel
            )
        } label: {
            HStack(spacing: 6) {
                if flashcardVM.isGeneratingPractice {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(flashcardVM.isGeneratingPractice
                     ? L10n.practiceGenerating(lang)
                     : L10n.practiceSelectedWithAI(
                        lang,
                        count: flashcardVM.selectedVocabSeedCount
                     ))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!flashcardVM.hasSelectedVocabSeeds || flashcardVM.isGeneratingPractice)
        .help(L10n.practiceSelectedWithAIHelp(lang))

        if SpeakingFeature.isEnabled {
            Button {
                startSpeakingFromSelection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                    Text(L10n.speakSelectedWithAI(
                        lang,
                        count: flashcardVM.selectedVocabSeedCount
                    ))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!flashcardVM.hasSelectedVocabSeeds || flashcardVM.isGeneratingPractice)
            .help(L10n.speakSelectedWithAIHelp(lang))
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Text(
                L10n.practiceSelectionCount(
                    lang,
                    selected: flashcardVM.selectedVocabSeedCount,
                    max: PracticeGenerationConfig.maxDueSeeds
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Spacer()

            Button(L10n.practiceSelectAllVisible(lang)) {
                flashcardVM.selectVisibleVocabSeeds(from: flashcardVM.filteredFlashcards)
                if flashcardVM.isVocabSeedSelectionAtLimit {
                    // Silent fill to cap is expected; no alert unless user taps a blocked card.
                }
            }
            .buttonStyle(.borderless)
            .disabled(flashcardVM.filteredFlashcards.isEmpty || flashcardVM.isGeneratingPractice)

            Button(L10n.practiceDeselectAll(lang)) {
                flashcardVM.deselectAllVocabSeeds()
            }
            .buttonStyle(.borderless)
            .disabled(flashcardVM.selectedVocabSeedCount == 0 || flashcardVM.isGeneratingPractice)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.platformWindowBackground.opacity(0.6))
    }

    private var summaryLine: String {
        if flashcardVM.isSelectingVocabForPractice {
            return L10n.practiceSelectionCount(
                lang,
                selected: flashcardVM.selectedVocabSeedCount,
                max: PracticeGenerationConfig.maxDueSeeds
            )
        }
        return L10n.flashcardKindSummary(
            lang,
            kind: flashcardVM.selectedDeckKind,
            total: flashcardVM.flashcardsForSelectedKind.count,
            due: flashcardVM.dueCountForSelectedKind
        )
    }

    private var kindPicker: some View {
        Picker("", selection: $flashcardVM.selectedDeckKind) {
            Text(L10n.flashcardKindVocabTab(lang, due: flashcardVM.vocabDueCount))
                .tag(FlashcardKind.vocab)
            Text(L10n.flashcardKindExampleTab(lang, due: flashcardVM.exampleDueCount))
                .tag(FlashcardKind.example)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .disabled(flashcardVM.isSelectingVocabForPractice)
        .onChange(of: flashcardVM.selectedDeckKind) { _, newKind in
            flashcardVM.searchText = ""
            if newKind != .vocab {
                flashcardVM.cancelVocabPracticeSelection()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(L10n.searchFlashcards(lang), text: $flashcardVM.searchText)
                .textFieldStyle(.plain)
            if flashcardVM.isSearchActive {
                Button {
                    flashcardVM.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.clearSearch(lang))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.platformWindowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: flashcardVM.selectedDeckKind == .vocab
                  ? "rectangle.on.rectangle.angled"
                  : "text.book.closed")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(emptyTitle)
                .font(.title3)
                .fontWeight(.medium)
            Text(emptyHint)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        flashcardVM.selectedDeckKind == .vocab
            ? L10n.noFlashcards(lang)
            : L10n.noExampleFlashcards(lang)
    }

    private var emptyHint: String {
        flashcardVM.selectedDeckKind == .vocab
            ? L10n.noFlashcardsHint(lang)
            : L10n.noExampleFlashcardsHint(lang)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L10n.noSearchResults(lang))
                .font(.title3)
                .fontWeight(.medium)
            Text(L10n.noSearchResultsHint(lang))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var flashcardList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(flashcardVM.filteredFlashcards) { card in
                    FlashcardDeckRow(
                        card: card,
                        dueLabel: flashcardVM.dueLabel(for: card, language: lang),
                        isDue: flashcardVM.isDue(card),
                        parentFront: flashcardVM.parentFrontLabel(for: card),
                        isSelecting: flashcardVM.isSelectingVocabForPractice && card.kind == .vocab,
                        isSelected: flashcardVM.isVocabSeedSelected(card.id),
                        onToggleSelect: {
                            let added = !flashcardVM.isVocabSeedSelected(card.id)
                            let ok = flashcardVM.toggleVocabSeedSelection(id: card.id)
                            if added && !ok {
                                selectionLimitMessage = L10n.practiceSelectionLimitReached(
                                    lang,
                                    max: PracticeGenerationConfig.maxDueSeeds
                                )
                            }
                        },
                        onEdit: { flashcardVM.prepareEdit(flashcard: card) },
                        onDelete: { flashcardVM.deleteFlashcard(card) }
                    )
                }
            }
            .padding()
        }
    }
}

private struct FlashcardDeckRow: View {
    let card: Flashcard
    let dueLabel: String
    let isDue: Bool
    let parentFront: String?
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)?
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if card.kind == .example, let parentFront, !parentFront.isEmpty {
                        Text(L10n.practiceFromWord(lang, word: parentFront))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }

                    Text(card.front)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)

                    Text(card.back)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    if let phonics = card.phonics, !phonics.isEmpty {
                        Text(phonics)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                Spacer()

                Text(dueLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isDue ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.12))
                    )
                    .foregroundColor(isDue ? .orange : .secondary)
            }

            if !isSelecting {
                HStack {
                    Spacer()
                    Button(action: onEdit) {
                        Label(L10n.editFlashcard(lang), systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.delete(lang), systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.platformWindowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(rowStrokeColor, lineWidth: isSelected ? 2 : 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            }
        }
    }

    private var rowStrokeColor: Color {
        if isSelecting && isSelected {
            return Color.accentColor.opacity(0.7)
        }
        if isDue {
            return Color.orange.opacity(0.4)
        }
        return Color.gray.opacity(0.2)
    }
}
