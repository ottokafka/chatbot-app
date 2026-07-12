import SwiftUI

struct EssentialVocabListView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @StateObject private var essentialVM = EssentialVocabViewModel()
    @Environment(\.appLanguage) private var lang

    var body: some View {
        NavigationStack {
            Group {
                if essentialVM.showLanguagePicker {
                    languagePicker
                } else if let error = essentialVM.loadError {
                    errorState(error)
                } else {
                    triageContent
                }
            }
            .navigationTitle(L10n.essentialWords(lang))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if essentialVM.showLanguagePicker {
                        Button(L10n.cancel(lang)) {
                            essentialVM.cancelLanguagePicker()
                        }
                    } else {
                        Button(L10n.done(lang)) {
                            flashcardVM.isShowingEssentialVocab = false
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !essentialVM.showLanguagePicker && essentialVM.loadError == nil {
                        Button {
                            essentialVM.undoLast()
                        } label: {
                            Label(L10n.essentialUndo(lang), systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!essentialVM.canUndo)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .onAppear {
            essentialVM.attach(flashcardVM: flashcardVM, dbManager: flashcardVM.dbManager)
            essentialVM.onLog = flashcardVM.onLog
            essentialVM.load(using: flashcardVM.flashcards)
        }
        .onChange(of: flashcardVM.flashcards) { _, newCards in
            essentialVM.refreshCardsFromDeck()
            _ = newCards
        }
        .alert(
            L10n.essentialErrorTitle(lang),
            isPresented: Binding(
                get: { essentialVM.actionError != nil },
                set: { if !$0 { essentialVM.actionError = nil } }
            )
        ) {
            Button(L10n.dismissError(lang), role: .cancel) {
                essentialVM.actionError = nil
            }
        } message: {
            Text(essentialVM.actionError ?? "")
        }
        .overlay(alignment: .bottom) {
            if essentialVM.toastMessage != nil {
                toastBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                essentialVM.toastMessage = nil
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Language picker

    private var languagePicker: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(L10n.essentialLearningPickerTitle(lang))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(EssentialListLanguage.allCases) { listLang in
                    Button {
                        essentialVM.setListLanguage(listLang)
                    } label: {
                        Text(listLang.displayName(uiLanguage: lang))
                            .frame(maxWidth: 280)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Button(L10n.cancel(lang)) {
                essentialVM.cancelLanguagePicker()
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Triage

    private var triageContent: some View {
        VStack(spacing: 0) {
            headerMetrics
            Divider()
            controlsBar
            Divider()
            if essentialVM.isUniverseComplete {
                completeState
            } else if essentialVM.batchExhaustedWithMorePending {
                batchCompleteState
            } else if essentialVM.visibleEntries.isEmpty {
                emptyFilterState
            } else {
                entryList
            }
        }
    }

    private var headerMetrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(listTitle)
                    .font(.headline)
                Spacer()
                menuListLanguage
            }

            ProgressView(value: essentialVM.progressFraction)
                .progressViewStyle(.linear)

            Text(progressSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if essentialVM.filter == .pending,
               essentialVM.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !essentialVM.batchEntryIds.isEmpty {
                Text(
                    L10n.essentialPassProgress(
                        lang,
                        remaining: essentialVM.snapshotRemainingCount,
                        batch: essentialVM.batchEntryIds.count,
                        pending: essentialVM.pendingCount
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.platformWindowBackground)
    }

    private var listTitle: String {
        if let listLang = essentialVM.listLanguage {
            return "\(L10n.essentialWords(lang)) · \(listLang.displayName(uiLanguage: lang))"
        }
        return L10n.essentialWords(lang)
    }

    private var progressSummary: String {
        let reviewed = essentialVM.addedCount + essentialVM.dismissedCount
        return L10n.essentialProgressSummary(
            lang,
            reviewed: reviewed,
            total: essentialVM.universeSize,
            added: essentialVM.addedCount,
            known: essentialVM.dismissedCount,
            pending: essentialVM.pendingCount
        )
    }

    private var menuListLanguage: some View {
        Menu {
            ForEach(EssentialListLanguage.allCases) { listLang in
                Button {
                    essentialVM.setListLanguage(listLang)
                } label: {
                    if essentialVM.listLanguage == listLang {
                        Label(listLang.displayName(uiLanguage: lang), systemImage: "checkmark")
                    } else {
                        Text(listLang.displayName(uiLanguage: lang))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(essentialVM.listLanguage?.displayName(uiLanguage: lang) ?? "—")
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline)
        }
    }

    private var controlsBar: some View {
        VStack(spacing: 8) {
            HStack {
                Picker(L10n.essentialRankCap(lang), selection: Binding(
                    get: { essentialVM.rankCap },
                    set: { essentialVM.setRankCap($0) }
                )) {
                    Text(L10n.essentialTopN(lang, n: 100)).tag(100)
                    Text(L10n.essentialTopN(lang, n: 500)).tag(500)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer(minLength: 8)

                Picker(L10n.essentialFilter(lang), selection: $essentialVM.filter) {
                    ForEach(EssentialFilter.allCases) { f in
                        Text(f.title(lang)).tag(f)
                    }
                }
                .frame(maxWidth: 160)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.essentialSearch(lang), text: $essentialVM.searchText)
                    .textFieldStyle(.plain)
                if !essentialVM.searchText.isEmpty {
                    Button {
                        essentialVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.platformControlBackground)
            .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.platformWindowBackground)
    }

    private var entryList: some View {
        List {
            ForEach(essentialVM.visibleEntries) { entry in
                EssentialVocabRow(
                    entry: entry,
                    status: essentialVM.effectiveStatus(entry),
                    cardKind: essentialVM.cardKind(for: entry),
                    lang: lang,
                    onAdd: {
                        if essentialVM.addToDeck(entry) {
                            withAnimation {
                                essentialVM.toastMessage = "added"
                            }
                        }
                    },
                    onDismiss: {
                        essentialVM.dismiss(entry)
                    },
                    onShowInVocab: {
                        essentialVM.showInVocabulary(entry)
                    },
                    onKeepKnown: {
                        // no-op; stays dismissed
                    }
                )
            }
        }
        .listStyle(.plain)
    }

    private var batchCompleteState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L10n.essentialBatchComplete(lang))
                .font(.title3)
                .fontWeight(.medium)
            Text(L10n.essentialBatchCompleteHint(lang, pending: essentialVM.pendingCount))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                essentialVM.continueBatch()
            } label: {
                Text(L10n.essentialContinue(lang))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completeState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L10n.essentialAllReviewed(lang, cap: essentialVM.rankCap))
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            Text(
                L10n.essentialCompleteCounts(
                    lang,
                    added: essentialVM.addedCount,
                    known: essentialVM.dismissedCount
                )
            )
            .font(.body)
            .foregroundColor(.secondary)

            if essentialVM.rankCap == 100 {
                Button {
                    essentialVM.setRankCap(500)
                } label: {
                    Text(L10n.essentialShowTop500(lang))
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                flashcardVM.isShowingEssentialVocab = false
            } label: {
                Text(L10n.done(lang))
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(L10n.essentialEmptyFilter(lang))
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L10n.essentialRetry(lang)) {
                essentialVM.load(using: flashcardVM.flashcards)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toastBanner: some View {
        Text(L10n.essentialAddedToast(lang))
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
    }
}

// MARK: - Row

private struct EssentialVocabRow: View {
    let entry: EssentialVocabEntry
    let status: EssentialVocabStatus?
    let cardKind: FlashcardKind?
    let lang: AppLanguage
    let onAdd: () -> Void
    let onDismiss: () -> Void
    let onShowInVocab: () -> Void
    let onKeepKnown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(entry.rank)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)

                Text(entry.front)
                    .font(.body.weight(.semibold))

                if let phonics = entry.phonics, !phonics.isEmpty {
                    Text(phonics)
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                }

                if let pos = entry.pos, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }

                if entry.isFunctionWord {
                    Text(L10n.essentialFunctionWord(lang))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text(entry.back)
                .font(.subheadline)
                .foregroundColor(.secondary)

            actions
        }
        .padding(.vertical, 4)
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            switch status {
            case nil:
                Button(action: onAdd) {
                    Label(L10n.essentialAddToDeck(lang), systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Label(L10n.essentialIKnowThis(lang), systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .dismissed:
                Button(action: onAdd) {
                    Label(L10n.essentialAddToDeck(lang), systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onKeepKnown) {
                    Text(L10n.essentialKeepKnown(lang))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)

            case .added:
                if cardKind == .example {
                    Text(L10n.essentialAlreadyInExamples(lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.essentialAlreadyInVocab(lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: onShowInVocab) {
                        Text(L10n.essentialShowInVocabulary(lang))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if status == nil {
            Button(L10n.essentialAddToDeck(lang), action: onAdd)
            Button(L10n.essentialIKnowThis(lang), action: onDismiss)
        } else if status == .dismissed {
            Button(L10n.essentialAddToDeck(lang), action: onAdd)
        } else if status == .added, cardKind != .example {
            Button(L10n.essentialShowInVocabulary(lang), action: onShowInVocab)
        }
    }
}
