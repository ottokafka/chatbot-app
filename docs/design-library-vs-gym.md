# Design: Library vs Gym (Flashcard Kinds)

**Status:** Implemented (phases A–C)  
**Date:** 2026-07-11  
**Related:** `/flashcard_system.md` (product overview)

---

## 1. Problem

The app has a single flashcard pile. AI practice correctly stays ephemeral until save, but **saving favorites** inserts normal cards into that pile. Over time, curated vocabulary and AI example sentences share:

- the same list
- the same due count
- the same Study Now queue

That undermines user ownership of the deck and makes scheduling feel inconsistent (short headwords vs long sentences).

## 2. Goals

1. Separate **vocabulary (library)** from **saved usage examples (gym)** without building full multi-deck.
2. Keep AI practice ephemeral by default; saves land in Examples.
3. Preserve existing FSRS review UX; only change *which* cards enter each queue.
4. Migrate existing cards with zero data loss (all become vocabulary).

## 3. Non-goals

- Named decks / deck manager UI
- Parent-card FSRS updates from example reviews
- Cloze mode
- Resume of in-flight practice packs after quit

## 4. Recommendation

Introduce a required **`FlashcardKind`**: `vocab` | `example`, plus optional **`parentFlashcardId`** linking an example to its source vocab card.

```
Vocabulary (library)     Examples (gym)           Practice session
  user-curated      ←——  saved AI sentences        ephemeral only
  Study vocab            Study examples            discard / save→example
  seeds AI practice
```

**Why not multi-deck?** Role separation is the need; topic decks are a different product. Kinds are smaller, enforceable, and forward-compatible.

## 5. Data model

### Schema

```sql
-- New columns (migrated on existing DBs)
kind TEXT NOT NULL DEFAULT 'vocab';
parent_flashcard_id TEXT NULL;

CREATE INDEX IF NOT EXISTS idx_flashcards_kind_due
  ON flashcards(kind, due);
CREATE INDEX IF NOT EXISTS idx_flashcards_parent
  ON flashcards(parent_flashcard_id);
```

New databases include these columns in `CREATE TABLE flashcards`.

### Swift

```swift
enum FlashcardKind: String, CaseIterable, Identifiable {
    case vocab
    case example
    var id: String { rawValue }
}

struct Flashcard {
    // existing fields…
    var kind: FlashcardKind
    var parentFlashcardId: String?
}
```

### Uniqueness

Keep global unique `front` (current behavior). Duplicates surface the existing duplicate error.

### Delete semantics

Deleting a vocab card **nulls** `parent_flashcard_id` on child examples; examples are retained.

## 6. Behavior matrix

| Action | Kind / effect |
|--------|----------------|
| Chat / manual create | `vocab` |
| Edit card content | Kind unchanged |
| Practice pack (AI) | Not persisted |
| Save practice card(s) | `example` + `parentFlashcardId` when available |
| Study (Vocabulary tab) | Due ∩ `kind = vocab` |
| Study (Examples tab) | Due ∩ `kind = example` |
| Sidebar due badge | Vocab due count only |
| Practice with AI seeds | Due vocab cards only |
| Default dashboard tab | Vocabulary |

## 7. UI

### `FlashcardDeckView`

- Segmented control: **Vocabulary** | **Examples**
- Summary line scoped to selected kind (total · due)
- **Practice with AI** only enabled when vocab due > 0 (visible on both tabs; still seeds vocab)
- **Study Now** uses selected kind’s due count and queue
- Example rows show **From: {parentFront}** when resolvable
- Empty states per kind

### Sidebar (`ContentView`)

- List filtered to selected kind (shared `selectedDeckKind` on view model)
- Section badge uses vocab due

### Review completion

- “No cards due” refers to the kind just studied (or overall vocab for primary messaging)

## 8. API / code touchpoints

| Area | Change |
|------|--------|
| `DatabaseManager` | Migrate columns; SELECT/INSERT bind kind + parent; `fetchFlashcards(kind:)`; `fetchDueFlashcards(kind:)`; clear parents on delete |
| `Flashcard` | `kind`, `parentFlashcardId` |
| `FlashcardViewModel` | `selectedDeckKind`; split due counts; review/practice seed filters; save → example |
| `FlashcardDeckView` | Tabs + study/practice wiring |
| `ContentView` | Sidebar list uses filtered cards; due badge = vocab |
| `Localization` | Tab labels, empty states, study strings |

## 9. Implementation phases

### Phase A — Schema & model
Migration + parse/bind; UI still works; all cards load as vocab.

### Phase B — Behavior
Practice save → example; due/review/practice seed by kind.

### Phase C — UI
Vocabulary \| Examples tabs; parent badge; empty states.

### Phase D (later)
Promote example → vocab; optional further polish.

## 10. Risks

| Risk | Mitigation |
|------|------------|
| Users miss Examples after save | Info alert already summarizes save; copy says “Examples” |
| Due count drops after filter | Expected if sentences were mixed in; vocab due becomes honest |
| Orphan examples after vocab delete | Keep card; clear parent link |

## 11. Testing checklist

- [ ] Fresh DB: create vocab card; appears under Vocabulary
- [ ] Existing DB: old cards appear as vocab
- [ ] Practice save → appears under Examples only
- [ ] Study vocab does not include example due cards
- [ ] Study examples does not include vocab due cards
- [ ] AI practice seeds only from due vocab
- [ ] Delete parent vocab; example remains, no crash
- [ ] Duplicate front still blocked on save

## 12. Key decisions

1. **Kinds over multi-deck** for role separation.
2. **Save defaults to example** — never auto-vocab.
3. **AI seeds from vocab due only.**
4. **Two queues, one FSRS engine.**
5. **Ephemeral practice retained** — kinds fix *saved* outcomes only.

## 13. Success criteria

- Library stays user-owned vocabulary.
- Gym holds saved usage without flooding Study Now for vocab.
- AI can generate freely; permanent pollution requires an explicit save into Examples.
