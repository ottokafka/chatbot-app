import SwiftUI

struct PracticePreviewSheet: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let pack = flashcardVM.practicePack, !pack.cards.isEmpty {
                summaryBanner(pack)
                selectionToolbar(pack)
                cardList(pack)
                footer(canStart: true)
            } else {
                emptyState
                footer(canStart: false)
            }
        }
        .frame(minWidth: 560, minHeight: 500)
        .background(Color.platformControlBackground)
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
        .alert(
            L10n.practiceErrorTitle(lang),
            isPresented: Binding(
                get: { flashcardVM.practiceError != nil && flashcardVM.isShowingPracticePreview },
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

    private var header: some View {
        HStack {
            Text(L10n.practicePreviewTitle(lang))
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button(L10n.practiceRegenerate(lang)) {
                flashcardVM.regeneratePracticePack()
            }
            .disabled(flashcardVM.isGeneratingPractice || !flashcardVM.regeneratingPracticeCardIds.isEmpty)
            Button(L10n.discardPractice(lang)) {
                flashcardVM.discardPracticePack()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private func summaryBanner(_ pack: PracticePack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.practicePreviewSummary(lang, cards: pack.cards.count, seeds: pack.sourceDueCount))
                .font(.subheadline)
                .fontWeight(.medium)
            Text(L10n.practicePreviewAINote(lang, style: flashcardVM.practiceSentenceStyle))
                .font(.caption)
                .foregroundColor(.secondary)

            sentenceStylePicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.platformWindowBackground.opacity(0.6))
    }

    private var sentenceStylePicker: some View {
        HStack(spacing: 10) {
            Text(L10n.practiceSentenceStyleLabel(lang))
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $flashcardVM.practiceSentenceStyle) {
                Text(L10n.practiceSentenceStyleSimple(lang)).tag(PracticeSentenceStyle.comprehensible)
                Text(L10n.practiceSentenceStyleNatural(lang)).tag(PracticeSentenceStyle.natural)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .labelsHidden()
            .help(L10n.practiceSentenceStyleHelp(lang))
            .disabled(flashcardVM.isGeneratingPractice || !flashcardVM.regeneratingPracticeCardIds.isEmpty)
            Spacer(minLength: 0)
        }
    }

    private func selectionToolbar(_ pack: PracticePack) -> some View {
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

            Text("\(flashcardVM.selectedPracticeCardIds.count)/\(pack.cards.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func cardList(_ pack: PracticePack) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(pack.cards) { card in
                    PracticePreviewRow(
                        card: card,
                        isSelected: flashcardVM.isPracticeCardSelected(card.id),
                        isSaved: flashcardVM.isPracticeCardSaved(card.id),
                        isRegenerating: flashcardVM.isRegeneratingPracticeCard(card.id),
                        onToggleSelect: { flashcardVM.togglePracticeCardSelection(id: card.id) },
                        onFrontChange: { flashcardVM.updatePracticeCard(id: card.id, front: $0) },
                        onBackChange: { flashcardVM.updatePracticeCard(id: card.id, back: $0) },
                        onRegenerate: { flashcardVM.regeneratePracticeCard(id: card.id) },
                        onSaveOne: { flashcardVM.savePracticeCardToDeck(id: card.id, appLanguage: lang) },
                        onRemove: { flashcardVM.removePracticeCard(id: card.id) }
                    )
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(L10n.practiceEmptyPreview(lang))
                .font(.title3)
                .fontWeight(.medium)
            Text(L10n.practiceEmptyPreviewHint(lang))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(L10n.practiceRegenerate(lang)) {
                flashcardVM.regeneratePracticePack()
            }
            .buttonStyle(.bordered)
            .disabled(flashcardVM.isGeneratingPractice)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(canStart: Bool) -> some View {
        HStack {
            Button(L10n.discardPractice(lang)) {
                flashcardVM.discardPracticePack()
                dismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(L10n.practiceSaveSelected(lang, count: flashcardVM.selectedPracticeCardIds.count)) {
                flashcardVM.saveSelectedPracticeCardsToDeck(appLanguage: lang)
            }
            .buttonStyle(.bordered)
            .disabled(!flashcardVM.hasPracticeSelection)

            Button(L10n.startPractice(lang)) {
                flashcardVM.startPracticeSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStart)
        }
        .padding()
        .background(Color.platformWindowBackground)
    }
}

private struct PracticePreviewRow: View {
    let card: PracticeCard
    let isSelected: Bool
    let isSaved: Bool
    let isRegenerating: Bool
    let onToggleSelect: () -> Void
    let onFrontChange: (String) -> Void
    let onBackChange: (String) -> Void
    let onRegenerate: () -> Void
    let onSaveOne: () -> Void
    let onRemove: () -> Void

    @Environment(\.appLanguage) private var lang
    @State private var frontText: String
    @State private var backText: String

    init(
        card: PracticeCard,
        isSelected: Bool,
        isSaved: Bool,
        isRegenerating: Bool,
        onToggleSelect: @escaping () -> Void,
        onFrontChange: @escaping (String) -> Void,
        onBackChange: @escaping (String) -> Void,
        onRegenerate: @escaping () -> Void,
        onSaveOne: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.card = card
        self.isSelected = isSelected
        self.isSaved = isSaved
        self.isRegenerating = isRegenerating
        self.onToggleSelect = onToggleSelect
        self.onFrontChange = onFrontChange
        self.onBackChange = onBackChange
        self.onRegenerate = onRegenerate
        self.onSaveOne = onSaveOne
        self.onRemove = onRemove
        _frontText = State(initialValue: card.front)
        _backText = State(initialValue: card.back)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(L10n.practiceMarkForSave(lang))

                if let parent = card.parentFront, !parent.isEmpty {
                    Text(L10n.practiceFromWord(lang, word: parent))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                if isSaved {
                    Text(L10n.practiceSavedBadge(lang))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                        .foregroundColor(.green)
                }

                Spacer(minLength: 8)

                if isRegenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: onRegenerate) {
                        Label(L10n.practiceRegenerateOne(lang), systemImage: "arrow.clockwise")
                            .font(.caption)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.practiceRegenerateOne(lang))
                }

                Button(action: onSaveOne) {
                    Label(L10n.practiceSaveOne(lang), systemImage: "tray.and.arrow.down")
                        .font(.caption)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(L10n.practiceSaveOne(lang))
                .disabled(isSaved)

                Button(role: .destructive, action: onRemove) {
                    Label(L10n.removePracticeCard(lang), systemImage: "xmark.circle")
                        .font(.caption)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(L10n.removePracticeCard(lang))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.practiceSentenceLabel(lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField(L10n.practiceSentenceLabel(lang), text: $frontText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...5)
                    .disabled(isRegenerating)
                    .onChange(of: frontText) { _, newValue in
                        onFrontChange(newValue)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.practiceTranslationLabel(lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField(L10n.practiceTranslationLabel(lang), text: $backText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2...4)
                    .disabled(isRegenerating)
                    .onChange(of: backText) { _, newValue in
                        onBackChange(newValue)
                    }
            }

            if let phonics = card.phonics, !phonics.isEmpty {
                Text(phonics)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformWindowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .opacity(isRegenerating ? 0.7 : 1)
        .onChange(of: card.front) { _, newValue in
            if frontText != newValue {
                frontText = newValue
            }
        }
        .onChange(of: card.back) { _, newValue in
            if backText != newValue {
                backText = newValue
            }
        }
    }
}
