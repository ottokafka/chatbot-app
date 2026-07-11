import SwiftUI

struct FlashcardDeckView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    /// Active text-gen endpoint used for AI practice generation.
    var llmEndpoint: String
    var llmModel: String
    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            deckHeader

            Divider()

            kindPicker

            if flashcardVM.flashcardsForSelectedKind.isEmpty {
                emptyState
            } else {
                searchBar
                if flashcardVM.filteredFlashcards.isEmpty {
                    noSearchResultsState
                } else {
                    flashcardList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground)
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
                Button(action: {
                    flashcardVM.beginPracticeGeneration(
                        appLanguage: lang,
                        llmEndpoint: llmEndpoint,
                        llmModel: llmModel
                    )
                }) {
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
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!flashcardVM.canStartPractice)
                .help(L10n.practiceWithAIHelp(lang))

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
    }

    private var summaryLine: String {
        L10n.flashcardKindSummary(
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
        .onChange(of: flashcardVM.selectedDeckKind) { _, _ in
            flashcardVM.searchText = ""
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.platformWindowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDue ? Color.orange.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
