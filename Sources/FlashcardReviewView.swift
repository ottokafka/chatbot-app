import SwiftUI
import FSRS

struct FlashcardReviewView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            reviewHeader

            Divider()

            if flashcardVM.reviewComplete {
                completionView
            } else if let card = flashcardVM.currentReviewCard {
                reviewCardView(card)
            } else {
                completionView
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Color.platformControlBackground)
        .onAppear {
            autoPlayFrontIfNeeded()
        }
        .onChange(of: flashcardVM.currentReviewIndex) { _, _ in
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
    }

    private var reviewHeader: some View {
        HStack {
            if !flashcardVM.reviewComplete, !flashcardVM.reviewQueue.isEmpty {
                Text(L10n.reviewProgress(
                    lang,
                    current: min(flashcardVM.currentReviewIndex + 1, flashcardVM.reviewQueue.count),
                    total: flashcardVM.reviewQueue.count
                ))
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            autoPlayToggleButton

            Button(L10n.done(lang)) {
                flashcardVM.endReviewSession()
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

    /// Speaks the current card's front when auto-play is enabled.
    private func autoPlayFrontIfNeeded() {
        guard chatVM.isFlashcardAutoPlayEnabled else { return }
        guard !flashcardVM.reviewComplete else { return }
        guard let card = flashcardVM.currentReviewCard else { return }

        let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }

        let playbackId = "\(card.id)-front"
        if chatVM.isPlayingEphemeralAudio(id: playbackId)
            || chatVM.isGeneratingEphemeralAudio(id: playbackId) {
            return
        }

        chatVM.playEphemeralSpeech(text: front, playbackId: playbackId)
    }

    private func reviewCardView(_ card: Flashcard) -> some View {
        let frontPlaybackId = "\(card.id)-front"
        let backPlaybackId = "\(card.id)-back"

        return VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                flashcardTextRow(
                    text: card.front,
                    font: .system(size: 32, weight: .medium, design: .monospaced),
                    playbackId: frontPlaybackId,
                    onPlay: {
                        chatVM.playEphemeralSpeech(text: card.front, playbackId: frontPlaybackId)
                    }
                )

                if let phonics = FlashcardTranslator.displayPhonics(for: card.front, storedPhonics: card.phonics) {
                    phonicsLabel(phonics)
                }

                if !flashcardVM.isAnswerRevealed {
                    Text(L10n.tapToReveal(lang))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Divider()
                        .padding(.horizontal, 40)

                    flashcardTextRow(
                        text: card.back,
                        font: .system(size: 22, design: .monospaced),
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
                if !flashcardVM.isAnswerRevealed {
                    flashcardVM.revealAnswer()
                }
            }

            Spacer()

            if flashcardVM.isAnswerRevealed {
                gradeButtons
            } else {
                Button(L10n.revealAnswer(lang)) {
                    flashcardVM.revealAnswer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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

    private func flashcardTextRow(
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

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            GradeButton(title: L10n.gradeAgain(lang), color: .red) {
                chatVM.stopPlayback()
                flashcardVM.gradeCurrentCard(.again)
            }
            GradeButton(title: L10n.gradeHard(lang), color: .orange) {
                chatVM.stopPlayback()
                flashcardVM.gradeCurrentCard(.hard)
            }
            GradeButton(title: L10n.gradeGood(lang), color: .green) {
                chatVM.stopPlayback()
                flashcardVM.gradeCurrentCard(.good)
            }
            GradeButton(title: L10n.gradeEasy(lang), color: .blue) {
                chatVM.stopPlayback()
                flashcardVM.gradeCurrentCard(.easy)
            }
        }
        .padding(.horizontal, 32)
    }

    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text(L10n.reviewComplete(lang))
                .font(.title2)
                .fontWeight(.bold)

            if flashcardVM.dueCountForSelectedKind == 0 {
                Text(L10n.noCardsDue(lang))
                    .foregroundColor(.secondary)
            }

            Button(L10n.done(lang)) {
                flashcardVM.endReviewSession()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GradeButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}