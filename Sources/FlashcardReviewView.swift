import SwiftUI
import FSRS

struct FlashcardReviewView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
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

            Button(L10n.done(lang)) {
                flashcardVM.endReviewSession()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private func reviewCardView(_ card: Flashcard) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Text(card.front)
                    .font(.system(size: 32, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if !flashcardVM.isAnswerRevealed {
                    Text(L10n.tapToReveal(lang))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Divider()
                        .padding(.horizontal, 40)

                    Text(card.back)
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if let phonics = card.phonics, !phonics.isEmpty {
                        Text(phonics)
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                            .italic()
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

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            GradeButton(title: L10n.gradeAgain(lang), color: .red) {
                flashcardVM.gradeCurrentCard(.again)
            }
            GradeButton(title: L10n.gradeHard(lang), color: .orange) {
                flashcardVM.gradeCurrentCard(.hard)
            }
            GradeButton(title: L10n.gradeGood(lang), color: .green) {
                flashcardVM.gradeCurrentCard(.good)
            }
            GradeButton(title: L10n.gradeEasy(lang), color: .blue) {
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

            if flashcardVM.dueCount == 0 {
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