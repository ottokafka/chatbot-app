import SwiftUI

struct FlashcardDeckView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            deckHeader

            Divider()

            if flashcardVM.flashcards.isEmpty {
                emptyState
            } else {
                flashcardList
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
                Text(L10n.flashcardDeckSummary(lang, total: flashcardVM.flashcards.count, due: flashcardVM.dueCount))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                flashcardVM.startReviewSession()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                    Text(L10n.studyNow(lang, count: flashcardVM.dueCount))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(flashcardVM.dueCount == 0)
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(L10n.noFlashcards(lang))
                .font(.title3)
                .fontWeight(.medium)
            Text(L10n.noFlashcardsHint(lang))
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
                ForEach(flashcardVM.flashcards) { card in
                    FlashcardDeckRow(
                        card: card,
                        dueLabel: flashcardVM.dueLabel(for: card, language: lang),
                        isDue: flashcardVM.isDue(card),
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
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