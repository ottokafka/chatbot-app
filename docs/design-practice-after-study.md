# Design: Practice After Study (Seed Sources Beyond Due)

**Status:** Implemented (Phases 1–3)  
**Date:** 2026-07-11  
**Related:** `/flashcard_system.md`, `design-library-vs-gym.md`  
**Problem owner:** Study → Practice continuity

---

## 1. Problem

The intended learning loop is:

```
Due vocab → Study (FSRS grade) → Practice with AI (usage) → optional Save → Examples
```

What actually happens today:

1. User opens **Study Now** on due vocabulary.
2. Each card is graded; FSRS advances `due` into the future.
3. Session ends. Those cards are **no longer due**.
4. **Practice with AI** is gated on `vocabDueCount > 0` and seeds only from currently due vocab.
5. User cannot practice the words they just studied — the highest-motivation moment is blocked by the same signal that marks study “done.”

This is not a bug in FSRS. It is a **seed-source policy** that conflates two different questions:

| Question | Signal today | Should use |
|----------|--------------|------------|
| What do I need to *review* for memory? | FSRS due | Due |
| What do I want to *practice in context* right now? | (same as due) | Session / intent |

Practice packs are already ephemeral and do **not** update FSRS. Seeding from non-due cards is therefore safe for scheduling — the constraint is product wiring, not the gym/library model.

---

## 2. Goals

1. After a vocab study session, the user can immediately practice **those same words** with AI.
2. Keep practice **ephemeral by default**; saves still land in **Examples** with `parent_flashcard_id`.
3. Do **not** invent a second FSRS queue or change grade semantics.
4. Preserve Library vs Gym: practice seeds remain **vocab** only (never examples).
5. Keep the deck-level **Practice with AI** useful when cards are still due (existing path).
6. Prefer the smallest change that unblocks the post-study moment; leave broader “practice anything” as a later phase.

## 3. Non-goals (this proposal)

- Changing FSRS parameters or re-scheduling on practice
- Parent FSRS influence from example reviews
- Cloze / production-from-blank modes
- Named multi-deck or topic filters
- Persisting practice packs across app quit (still deferred)
- Practicing from **example** cards as seeds (out of scope; gym is already usage)

---

## 4. Product recommendation

### Mental model

> **Study schedules memory. Practice drills usage.**  
> Due answers “what is due now.” Session answers “what I just touched.”

### Seed sources (ordered by priority for v1)

| Source | When | Seeds | UI entry |
|--------|------|-------|----------|
| **A. Last study session** | After completing (or aborting mid-way with ≥1 graded) a **vocab** review | Graded vocab cards from that session | Primary CTA on review completion; soft “recent session” on deck |
| **B. Currently due vocab** | Any time due > 0 | Current due vocab (existing) | Deck **Practice with AI** |
| **C. Manual selection** (phase 2) | User picks cards | Selected vocab | Multi-select → Practice |

**v1 ships A + B.** C is valuable but optional UI; A alone fixes the reported pain.

### Why not only “recently reviewed in last 24h”?

A time window works as a fallback but is worse as the primary fix:

- Unclear which cards (all of yesterday vs this session)
- Harder to explain in UI
- Couples to wall clock instead of user intent

Session-scoped seeds are explicit: “Practice what you just studied.”

### Why not auto-launch practice after every review?

Auto-start costs LLM tokens and may annoy users who only wanted a quick grade pass. Prefer an explicit, high-visibility **Practice these words** action on the completion screen.

---

## 5. UX flows

### 5.1 Primary: post-study completion (new)

When a **vocabulary** review session ends with `reviewedCount ≥ 1`:

```
┌─────────────────────────────────────────┐
│           ✓ Review complete             │
│         You studied N words             │
│                                         │
│  [ Practice these with AI ]  ← primary  │
│  [ Done ]                    ← secondary│
└─────────────────────────────────────────┘
```

- **Practice these with AI** → `beginPracticeGeneration(seedSource: .lastStudySession)`  
  → existing preview sheet → practice session → discard/save (unchanged).
- **Done** → dismiss; keep a short-lived **last session** handle on the deck so the user can still start practice from the dashboard without re-studying.

For **Examples** tab study sessions: no “Practice these with AI” CTA (examples are already sentences; seeding practice from examples is non-goal).

### 5.2 Deck: Practice with AI (existing, generalized)

| Condition | Button | Seeds |
|-----------|--------|-------|
| Vocab due > 0 | Enabled | Due vocab (current behavior) |
| Vocab due == 0, but last study session has seeds | Enabled (secondary affordance) | Last study session |
| Neither | Disabled | — |

Help text should reflect source, e.g.:

- “Generate example sentences from due vocabulary”
- “No cards due — practice the N words from your last study session”

Optional later: menu / split button “Due / Last session / Choose cards…”

### 5.3 Mid-session exit

If the user grades some cards then hits **Done** before finishing:

- Still record graded cards as `lastStudySessionSeeds`.
- Completion view only shows when `reviewComplete`; mid-exit goes to deck — last-session affordance on deck covers this.

### 5.4 Empty / edge cases

| Case | Behavior |
|------|----------|
| Review opened with 0 due | Existing empty completion; no practice CTA |
| Session graded 0 cards (immediate Done) | No last-session seeds; practice CTA hidden |
| Seeds > 10 | Cap at `PracticeGenerationConfig.maxDueSeeds` (10), prefer session order (first studied first, or most recently graded — pick one and document) |
| Parent vocab deleted after session | Resolve seeds by id from current deck; drop missing |
| LLM endpoint missing | Same error path as today |

---

## 6. Architecture

### 6.1 Seed source abstraction

Introduce an explicit seed policy instead of hardcoding “due only”:

```swift
enum PracticeSeedSource: Equatable {
    /// Current FSRS-due vocabulary (legacy default).
    case dueVocab
    /// Vocab cards graded in the most recent study session.
    case lastStudySession
    /// Explicit user selection (phase 2).
    case selectedVocab(ids: [String])
}

struct PracticeSeedResolution {
    let cards: [Flashcard]
    let source: PracticeSeedSource
    /// For UI/copy (“3 due” vs “5 from last study”).
    let labelSeedCount: Int
}
```

### 6.2 Session memory (in-memory first)

On each vocab `gradeCurrentCard` success, append the graded card’s **id** (and optionally a snapshot of front/back at grade time) to:

```swift
// FlashcardViewModel
private(set) var lastStudySession: StudySessionSnapshot?

struct StudySessionSnapshot: Equatable {
    let kind: FlashcardKind          // only .vocab used for practice
    let gradedCardIds: [String]      // order preserved
    let completedAt: Date
}
```

Rules:

- Reset snapshot when a **new** review session starts (`startReviewSession`).
- Append on successful grade.
- **Do not clear** snapshot in `endReviewSession` — that is the point of “last session.”
- Clear when a new session starts, or optionally after successful practice pack generation from that session (product choice: recommend **keep until next study session** so regenerate/retry works).
- No DB migration required for v1.

**Why snapshot ids, not keep `reviewQueue` forever?**  
`endReviewSession` currently clears `reviewQueue`. A dedicated snapshot avoids coupling UI session state to practice seeds and survives dismiss.

**Fresh card content:** resolve ids against `flashcards` at generation time so edits apply; drop ids not found.

### 6.3 Generation path changes

| Component | Change |
|-----------|--------|
| `FlashcardViewModel.beginPracticeGeneration` | Accept `PracticeSeedSource` (default `.dueVocab`); resolve seeds; same generator call |
| `canStartPractice` | `!isGeneratingPractice && (vocabDueCount > 0 \|\| hasLastStudySessionSeeds)` |
| `PracticeCardGenerator` | Rename mental model from “due cards” → “seed cards”; prompts say “flashcards to practice,” not only “due” |
| `PracticePack.sourceDueCount` | Rename or generalize → `sourceSeedCount` (or keep name, document as seed count) for less churn |
| `FlashcardReviewView.completionView` | Vocab + non-empty session → Practice CTA |
| `FlashcardDeckView` | Wire enablement + optional help; pass source when due empty but session exists |
| `Localization` | Completion CTA, help strings, empty errors per source |

### 6.4 What stays the same

- Ephemeral pack → preview → session → discard/save
- Save → `kind = example` + `parent_flashcard_id`
- No FSRS writes from practice
- Cap 10 seeds, 2 examples per seed
- Examples tab study behavior unchanged

```
┌─────────────┐     grade      ┌──────────────────────┐
│ Study Now   │ ─────────────► │ StudySessionSnapshot │
│ (vocab due) │                │ gradedCardIds[]      │
└─────────────┘                └──────────┬───────────┘
                                          │
         dueVocab ────────────────┐       │ lastStudySession
                                  ▼       ▼
                           resolveSeeds([Flashcard])
                                          │
                                          ▼
                               PracticeCardGenerator
                                          │
                                          ▼
                         Preview → Practice → Save/Discard
```

---

## 7. Implementation phases

### Phase 1 — Unblock post-study (recommended ship)

1. Add `StudySessionSnapshot` + populate on vocab grades; start clears previous snapshot.
2. `resolvePracticeSeeds(source:)` + plumb into `beginPracticeGeneration`.
3. Review completion CTA: **Practice these with AI** (vocab sessions with ≥1 graded).
4. `canStartPractice` includes last-session seeds; deck button uses last session when due is empty.
5. Soften generator / L10n copy from “due-only” to “seed cards.”
6. Manual QA checklist (below).

**Effort:** Small — mostly view model + two UI surfaces; no schema.

### Phase 2 — Manual selection ✅

- Multi-select on Vocabulary list → **Practice selected (N)**.
- Hard cap at `PracticeGenerationConfig.maxDueSeeds` (10); selection order preserved.
- Kind picker disabled while selecting; switching away cancels selection.
- Useful for cramming a theme without waiting for due or re-studying.

### Phase 3 — Polish ✅

- Split button / menu for seed source when both due and last session exist (`Menu` + `primaryAction`).
- Persist last-session graded entries in UserDefaults (`StudySessionStore`, TTL 24h).
- Prefer Again/Hard first when capping last-session seeds to 10; preserve order within tiers.
- Analytics-style log: `Practice generation from lastStudySession (n seeds)` (+ weak-first count).

---

## 8. Decision log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary fix | Session seeds + completion CTA | Matches exact user story; zero scheduler risk |
| Auto-start practice? | No | Explicit consent; token cost |
| Persist session across relaunch? | Yes (phase 3, 24h TTL) | Survives quit without a new DB table |
| Practice from examples study? | No | Examples already are sentences |
| When both due and session exist on deck | Prefer **due** for default Practice button; completion always uses **session** | Due remains the “catch up” path; session is contextual |
| Cap ordering for >10 session cards | Again/Hard first, then Good/Easy (study order within tier) | Weak words get practice priority |
| Clear snapshot after practice? | Keep until next study | Allows regenerate / second pack |

---

## 9. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| User confuses practice with more FSRS review | Copy: “Example sentences (does not affect schedule)” already partly present; reinforce on CTA |
| Large session → long generation | Existing max 10 seeds |
| Stale snapshot after bulk delete | Resolve by id; if empty, disable CTA and show clear error |
| Due path regression | Default source remains `.dueVocab` when due > 0 from deck |
| Double practice of weak cards same day | Intentional; practice does not reschedule — acceptable “gym” use |

---

## 10. Testing checklist

- [ ] Study N due vocab → completion shows Practice CTA with correct N
- [ ] CTA generates pack whose parents match studied fronts (spot-check)
- [ ] After Done, with 0 due left, deck Practice still enabled via last session
- [ ] New study session replaces previous snapshot
- [ ] Examples study completion does **not** show Practice CTA
- [ ] Due > 0 still enables Practice; seeds are due cards when started from deck
- [ ] Grade 1 card, Done early → last session has 1 seed; deck Practice works
- [ ] Save from post-study practice → Examples only, parent link set
- [ ] No FSRS field changes when practicing
- [ ] Missing LLM endpoint error unchanged
- [ ] Empty seeds (deleted cards) → graceful error, no crash

---

## 11. Success criteria

1. User who finishes a vocab study session can practice those words **without waiting for them to become due again**.
2. Library vs Gym rules unchanged.
3. Existing due-based Practice with AI still works when cards are due.
4. Implementation stays small: no new tables, no FSRS API changes.

---

## 12. Suggested copy (EN / ZH later)

| Key | EN draft |
|-----|----------|
| Completion CTA | Practice these with AI |
| Completion subtitle | Turn the words you just studied into example sentences |
| Deck help (session) | Practice example sentences from your last study session |
| Error no seeds | No vocabulary available to practice. Study some cards first, or wait until cards are due. |

---

## 13. Open questions (resolve at implement time if needed)

1. **Mid-session CTA?** Only deck last-session is enough for v1.
2. **Should “Practice these” dismiss the review sheet then open preview**, or present practice on top? Prefer: end review → present practice preview (clean stack).
3. **Include only `.vocab` even if we later allow mixed review?** Snapshot stores `kind`; practice only if `kind == .vocab`.

---

## 14. Summary

The gap is **seed policy**, not the practice engine. Track the last vocab study session’s graded cards and offer them as an explicit seed source, with a completion-screen CTA as the main entry. Keep due-based practice as the daily catch-up path. No FSRS changes, no library pollution, phases cleanly from “unbreak the loop” to “practice any selection.”
