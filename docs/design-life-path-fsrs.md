# Design: Life Path Game Deck with FSRS

| Field | Value |
|-------|--------|
| **Status** | Implemented (core FSRS game deck, unlimited sessions, carry-over) |
| **Date** | 2026-07-13 (impl 2026-07-16) |
| **App** | DeveloperChatbot (`chatbot-app/`) |
| **Related** | `docs/life-path-vocab-stages.md` (current game; partially superseded for scheduling), `docs/design-library-vs-gym.md`, `Sources/FSRSManager.swift`, `Sources/LifePathViewModel.swift` |
| **Non-goal this doc** | Implementation code; multi-deck UI for Vocabulary library |

---

## 1. Problem

Life Path’s original goal is to **learn frequent words at each developmental age** (baby → toddler → preschool → …). Today the game uses a short-term loop:

- Session = all unmastered words in **current stage only**
- **1× “Got it” → mastered**
- Stage clear unlocks the next stage
- No durable spaced repetition inside the game

That optimizes **level-up fantasy**, not **long-term memory**. After level-up, earlier words largely disappear from play.

### Product decision (this plan)

1. **FSRS is the scheduling engine for the entire Life Path game.**
2. Life Path is a **separate game deck** — not Vocabulary (`kind=vocab`) and not Examples (`kind=example`). No automatic inject into the library.
3. **Carry-over reviews:** when the player is on a later stage, **due cards from all unlocked earlier stages still appear** (e.g. baby words reappear during toddler).

Essential Vocab remains a separate triage funnel into the **library**. Life Path remains a **curriculum + progression game** with its own FSRS state.

---

## 2. Goals & non-goals

### Goals

1. Replace streak/mastery-only scheduling with **full FSRS** on every Life Path word once unlocked.
2. Keep Life Path **isolated** from the user’s Vocabulary / Examples deck (no shared rows, no unique-`front` collisions).
3. Build sessions that mix:
   - **New words** from the current stage (introduction)
   - **Due reviews** from **all stages ≤ current** (carry-over)
4. Redefine **stage clear / grow-up** so it still feels achievable under FSRS.
5. Preserve fantasy: stage map, level-up ceremony, pronunciation path can stay.
6. Reuse existing `FSRS` package + `FSRSManager` patterns (same grades as library review when possible).
7. Migratable path from current `baby_to_child_list` installs.

### Non-goals (v1 of this redesign)

- Named multi-deck manager in the Vocabulary UI
- Auto-adding Life Path words into `flashcards`
- Sharing FSRS state with Essential or library cards
- XP / coins / shop
- Changing catalog content (still bundled JSON stages/entries)
- Cross-language single deck (EN and ZH paths stay separate, as today)
- **Session size caps, max-new-per-session, or daily new limits** (explicitly rejected — unlimited play)

---

## 3. Product model

### 3.1 Mental model

```
┌─────────────────────────────────────────────────────────┐
│  Life Path GAME DECK (per language: zh | en)            │
│  • Catalog syllabus (stages + entries)                  │
│  • Own FSRS state per word                              │
│  • Unlock by stage                                      │
│  • Play sessions = new + due across unlocked stages     │
└─────────────────────────────────────────────────────────┘
         │ no auto-merge
         ▼
┌─────────────────────────────────────────────────────────┐
│  Vocabulary library / Examples gym (unchanged)          │
│  Optional future: manual “Add to Vocabulary”            │
└─────────────────────────────────────────────────────────┘
```

**One-line pitch:**  
Life Path is a **developmental FSRS deck**: grow up by stabilizing each stage’s words, while younger-you words keep coming due as you age.

### 3.2 Deck identity (“separate deck”)

“Deck” here means **product isolation**, not a new Vocabulary deck picker.

| Property | Life Path game deck | Library vocab |
|----------|---------------------|---------------|
| Storage | `baby_to_child_*` (extended) | `flashcards` |
| Scheduler | FSRS on game rows | FSRS on flashcards |
| Uniqueness | `(language, entry_id)` | global unique `front` |
| Entry points | Life Path UI only | Flashcards shell |
| Due badge | Life Path home (game) | Sidebar vocab due |
| Content source | Bundled life-path JSON | User / Essential / chat |

**Do not** store game cards in `flashcards` with a new `kind`. That reintroduces front collisions and mixes due counts.

### 3.3 Player loop (redesigned)

```
Open Life Path
  → See current age + stage graduation progress + due count
  → Play (unlimited mixed queue — player stops when they want)
       • all due words from unlocked stages (carry-over)
       • all new words from unlocked stages (prefer current stage ordering)
  → Grade with FSRS (Again / Hard / Good / Easy)
  → When current stage meets graduation rule → level-up ceremony
  → Unlock next stage’s words as “new” (FSRS empty cards)
  → Older stages remain in the deck forever (for due reviews)
```
---

## 4. Core rules (locked for planning)

### 4.1 Unlock

- Words start **locked** until their stage is reached (unchanged idea).
- On language seed: stage 1 (`baby`) → unlocked / new; later stages → locked.
- On level-up: next stage rows unlock; each gets a fresh FSRS card (`due = now` or “new queue”).

### 4.2 Carry-over (required)

When building a session at stage **S**:

```
eligible = all rows where language=L
           AND stage is unlocked (stage_order ≤ current)
           AND not locked
```

Include:

| Bucket | Definition | Role |
|--------|------------|------|
| **New** | Unlocked, never reviewed (`reps == 0` / status new) | Teach current (and any backlog) stage words |
| **Learning / relearning** | FSRS state learning/relearning, due ≤ now | Stabilize recent mistakes |
| **Review** | Due ≤ now from **any unlocked stage**, including earlier ages | Carry-over memory |

So in **toddler**, baby cards appear whenever FSRS says they are due.

### 4.3 Session composition — **no session locks / no size limits**

**Product rule (locked):** There is **no session size**, **no max-new-per-session**, **no daily new cap**, and **no artificial stop**. The player may review **as far as they want** in one Play run. The only natural end is:

- the queue is empty (nothing due and nothing new left among unlocked stages), or  
- the player **exits** (Done / leave play) at any time.

FSRS still spaces *future* dues after each grade — unlimited play does not mean infinite re-shows of the same card in one run unless the grade puts it due again immediately (e.g. Again → short learning step). That is scheduler behavior, not a session lock.

**Ordering constants only** (not limits):

| Constant | v1 default | Notes |
|----------|------------|--------|
| `preferCurrentStageNew` | true | When ordering **new** cards, current stage before older backlog |
| `order` | due ASC → learning/relearning → new by stage order then rank | Predictable queue; not a cap |

**Algorithm (pseudocode):**

```
now = Date()
unlocked = stages with order ≤ currentStage.order

due = unlocked rows where fsrs.due ≤ now AND reps > 0
     sorted by due ASC, then stage order, then rank

newCurrent = current stage rows where reps == 0
             sorted by rankInStage ASC
newBacklog = earlier unlocked stages where reps == 0
             sorted by stage order ASC, then rankInStage ASC
             // usually empty if graduation requires all introduced

// FULL queue — no take(limit), no sessionTargetSize, no daily budget
queue = due + newCurrent + newBacklog   // if preferCurrentStageNew
// (if preferCurrentStageNew is false: due + all new sorted by stage/rank only)

if queue.isEmpty:
  → "All caught up" empty state (not an error); show next due time if any scheduled future card exists
else:
  → play until queue exhausted OR player exits
```

**Re-queue after Again (optional policy):** If FSRS sets `due ≤ now` after Again (learning steps), the card may reappear later in the **same** run by appending to the end of the remaining queue, or wait until the next Play. Prefer **append-to-end in same run** so unlimited play can still drill weak cards without a hard session wall.

**What unlimited does *not* mean:** Stage unlock still gates future-stage words. Locked stages stay locked until graduation. Unlimited only removes **session/daily quantity locks**, not the life-path syllabus gate.

### 4.4 Grading

Align with library review for consistency:

| Grade | FSRS `Rating` | UI |
|-------|---------------|-----|
| Again | `.again` | Red |
| Hard | `.hard` | Orange |
| Good | `.good` | Green (primary) |
| Easy | `.easy` | Blue |

**Pronunciation path:** keep as an alternate input that maps to a grade:

- Pass threshold → **Good** (or Hard if you want stricter speech mode later)
- Fail → **Again** (retry policy: either re-queue in session or wait for FSRS due — prefer FSRS due after one fail to avoid infinite loops)

Optional v1.1: keep a simplified 2-button mode (Wrong → Again, Got it → Good) for younger UX; still write FSRS.

### 4.5 Stage graduation (“cleared” under FSRS)

One-shot mastery is removed. Implemented rule (v1 relaxed, 2026-07-16):

A stage **S** is **cleared** when all hold:

1. **All introduced:** every entry in S has `reps ≥ 1` (seen at least once) and is unlocked.
2. **Stability ratio:** at least `graduationStableRatio` (80%) of introduced cards meet `meetsGraduationCriteria` (reps ≥ 2, not in relearning).

Non-stable cards **carry forward** as due reviews into future sessions via the existing carry-over mechanism — the player never hits a wall.

```swift
// LifePathGame.graduationStableRatio = 0.80
cleared(S) =
    all cards in S are unlocked
    AND all cards have reps >= 1
    AND (stableCount / totalCount) >= 0.80
```

Tune `graduationStableRatio` after playtest.

**On clear:**

1. Append S to `stages_cleared`
2. Set current/highest to next stage
3. Unlock next stage rows (fresh FSRS cards)
4. Show level-up notify
5. **Do not delete or freeze** stage S rows — they remain fully schedulable forever

### 4.6 After level-up

- Next stage words become available as **new**.
- Previous stage words continue FSRS; they show up in future sessions via carry-over.
- Home UI should show something like:  
  **Toddler · 12 due (incl. 5 from Baby)**  
  so carry-over is visible, not surprising.

### 4.7 “Mastered” concept

Repurpose or drop game `mastered`:

| Old | New |
|-----|-----|
| `mastered` = 1 correct | **Retired as clear condition** |
| Progress bar | % of stage meeting graduation sub-criteria (introduced / stable) |
| `totalMastered` profile field | Redefine as “words meeting stable threshold” or keep as count of words with `reps≥1` |

Suggested statuses for UI only (derived from FSRS, not a parallel scheduler):

| UI status | Derived from |
|-----------|----------------|
| Locked | stage locked |
| New | unlocked, reps == 0 |
| Learning | state learning/relearning |
| Reviewing | state review, not yet “stable” |
| Stable | meets graduation bar for that word |

Persist FSRS fields; **derive** display status.

---

## 5. Data model

### 5.1 Strategy

**Extend `baby_to_child_list` with full FSRS columns** (same shape as `flashcards` FSRS fields).  
This *is* the game deck table.

Do **not** create rows in `flashcards` for gameplay.

Optional later: `flashcard_id` remains for manual “Add to Vocabulary” bridge (out of scope for core FSRS plan).

### 5.2 Schema changes

Current lightweight fields (`correct_count`, `wrong_count`, `correct_streak`, `due_at`, `ease`) become insufficient alone.

**Add FSRS columns** (mirror library):

```sql
-- Migration: ALTER TABLE baby_to_child_list ADD COLUMN ...
due              REAL,          -- prefer rename due_at → due OR map due_at as FSRS due
stability        REAL NOT NULL DEFAULT 0,
difficulty       REAL NOT NULL DEFAULT 0,
elapsed_days     REAL NOT NULL DEFAULT 0,
scheduled_days   REAL NOT NULL DEFAULT 0,
learning_steps   INTEGER NOT NULL DEFAULT 0,
reps             INTEGER NOT NULL DEFAULT 0,
lapses           INTEGER NOT NULL DEFAULT 0,
state            INTEGER NOT NULL DEFAULT 0,  -- CardState raw value
last_review      REAL,
```

**Pragmatic v1 approach (less rename churn):**

- Keep `due_at` as the FSRS `due` timestamp (single due field).
- Add the other FSRS fields above.
- Keep `correct_count` / `wrong_count` as **analytics counters** (increment on Good/Easy vs Again), not as the scheduler.
- Deprecate `correct_streak` for mastery; optional keep for UI streaks.
- `status` column: either  
  - **A)** derive in app and stop writing `mastered` as authority, or  
  - **B)** write derived status after each review for cheap SQL filters (`new`/`learning`/`review`/`stable`/`locked`).

**Recommendation:** **B** with expanded status enum:

```text
locked | new | learning | review | stable
```

(migrate old `available` → `new`, `mastered` → recompute from FSRS or map to `stable` only if criteria met else `review`)

### 5.3 Swift model

```swift
struct LifePathListRow {
    // identity + catalog denorm (existing)
    let rowId: String
    let language: String
    let entryId: String
    let stageId: String
    let front: String

    var status: LifePathWordStatus   // derived/cached
    var correctCount: Int            // analytics
    var wrongCount: Int
    // remove scheduling role of correctStreak / ease or keep unused

    var fsrsCard: Card               // FSRS package Card (same as Flashcard)

    var flashcardId: String?         // optional future bridge
    let createdAt: Date
    var updatedAt: Date
}
```

`dueAt` becomes `fsrsCard.due`.

### 5.4 Profile

Keep `baby_to_child_profile`. No daily-new tracking fields (no new caps).

| Field | Purpose |
|-------|---------|
| existing `total_reviews` | Increment on every grade |
| `total_mastered` | Redefine = count stable words |

### 5.5 Isolation guarantees

- Life Path DB APIs never insert into `flashcards` for reviews.
- Library Study Now never queries `baby_to_child_list`.
- Same surface string may exist in both systems independently (by design for separate decks).

---

## 6. Session & UI plan

### 6.1 Home (`LifePathHomeView`)

Show:

- Current stage title + avatar fantasy
- **Graduation progress:** e.g. `18/50 stable` or two meters: Introduced / Stable
- **Due now:** count across all unlocked stages
- **New remaining** in current stage
- Breakdown chip: `Due · 5 baby · 8 toddler` (carry-over transparency)
- CTA: **Play** (disabled only if due==0 and new==0 and stage not blocked)
- Stage map: cleared / current / locked; optional per-stage due badge

### 6.2 Play (`LifePathPlayView`)

- Session progress: **cards done this run** and **remaining in queue** (e.g. `12 done · 47 left`) — informational only, not a cap
- Player may exit anytime; no forced end at N cards
- Card chrome: optional **stage pill** on the card (`Baby` vs `Toddler`) so carry-over is understandable
- Reveal → **4 grade buttons** (reuse patterns from `FlashcardReviewView`)
- Pronunciation flow can remain; map pass/fail → Good/Again
- End / leave summary: reviewed N · new M · again K · stage graduation % delta

### 6.3 Level-up

Unchanged ceremony shape; copy may change:

- From: “You mastered every baby word!”
- To: “You’ve grown past baby words — Toddler language unlocked. Baby words will still visit for review.”

### 6.4 Empty / caught-up states

| State | Message |
|-------|---------|
| Due=0, new remain | “Ready to learn new {stage} words” (Play starts full new queue) |
| Due=0, new=0, stage not clear | “Waiting for reviews to mature — come back later” (show next due time) |
| Due=0, stage clearable | Auto-trigger or banner “You’ve graduated — Grow up!” |
| Due=0, new=0, all stages done | “Life Path caught up” |

**Next due time** is important once FSRS is live; without it the game feels broken.

---

## 7. Algorithm details

### 7.1 Review write path

```
onGrade(entry, rating):
  row = listRows[entry.id]
  item = try FSRSManager.shared.review(card: row.fsrsCard, grade: rating)
  row.fsrsCard = item.card
  row.updatedAt = now
  row.last side effects:
    if rating == .again { wrongCount += 1 } else if rating ∈ {good,easy} { correctCount += 1 }
  row.status = deriveStatus(row)
  upsert row
  profile.totalReviews += 1
  checkStageGraduation(currentStage)
  // if Again left card due now: append to end of remaining session queue (optional same-run drill)
```

### 7.2 Derive status

```
if locked → locked
else if reps == 0 → new
else if state ∈ {learning, relearning} → learning
else if meetsStableCriteria → stable
else → review
```

### 7.3 Graduation check

After each review (and on session end):

```
if current stage not in stagesCleared
   AND all entries in stage satisfy stable/graduation criteria
→ performLevelUp()
```

### 7.4 Seed / unlock

```
seed:
  for entry in catalog:
    row.fsrsCard = empty Card(due: now)  // only matters when unlocked
    row.status = entry.stage == first ? new : locked

unlock(stage):
  for row in stage:
    status = new
    fsrsCard = empty Card(due: now)  // available immediately as new
```

---

## 8. Migration from current game

Existing installs have streak mastery and may have `mastered` words with weak FSRS-less state.

### 8.1 Policy options

| Policy | Behavior | Tradeoff |
|--------|----------|----------|
| **A. Soft reset scheduling** | Keep profile stage; reset all FSRS to empty; re-derive status from old status | Fair scheduling, some progress loss |
| **B. Credit mastered** | `mastered` → Card with artificial stability (e.g. due in 3d, reps=2, state=review) | Feels nicer; approximate |
| **C. Hard reset** | Wipe list+profile for language | Cleanest; harshest |

**Recommendation:** **B** for UX + recompute:

- `locked` → locked, empty card  
- `available` → new, empty card  
- `learning` → learning-ish empty or due now, reps=1  
- `mastered` → seed mild review card (stability ~2–3d, due = now + 1d) so they reappear as carry-over without forcing full re-intro  

Run once on schema version bump (`life_path_fsrs_schema = 1` in UserDefaults or profile column).

### 8.2 Tests

- Catalog load unchanged  
- Session includes earlier-stage due cards when current is toddler  
- Full queue includes **all** due + **all** new (no size / daily caps)  
- Player exit mid-queue persists graded cards; ungraded remain for next Play  
- Graduation does not fire on single Good  
- Level-up unlocks next stage news  
- Library flashcard counts unchanged after Life Path reviews  
- Migration maps old statuses  

---

## 9. Architecture / code touchpoints

| Area | Change |
|------|--------|
| `DatabaseManager` | Migrate `baby_to_child_list`; read/write FSRS fields; queries for due across stages |
| `LifePathModels` | Status enum; row carries `Card`; game constants for graduation (not session caps) |
| `LifePathViewModel` | Session builder rewrite; grade → FSRS; graduation rewrite; home metrics |
| `LifePathViews` | 4-button grades; due/next-due UI; stage pill; progress semantics |
| `FSRSManager` | Possibly add helper `dueRows` generic or Life Path-specific wrapper; reuse `review` |
| `FlashcardViewModel` / library | **No change** for core plan |
| `Tests/LifePathTests` | Expand heavily; optional FSRS integration tests parallel to `FSRSIntegrationTests` |
| Docs | This doc + update `life-path-vocab-stages.md` status section pointing here for scheduling |

### Suggested module boundaries

```
LifePathScheduler (new, pure logic, testable)
  - buildSession(rows, stages, profile, now) -> [entryId]  // full queue, no limits
  - deriveStatus(card) -> status
  - stageMeetsGraduation(rowsForStage) -> Bool
  - migrateLegacyRow(...)

LifePathViewModel
  - orchestration, UI state, pronunciation, persistence
```

Keep scheduling pure for unit tests without SwiftUI.

---

## 10. Pros / cons of this plan (explicit)

### Pros

- Matches original learning intent with a real memory model  
- Separate deck avoids library pollution and unique-front fights  
- Carry-over keeps childhood vocabulary alive after level-up  
- One algorithm already in the app (`FSRS`)  
- Stage fantasy can remain if graduation is designed carefully  

### Cons / risks

- Level-ups become slower (days, not one sitting) — copy and UX must set expectations  
- Preschool (~300 words) + carry-over can mean **long optional queues** — player chooses how far to go; home should show honest remaining counts  
- “All caught up, wait for due” feels less game-like — need next-due messaging  
- Dual status (FSRS + stage unlock) is more complex than v1 game  
- Migration ambiguity for existing mastered rows  

### Mitigations

- Clear home stats (due / new / remaining) and next due  
- **No session or daily locks** — exit anytime; progress is per-card FSRS  
- Progress UI: `done · left` so long queues feel navigable, not forced  
- Graduation criteria playtested on baby (50 cards) before expecting preschool polish  
- Optional later: “Reviews only” vs “New only” filters (convenience, not caps)

---

## 11. Open decisions (resolve before / during PR1)

| # | Question | Options | Suggestion |
|---|----------|---------|------------|
| 1 | Graduation criteria strictness | 2× Good vs stability≥3d | Start with **reps≥2 and not relearning**; tune up |
| 2 | Grades UI | Always 4-button vs 2-button map | **4-button** for parity; 2-button later if needed |
| 3 | Pronunciation pass maps to | Good vs Hard | **Good** |
| 4 | Session size / new caps | — | **None** (locked): unlimited play, exit anytime |
| 5 | Again after Again in same run | append end / wait next Play | **Append to end** of remaining queue |
| 6 | Migration | A / B / C | **B credit mastered** |
| 7 | Show stage pill on cards | yes / no | **yes** (explains baby-in-toddler) |
| 8 | Auto level-up vs confirm button | auto modal / “Grow up” CTA | Keep **blocking modal** when criteria met |
| 9 | Manual add to Vocabulary | later / never | **Later**; not in FSRS core |

---

## 12. Implementation plan (PR DAG)

Planning order; each PR should be shippable/testable.

### PR1 — Schema + models + FSRS persistence

- Migrate `baby_to_child_list` FSRS columns  
- `LifePathListRow.fsrsCard` round-trip  
- Seed/unlock creates empty `Card`  
- Unit tests for DB parse/bind  
- **No UX change yet** (can still write legacy grade path behind flag if needed)

### PR2 — `LifePathScheduler` pure logic

- Session builder with carry-over + **full unlimited queue** (no size/daily caps)  
- Status derivation  
- Graduation predicate  
- Heavy unit tests with fake clocks / cards  

### PR3 — ViewModel integration

- `startRound` uses scheduler  
- `grade` calls `FSRSManager.review`  
- Level-up uses new graduation  
- Migration on load  
- Preserve pronunciation → grade mapping  

### PR4 — UI

- Four grade buttons  
- Home due / introduced / stable metrics  
- Stage pill on play cards  
- Caught-up + next due empty states  
- Level-up copy  

### PR5 — Polish + playtest tuning

- Constants pass (graduation only; **no session caps**)  
- Analytics counters  
- DEV reset still works  
- Update `life-path-vocab-stages.md` “scheduling” section to point at this doc  
- Optional: per-stage due breakdown chips  

**Parallelism:** PR1 → PR2 → PR3 → PR4 → PR5 (mostly linear; PR2 can start once PR1 model types exist).

---

## 13. Acceptance criteria (definition of done)

1. Reviewing a Life Path card updates FSRS fields only in `baby_to_child_list`, not `flashcards`.  
2. With current stage = toddler and a baby card due, **Play** can show that baby card.  
3. Play queue includes **all** due + **all** new unlocked cards — **no session size or daily/new caps**.  
4. Player can exit mid-queue anytime; graded progress is kept.  
5. A single Good does **not** clear a stage of 50 words.  
6. Meeting graduation criteria unlocks the next stage and shows level-up.  
7. After level-up, previous stage cards remain reviewable when due.  
8. “All caught up” shows next due time instead of a dead end.  
9. Essential / Vocabulary flows unchanged.  
10. Tests cover scheduler, graduation, migration, isolation, and unlimited queue.  

---

## 14. Future extensions (out of scope now)

- Manual “Add stable words to Vocabulary”  
- Shared skin components between `FlashcardReviewView` and Life Path play  
- “Memories” mode: only earlier-stage dues  
- Soft 90% graduation for huge stages  
- Server sync  
- True multi-deck product for library topics  

---

## 15. Summary decision

| Topic | Decision |
|-------|----------|
| Scheduler | **FSRS for entire Life Path game** |
| Deck | **Separate game deck** in `baby_to_child_list`, not library |
| Carry-over | **Yes** — all unlocked stages contribute due reviews |
| Session limits | **None** — no session size, no new/day caps; play until empty or exit |
| Stage clear | **Graduation criteria** (multi-review / stability), not 1× correct |
| Library inject | **Not part of this plan** |
| Implementation | Phased PR1–PR5 above |

**Bottom line:** Life Path becomes a **stage-gated FSRS curriculum deck** with a growth fantasy. Level-up unlocks new words; FSRS keeps old ages alive inside the same game deck forever. Sessions are **unlimited** — only FSRS scheduling and stage unlocks constrain what appears, not artificial session locks.
