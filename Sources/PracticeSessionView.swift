import SwiftUI

/// Practice session chrome, modeled on `FlashcardReviewView`.
/// Grades advance the queue only — no FSRS updates unless the user saves cards to the deck.
struct PracticeSessionView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader

            Divider()

            if flashcardVM.practiceComplete {
                completionView
            } else if let card = flashcardVM.currentPracticeCard {
                practiceCardView(card)
            } else {
                completionView
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(Color.platformControlBackground)
        .onAppear {
            autoPlayFrontIfNeeded()
        }
        .onChange(of: flashcardVM.currentPracticeIndex) { _, _ in
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
        .alert(
            L10n.practiceInfoTitle(lang),
            isPresented: Binding(
                get: { flashcardVM.practiceInfoMessage != nil },
                set: { if !$0 { flashcardVM.practiceInfoMessage = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                flashcardVM.practiceInfoMessage = nil
            }
        } message: {
            Text(flashcardVM.practiceInfoMessage ?? "")
        }
    }

    private var sessionHeader: some View {
        HStack {
            Text(L10n.practiceSessionTitle(lang))
                .font(.headline)

            if !flashcardVM.practiceComplete, !flashcardVM.practiceQueue.isEmpty {
                Text(L10n.practiceProgress(
                    lang,
                    current: min(flashcardVM.currentPracticeIndex + 1, flashcardVM.practiceQueue.count),
                    total: flashcardVM.practiceQueue.count
                ))
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            autoPlayToggleButton

            Button(L10n.done(lang)) {
                flashcardVM.discardPracticePack()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color.platformWindowBackground)
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

    /// Speaks the current practice card's front when auto-play is enabled.
    private func autoPlayFrontIfNeeded() {
        guard chatVM.isFlashcardAutoPlayEnabled else { return }
        guard !flashcardVM.practiceComplete else { return }
        guard let card = flashcardVM.currentPracticeCard else { return }

        let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }

        let playbackId = "practice-\(card.id)-front"
        if chatVM.isPlayingEphemeralAudio(id: playbackId)
            || chatVM.isGeneratingEphemeralAudio(id: playbackId) {
            return
        }

        chatVM.playEphemeralSpeech(text: front, playbackId: playbackId)
    }

    private func practiceCardView(_ card: PracticeCard) -> some View {
        let frontPlaybackId = "practice-\(card.id)-front"
        let backPlaybackId = "practice-\(card.id)-back"
        let isSelected = flashcardVM.isPracticeCardSelected(card.id)
        let isSaved = flashcardVM.isPracticeCardSaved(card.id)

        return VStack(spacing: 24) {
            HStack {
                if let parent = card.parentFront, !parent.isEmpty {
                    Text(L10n.practiceFromWord(lang, word: parent))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                Spacer()
                if isSaved {
                    Text(L10n.practiceSavedBadge(lang))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 16) {
                practiceTextRow(
                    text: card.front,
                    font: .system(size: 28, weight: .medium, design: .monospaced),
                    playbackId: frontPlaybackId,
                    onPlay: {
                        chatVM.playEphemeralSpeech(text: card.front, playbackId: frontPlaybackId)
                    }
                )

                if let phonics = FlashcardTranslator.displayPhonics(for: card.front, storedPhonics: card.phonics) {
                    phonicsLabel(phonics)
                }

                if !flashcardVM.isPracticeAnswerRevealed {
                    Text(L10n.tapToReveal(lang))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Divider()
                        .padding(.horizontal, 40)

                    practiceTextRow(
                        text: card.back,
                        font: .system(size: 20, design: .monospaced),
                        foreground: .secondary,
                        playbackId: backPlaybackId,
                        onPlay: {
                            chatVM.playEphemeralSpeech(text: card.back, playbackId: backPlaybackId)
                        }
                    )

                    if let phonics = FlashcardTranslator.displayPhonics(for: card.back) {
                        phonicsLabel(phonics)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.platformWindowBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            )
            .padding(.horizontal, 32)
            .contentShape(Rectangle())
            .onTapGesture {
                if !flashcardVM.isPracticeAnswerRevealed {
                    flashcardVM.revealPracticeAnswer()
                }
            }

            Spacer()

            if flashcardVM.isPracticeAnswerRevealed {
                HStack(spacing: 12) {
                    Button {
                        flashcardVM.togglePracticeCardSelection(id: card.id)
                    } label: {
                        Label(
                            L10n.practiceMarkForSave(lang),
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        flashcardVM.savePracticeCardToDeck(id: card.id, appLanguage: lang)
                    } label: {
                        Label(L10n.practiceSaveOne(lang), systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaved)

                    Button {
                        chatVM.stopPlayback()
                        flashcardVM.advancePracticeCard()
                    } label: {
                        Text(L10n.practiceNext(lang))
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(L10n.spaceToAdvancePractice(lang))
                }
                .padding(.horizontal, 32)
            } else {
                Button(L10n.revealAnswer(lang)) {
                    flashcardVM.revealPracticeAnswer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .help(L10n.spaceToReveal(lang))
            }

            Spacer(minLength: 24)
        }
    }

    private func phonicsLabel(_ phonics: String) -> some View {
        Text(phonics)
            .font(.system(.title3, design: .monospaced))
            .foregroundColor(.secondary)
            .italic()
    }

    private func practiceTextRow(
        text: String,
        font: Font,
        foreground: Color = .primary,
        playbackId: String,
        onPlay: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            MessageAudioButton(
                accent: .flashcard,
                isPlaying: chatVM.isPlayingEphemeralAudio(id: playbackId),
                isGenerating: chatVM.isGeneratingEphemeralAudio(id: playbackId),
                action: onPlay
            )
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.orange)
                .padding(.top, 20)

            Text(L10n.practiceComplete(lang))
                .font(.title2)
                .fontWeight(.bold)

            Text(L10n.practiceCompleteSaveHint(lang))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.horizontal)

            if !flashcardVM.practiceQueue.isEmpty {
                HStack(spacing: 12) {
                    Button(L10n.practiceSelectAll(lang)) {
                        flashcardVM.selectAllPracticeCards()
                    }
                    .buttonStyle(.borderless)

                    Button(L10n.practiceDeselectAll(lang)) {
                        flashcardVM.deselectAllPracticeCards()
                    }
                    .buttonStyle(.borderless)
                    .disabled(!flashcardVM.hasPracticeSelection)

                    Spacer()

                    Text("\(flashcardVM.selectedPracticeCardIds.count)/\(flashcardVM.practiceQueue.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(flashcardVM.practiceQueue) { card in
                            PracticeCompletionRow(
                                card: card,
                                isSelected: flashcardVM.isPracticeCardSelected(card.id),
                                isSaved: flashcardVM.isPracticeCardSaved(card.id),
                                onToggle: { flashcardVM.togglePracticeCardSelection(id: card.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
            }

            HStack(spacing: 12) {
                Button(L10n.practiceSaveSelected(lang, count: flashcardVM.selectedPracticeCardIds.count)) {
                    flashcardVM.saveSelectedPracticeCardsToDeck(appLanguage: lang)
                }
                .buttonStyle(.bordered)
                .disabled(!flashcardVM.hasPracticeSelection)

                Button(L10n.done(lang)) {
                    flashcardVM.discardPracticePack()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PracticeCompletionRow: View {
    let card: PracticeCard
    let isSelected: Bool
    let isSaved: Bool
    let onToggle: () -> Void

    @Environment(\.appLanguage) private var lang

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    if let parent = card.parentFront, !parent.isEmpty {
                        Text(L10n.practiceFromWord(lang, word: parent))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    Text(card.front)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Text(card.back)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if isSaved {
                    Text(L10n.practiceSavedBadge(lang))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                        .foregroundColor(.green)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.platformWindowBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.45) : Color.gray.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
