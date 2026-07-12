import Foundation
import SwiftUI
import Combine

// MARK: - Undo

private enum EssentialUndoAction {
    case add(
        entry: EssentialVocabEntry,
        previousStatus: EssentialVocabStatus?,
        didInsertCard: Bool,
        flashcardId: String?
    )
    case dismiss(
        entry: EssentialVocabEntry,
        previousStatus: EssentialVocabStatus?,
        previousFlashcardId: String?
    )
}

// MARK: - View model

@MainActor
final class EssentialVocabViewModel: ObservableObject {
    @Published private(set) var listLanguage: EssentialListLanguage?
    @Published private(set) var showLanguagePicker = false
    @Published private(set) var entries: [EssentialVocabEntry] = []
    @Published private(set) var progressById: [String: EssentialProgressRow] = [:]
    @Published var filter: EssentialFilter = .pending
    @Published var rankCap: Int = EssentialVocabPreferences.rankCap {
        didSet {
            if rankCap != 100 && rankCap != 500 {
                rankCap = 500
            }
            EssentialVocabPreferences.rankCap = rankCap
        }
    }
    @Published var searchText: String = ""
    /// Ordered entry ids for the current short pass (Option A snapshot). Not persisted.
    @Published private(set) var batchEntryIds: [String] = []
    let batchSize: Int = 20
    @Published private(set) var loadError: String?
    @Published private(set) var canUndo = false
    @Published var toastMessage: String?
    @Published var actionError: String?

    @Published private(set) var universeSize: Int = 0
    @Published private(set) var addedCount: Int = 0
    @Published private(set) var dismissedCount: Int = 0
    @Published private(set) var pendingCount: Int = 0

    private var dbManager: DatabaseManager
    private weak var flashcardVM: FlashcardViewModel?
    private var cardsById: [String: Flashcard] = [:]
    private var cardsByFront: [String: Flashcard] = [:]
    private var entriesById: [String: EssentialVocabEntry] = [:]
    private var undoStack: [EssentialUndoAction] = []
    private var listId: String = ""

    var onLog: ((String) -> Void)?

    init(dbManager: DatabaseManager = DatabaseManager(), flashcardVM: FlashcardViewModel? = nil) {
        self.dbManager = dbManager
        self.flashcardVM = flashcardVM
        self.rankCap = EssentialVocabPreferences.rankCap
    }

    func attach(flashcardVM: FlashcardViewModel, dbManager: DatabaseManager? = nil) {
        self.flashcardVM = flashcardVM
        if let dbManager {
            self.dbManager = dbManager
        }
    }

    // MARK: - Derived

    var visibleEntries: [EssentialVocabEntry] {
        let universe = universeEntries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            let pool = universe.filter { matchesSearch($0, query: query) && matchesFilter($0) }
            return Array(pool.sorted { $0.rank < $1.rank }.prefix(50))
        }

        switch filter {
        case .pending:
            return snapshotStillPending()
        case .added:
            return Array(
                universe.filter { effectiveStatus($0) == .added }
                    .sorted { $0.rank < $1.rank }
                    .prefix(100)
            )
        case .dismissed:
            return Array(
                universe.filter { effectiveStatus($0) == .dismissed }
                    .sorted { $0.rank < $1.rank }
                    .prefix(100)
            )
        case .all:
            return Array(universe.sorted { $0.rank < $1.rank }.prefix(100))
        }
    }

    var batchExhaustedWithMorePending: Bool {
        snapshotStillPending().isEmpty && pendingCount > 0 && filter == .pending
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isUniverseComplete: Bool {
        universeSize > 0 && pendingCount == 0
    }

    var progressFraction: Double {
        guard universeSize > 0 else { return 0 }
        return Double(addedCount + dismissedCount) / Double(universeSize)
    }

    var snapshotRemainingCount: Int {
        snapshotStillPending().count
    }

    // MARK: - Lifecycle

    func load(using flashcards: [Flashcard]? = nil) {
        loadError = nil
        actionError = nil
        let cards = flashcards ?? flashcardVM?.flashcards ?? dbManager.fetchFlashcards()
        rebuildCardMaps(from: cards)

        guard let language = EssentialVocabPreferences.listLanguage else {
            listLanguage = nil
            showLanguagePicker = true
            entries = []
            entriesById = [:]
            progressById = [:]
            batchEntryIds = []
            recomputeUniverseMetrics()
            return
        }

        showLanguagePicker = false
        listLanguage = language
        listId = language.listId

        do {
            let file = try EssentialVocabCatalog.loadList(language: language)
            entries = file.entries.sorted { $0.rank < $1.rank }
            entriesById = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            progressById = dbManager.fetchEssentialProgress(listId: listId)
            reconcile()
            recomputeUniverseMetrics()
            takeBatchSnapshot()
            onLog?("Essential vocab loaded: \(language.listId) (\(entries.count) entries)")
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            entries = []
            entriesById = [:]
            batchEntryIds = []
            recomputeUniverseMetrics()
            onLog?("Essential vocab load failed: \(loadError ?? "unknown")")
        }
    }

    func setListLanguage(_ lang: EssentialListLanguage) {
        EssentialVocabPreferences.listLanguage = lang
        listLanguage = lang
        showLanguagePicker = false
        undoStack.removeAll()
        canUndo = false
        load(using: flashcardVM?.flashcards)
    }

    /// Cancel language picker: dismiss sheet without persisting language (V1 / D22).
    func cancelLanguagePicker() {
        flashcardVM?.isShowingEssentialVocab = false
    }

    func setRankCap(_ cap: Int) {
        rankCap = (cap == 100) ? 100 : 500
        recomputeUniverseMetrics()
        takeBatchSnapshot()
    }

    func continueBatch() {
        guard batchExhaustedWithMorePending else { return }
        takeBatchSnapshot()
    }

    func refreshCardsFromDeck() {
        let cards = flashcardVM?.flashcards ?? dbManager.fetchFlashcards()
        rebuildCardMaps(from: cards)
        if listLanguage != nil {
            reconcile()
            recomputeUniverseMetrics()
            // Keep snapshot; only re-filter still-pending ids.
            objectWillChange.send()
        }
    }

    // MARK: - Actions

    @discardableResult
    func addToDeck(_ entry: EssentialVocabEntry) -> Bool {
        actionError = nil
        let previous = progressById[entry.id]?.status

        if let card = cardsByFront[entry.front] {
            upsertProgress(entryId: entry.id, status: .added, flashcardId: card.id)
            pushUndo(.add(entry: entry, previousStatus: previous, didInsertCard: false, flashcardId: card.id))
            recomputeUniverseMetrics()
            toastMessage = card.kind == .example
                ? nil
                : L10n.essentialAlreadyInVocab(.en) // toast filled by view with lang
            return true
        }

        let phonics: String? = {
            if let p = entry.phonics?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                return p
            }
            let auto = FlashcardTranslator.autoFillPhonics(for: entry.front)
            return auto.isEmpty ? nil : auto
        }()

        let card = Flashcard(
            front: entry.front,
            back: entry.back,
            phonics: phonics,
            kind: .vocab
        )

        if dbManager.insertFlashcard(card) == nil {
            if let existing = dbManager.flashcard(forFront: entry.front) {
                upsertProgress(entryId: entry.id, status: .added, flashcardId: existing.id)
                flashcardVM?.loadFlashcards()
                rebuildCardMaps(from: flashcardVM?.flashcards ?? dbManager.fetchFlashcards())
                pushUndo(.add(entry: entry, previousStatus: previous, didInsertCard: false, flashcardId: existing.id))
                recomputeUniverseMetrics()
                return true
            }
            actionError = "Failed to save flashcard"
            return false
        }

        upsertProgress(entryId: entry.id, status: .added, flashcardId: card.id)
        flashcardVM?.loadFlashcards()
        rebuildCardMaps(from: flashcardVM?.flashcards ?? dbManager.fetchFlashcards())
        pushUndo(.add(entry: entry, previousStatus: previous, didInsertCard: true, flashcardId: card.id))
        toastMessage = "added"
        recomputeUniverseMetrics()
        onLog?("Essential vocab added: \"\(entry.front)\"")
        return true
    }

    func dismiss(_ entry: EssentialVocabEntry) {
        let previous = progressById[entry.id]?.status
        let previousFlashcardId = progressById[entry.id]?.flashcardId
        upsertProgress(entryId: entry.id, status: .dismissed, flashcardId: nil)
        pushUndo(.dismiss(entry: entry, previousStatus: previous, previousFlashcardId: previousFlashcardId))
        recomputeUniverseMetrics()
        onLog?("Essential vocab dismissed: \"\(entry.front)\"")
    }

    func undoLast() {
        guard let action = undoStack.popLast() else {
            canUndo = false
            return
        }
        canUndo = !undoStack.isEmpty

        switch action {
        case .add(let entry, let previousStatus, let didInsertCard, let flashcardId):
            if didInsertCard, let id = flashcardId {
                if let existing = dbManager.flashcard(id: id), existing.front == entry.front {
                    dbManager.deleteFlashcard(id: id)
                    flashcardVM?.loadFlashcards()
                    rebuildCardMaps(from: flashcardVM?.flashcards ?? dbManager.fetchFlashcards())
                }
            }
            restoreProgress(entryId: entry.id, status: previousStatus, flashcardId: nil)
        case .dismiss(let entry, let previousStatus, let previousFlashcardId):
            restoreProgress(entryId: entry.id, status: previousStatus, flashcardId: previousFlashcardId)
        }
        recomputeUniverseMetrics()
        onLog?("Essential vocab undo")
    }

    func showInVocabulary(_ entry: EssentialVocabEntry) {
        flashcardVM?.selectedDeckKind = .vocab
        flashcardVM?.searchText = entry.front
        flashcardVM?.isShowingEssentialVocab = false
    }

    func cardKind(for entry: EssentialVocabEntry) -> FlashcardKind? {
        cardsByFront[entry.front]?.kind
    }

    func effectiveStatus(_ entry: EssentialVocabEntry) -> EssentialVocabStatus? {
        progressById[entry.id]?.status
    }

    // MARK: - Snapshot batch (Option A)

    func takeBatchSnapshot() {
        batchEntryIds = Array(pendingRanked().prefix(batchSize).map(\.id))
    }

    private func pendingRanked() -> [EssentialVocabEntry] {
        universeEntries
            .filter { effectiveStatus($0) == nil }
            .sorted { $0.rank < $1.rank }
    }

    private func snapshotStillPending() -> [EssentialVocabEntry] {
        batchEntryIds.compactMap { entriesById[$0] }
            .filter { effectiveStatus($0) == nil }
    }

    // MARK: - Reconcile (D13)

    private func reconcile() {
        // 1) Catalog fronts already in deck → ensure progress added
        for entry in entries {
            if let card = cardsByFront[entry.front] {
                let row = progressById[entry.id]
                if row == nil || row?.status != .added || row?.flashcardId != card.id {
                    upsertProgress(entryId: entry.id, status: .added, flashcardId: card.id)
                }
            }
        }

        // 2) Progress added rows: verify card still exists
        let addedRows = progressById.filter { $0.value.status == .added }
        for (entryId, row) in addedRows {
            let entry = entriesById[entryId]
            let byId = row.flashcardId.flatMap { cardsById[$0] }
            let byFront = entry.flatMap { cardsByFront[$0.front] }

            if byId == nil && byFront == nil {
                dbManager.deleteEssentialProgress(listId: listId, entryId: entryId)
                progressById.removeValue(forKey: entryId)
            } else if let card = byFront ?? byId {
                if row.flashcardId != card.id {
                    upsertProgress(entryId: entryId, status: .added, flashcardId: card.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private var universeEntries: [EssentialVocabEntry] {
        entries.filter { $0.rank <= rankCap }
    }

    private func recomputeUniverseMetrics() {
        let universe = universeEntries
        universeSize = universe.count
        addedCount = universe.filter { effectiveStatus($0) == .added }.count
        dismissedCount = universe.filter { effectiveStatus($0) == .dismissed }.count
        pendingCount = universe.filter { effectiveStatus($0) == nil }.count
    }

    private func rebuildCardMaps(from cards: [Flashcard]) {
        cardsById = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var byFront: [String: Flashcard] = [:]
        for card in cards {
            byFront[card.front] = card
        }
        cardsByFront = byFront
    }

    private func upsertProgress(entryId: String, status: EssentialVocabStatus, flashcardId: String?) {
        let now = Date()
        dbManager.upsertEssentialProgress(
            listId: listId,
            entryId: entryId,
            status: status,
            flashcardId: flashcardId,
            updatedAt: now
        )
        progressById[entryId] = EssentialProgressRow(
            listId: listId,
            entryId: entryId,
            status: status,
            flashcardId: flashcardId,
            updatedAt: now
        )
    }

    private func restoreProgress(entryId: String, status: EssentialVocabStatus?, flashcardId: String?) {
        if let status {
            upsertProgress(entryId: entryId, status: status, flashcardId: flashcardId)
        } else {
            dbManager.deleteEssentialProgress(listId: listId, entryId: entryId)
            progressById.removeValue(forKey: entryId)
        }
    }

    private func pushUndo(_ action: EssentialUndoAction) {
        undoStack = [action] // depth 1
        canUndo = true
    }

    private func matchesFilter(_ entry: EssentialVocabEntry) -> Bool {
        switch filter {
        case .pending: return effectiveStatus(entry) == nil
        case .added: return effectiveStatus(entry) == .added
        case .dismissed: return effectiveStatus(entry) == .dismissed
        case .all: return true
        }
    }

    private func matchesSearch(_ entry: EssentialVocabEntry, query: String) -> Bool {
        let q = query.lowercased()
        if entry.front.lowercased().contains(q) { return true }
        if entry.back.lowercased().contains(q) { return true }
        if let phonics = entry.phonics?.lowercased(), phonics.contains(q) { return true }
        if let pos = entry.pos?.lowercased(), pos.contains(q) { return true }
        return false
    }
}
