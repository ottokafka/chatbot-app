import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct FlashcardCreateSheet: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    #if canImport(Translation) && !targetEnvironment(simulator)
    @State private var translationConfiguration: TranslationSession.Configuration?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(flashcardVM.isEditing ? L10n.editFlashcardTitle(lang) : L10n.createFlashcard(lang))
                .font(.title2)
                .fontWeight(.bold)

            if flashcardVM.duplicateWarning {
                Label(L10n.flashcardDuplicate(lang), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }

            if let saveError = flashcardVM.saveError {
                Label(saveError, systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.flashcardFront(lang))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                TextField(L10n.flashcardFrontPlaceholder(lang), text: frontBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.flashcardBack(lang))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    if flashcardVM.isTranslatingDraft {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.translating(lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                TextField(L10n.flashcardBackPlaceholder(lang), text: backBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.flashcardPhonics(lang))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                TextField(L10n.flashcardPhonicsPlaceholder(lang), text: phonicsBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .italic()
            }

            Spacer()

            HStack {
                Button(L10n.cancel(lang)) {
                    flashcardVM.cancelDraft()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(flashcardVM.isEditing ? L10n.updateFlashcard(lang) : L10n.saveFlashcard(lang)) {
                    if flashcardVM.saveDraft(appLanguage: lang) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .onAppear {
            updateTranslationConfiguration()
        }
        .onChange(of: flashcardVM.draft?.front) {
            updateTranslationConfiguration()
        }
        #if canImport(Translation) && !targetEnvironment(simulator)
        .translationTask(translationConfiguration) { session in
            guard let front = flashcardVM.draft?.front.trimmingCharacters(in: .whitespacesAndNewlines),
                  !front.isEmpty,
                  flashcardVM.draft?.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
                return
            }
            do {
                let response = try await session.translate(front)
                await MainActor.run {
                    flashcardVM.applyTranslatedBack(response.targetText)
                }
            } catch {
                await MainActor.run {
                    flashcardVM.isTranslatingDraft = false
                }
                print("Flashcard translation failed: \(error)")
            }
        }
        #endif
    }

    private var canSave: Bool {
        guard let draft = flashcardVM.draft else { return false }
        let front = draft.front.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)
        return !front.isEmpty && !back.isEmpty && !flashcardVM.isTranslatingDraft
    }

    private var frontBinding: Binding<String> {
        Binding(
            get: { flashcardVM.draft?.front ?? "" },
            set: { flashcardVM.updateDraftFront($0) }
        )
    }

    private var backBinding: Binding<String> {
        Binding(
            get: { flashcardVM.draft?.back ?? "" },
            set: { flashcardVM.updateDraftBack($0) }
        )
    }

    private var phonicsBinding: Binding<String> {
        Binding(
            get: { flashcardVM.draft?.phonics ?? "" },
            set: { flashcardVM.updateDraftPhonics($0) }
        )
    }

    private func updateTranslationConfiguration() {
        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(macOS 15.0, iOS 17.4, *) {
            guard let front = flashcardVM.draft?.front.trimmingCharacters(in: .whitespacesAndNewlines),
                  !front.isEmpty,
                  flashcardVM.draft?.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                  let pair = FlashcardTranslator.translationConfiguration(for: front) else {
                translationConfiguration = nil
                return
            }
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.source),
                target: Locale.Language(identifier: pair.target)
            )
        }
        #endif
    }
}