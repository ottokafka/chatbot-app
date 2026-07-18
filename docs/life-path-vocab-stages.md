# Life Path

# Plan: Baby → Child Flashcard Game (Life Path)

| Field | Value |
|-------|--------|
| **Status** | Implemented (baby + toddler + preschool; **FSRS game deck** + stage level-up; **no XP/coins**). Scheduling superseded by `docs/design-life-path-fsrs.md`. |
| **Date** | 2026-07-12 (FSRS redesign 2026-07-16) |
| **Supersedes** | Earlier draft that *replaced* Essential Vocab with developmental lists |
| **App** | DeveloperChatbot (`chatbot-app/`) |
| **Related** | `docs/design-essential-vocab-list.md` (unchanged), `Sources/EssentialVocab/*` (kept) |

---

## 1. Product decision (locked)

| System | Fate | Role |
|--------|------|------|
| **Essential Vocab** (Top 100 / 500 frequency) | **Keep as-is** | Onboarding / enrichment funnel into Vocabulary library |
| **Baby → Child Life Path** | **New parallel system** | Flashcard **game**: grow from baby vocabulary upward |

These are **two separate features**. They do not share progress tables, UI sheets, or unlock rules.

```
┌──────────────────────────────┐     ┌──────────────────────────────────┐
│  Essential Vocab (existing)  │     │  Baby→Child Game (NEW)           │
│  essential_* JSON            │     │  life_path_* JSON (catalog)      │
│  essential_vocab_progress    │     │  baby_to_child_list (+ profile)  │
│  Triage: Add / I know        │     │  Play: study cards, clear stages │
│  → kind=vocab library        │     │  → grow stage + optional vocab   │
└──────────────────────────────┘     └──────────────────────────────────┘
```

**One-line pitch:**  
A life-path flashcard game where you start as a **baby**, clear baby words, get notified that you grew into a **toddler**, and keep aging through childhood stages — without touching the Essential frequency lists. **No XP or coins.**

---

## 2. What this is (and is not)

### Is

- A **new game mode** with its own DB tables, catalog, ViewModel, and UI.
- A **flashcard game**: player studies words in the current life stage (flip / rate / advance).
- A **progression game**: complete stage vocabulary → **grow up** (baby → toddler → preschool → …) with a **celebration notify**.
- Optionally may **also** insert or link `kind = vocab` flashcards so words land in the library (see §6).

### Is not

- A redesign of FSRS core or `FlashcardKind`.
- A replacement for Essential Vocab.
- A third permanent “deck kind” in the library/gym model (game has its own run state; library stays vocab/example).
- Soft triage-only (Essential stays the triage product; this is **play + grow**).
- An XP / coin economy, shop, or spendable currency (removed from product; inert DB columns only).

---

## 3. Player fantasy & loop

```
Start life as Baby
    → Study baby vocabulary (flashcards)
    → Master every word in the stage
    → Clear stage requirement
    → NOTIFY: "You grew up! You're a Toddler now."
    → Unlock toddler vocabulary
    → Repeat through Pre-K → Grade 1 → … (content-capped per release)
```

### Core loop (session)

1. Open **Life Path** game.  
2. See avatar age/stage + progress bar for current stage.  
3. Play a **full-stage session** of flashcards from the **current stage only**.  
4. On each correct review: word progress toward mastery.  
5. On stage clear: **level-up ceremony** (grow-up notify; unlock next stage).  
6. Session complete → **Next level** to start the new stage.

### Secondary loop (optional library bridge)

After a word is “mastered” in the game (or on first success), offer **Add to Vocabulary** so it appears in the normal library — **does not** replace game progress.

---

## 4. Life stages (content ladder)

Shared stage IDs for EN + ZH catalogs. v1 content can ship only early stages.

| Stage ID | Display (EN) | Display (ZH) | Age fantasy | Curated words (target) | v1 ship? |
|----------|--------------|--------------|-------------|------------------------|----------|
| `baby` | Baby | 婴儿 | First words | ~50 | **Yes** |
| `toddler` | Toddler | 幼儿 | First 100–150 | ~150 | **Yes** |
| `preschool` | Preschool | 学前 | Daily life | 299 | **Yes** (shipped) |
| `grade1` | Grade 1 | 一年级 | School start | ~300 | Later |
| `grade2` … `grade6` | Grade 2–6 | 二–六年级 | School growth | ~300–400 each | Later |

**Unlock rule (hard):**  
Stage \(N+1\) unlocks only when stage \(N\) is **cleared**. No skipping.

**Clear rule (v1 default):**  
Stage is cleared when every word in that stage reaches game status `mastered` (see §7).  
Alternative (softer, if playtests feel grindy): 90% mastered + rest at least `seen` — lock only after product playtest; default remains 100% mastered.

---

## 5. Architecture overview

```
┌─ Bundle ─────────────────────────────────────────────┐
│  Resources/LifePath/                                 │
│    manifest.json                                     │
│    life_path_en_v1.json   (or per-stage files)       │
│    life_path_zh_v1.json                              │
└──────────────────────────┬───────────────────────────┘
                           │ load
                           ▼
┌─ LifePathCatalog ────────────────────────────────────┐
│  stages[], entries[] by language                     │
└──────────────────────────┬───────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
┌─ SQLite ─────────────────────────────────────────────┐
│  baby_to_child_profile     (stage, mastery counts)   │
│  baby_to_child_list        (per-word game progress)  │
│  baby_to_child_rewards     (LEGACY inert table)      │
│  flashcards (optional link when user adds to vocab)  │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌─ LifePathViewModel + UI ─────────────────────────────┐
│  Stage map · Play session · Level-up modal           │
└──────────────────────────────────────────────────────┘
```

Essential stack (`EssentialVocab*`, `essential_vocab_progress`) remains **untouched**.

---

## 6. Database design

### 6.1 `baby_to_child_list` (required — per-word game progress)

User asked for this table by name. It stores **how far the player has gotten on each life-path word**.

```sql
CREATE TABLE IF NOT EXISTS baby_to_child_list (
    id              TEXT PRIMARY KEY,          -- uuid row id
    language        TEXT NOT NULL,             -- 'zh' | 'en'
    entry_id        TEXT NOT NULL,             -- catalog entry id, e.g. 'en_baby_001'
    stage_id        TEXT NOT NULL,             -- 'baby' | 'toddler' | ...
    front           TEXT NOT NULL,             -- denormalized for queries / offline
    status          TEXT NOT NULL
        CHECK (status IN ('locked', 'available', 'learning', 'mastered')),
    correct_count   INTEGER NOT NULL DEFAULT 0,
    wrong_count     INTEGER NOT NULL DEFAULT 0,
    ease            REAL,                      -- optional lightweight scheduling
    due_at          REAL,                      -- unix time; null = not scheduled
    last_reviewed_at REAL,
    mastered_at     REAL,
    flashcard_id    TEXT,                      -- optional FK-ish link to flashcards.id
    created_at      REAL NOT NULL,
    updated_at      REAL NOT NULL,
    UNIQUE (language, entry_id)
);

CREATE INDEX IF NOT EXISTS idx_btc_list_lang_stage_status
  ON baby_to_child_list(language, stage_id, status);

CREATE INDEX IF NOT EXISTS idx_btc_list_due
  ON baby_to_child_list(language, due_at);
```

| Column | Meaning |
|--------|---------|
| `status = locked` | Word belongs to a future stage |
| `available` | In current (or past) stage, not yet practiced |
| `learning` | Seen at least once; not yet mastered |
| `mastered` | Meets mastery threshold (counts toward stage clear) |
| `flashcard_id` | If player (or auto-rule) created a library vocab card |

**Seed rule:** On first launch of Life Path for a language, insert all catalog rows for that language: current stage words → `available`; future stages → `locked`. On stage unlock, flip that stage’s rows from `locked` → `available`.

### 6.2 `baby_to_child_profile` (player / run state)

One row per learning language (player can have EN and ZH paths).

```sql
CREATE TABLE IF NOT EXISTS baby_to_child_profile (
    language            TEXT PRIMARY KEY,      -- 'zh' | 'en'
    current_stage_id    TEXT NOT NULL,         -- e.g. 'baby'
    highest_stage_id    TEXT NOT NULL,         -- farthest ever unlocked
    -- LEGACY economy (inert): always 0; not used by gameplay/UI
    xp                  INTEGER NOT NULL DEFAULT 0,
    coins               INTEGER NOT NULL DEFAULT 0,
    lifetime_xp         INTEGER NOT NULL DEFAULT 0,
    streak_days         INTEGER NOT NULL DEFAULT 0,
    last_play_day       TEXT,                  -- 'yyyy-MM-dd' local
    total_reviews       INTEGER NOT NULL DEFAULT 0,
    total_mastered      INTEGER NOT NULL DEFAULT 0,
    stages_cleared_json TEXT NOT NULL DEFAULT '[]',  -- ["baby"]
    pending_notify_json TEXT,                  -- queue for level-up UI if app killed mid-ceremony
    created_at          REAL NOT NULL,
    updated_at          REAL NOT NULL
);
```

### 6.3 `baby_to_child_rewards` (legacy — unused)

Originally planned as an XP/coins ledger. **Product does not use XP or coins.**  
Table is still created for existing installs and wiped on DEV reset; **no app APIs read or write grants.**

### 6.4 Relation to `flashcards`

| Concern | Decision |
|---------|----------|
| Game reviews | Use **`baby_to_child_list`** scheduling fields (simple SM-2-lite or “N correct in a row”), **not** full FSRS on a shadow card — keeps game independent |
| Library | Optional: “Add to Vocabulary” sets `flashcard_id` and inserts `kind = vocab` |
| Unique front | Same global `idx_flashcards_front` as today; if front exists, link only |
| Essential | **No shared rows** with `essential_vocab_progress` |

---

## 7. Gameplay: flashcard session

### 7.1 Session build

```
active = baby_to_child_list WHERE language=? AND stage_id=current
                              AND status IN ('available','learning')
order: due_at ASC NULLS FIRST, then wrong_count DESC, then entry order
limit: round size 10 (v1)
if fewer than 10 non-mastered: fill with weak mastered for mixed review (optional)
```

### 7.2 Card face

Same bilingual idea as Essential rows:

- Learning ZH: front = 汉字, phonics, back = English gloss  
- Learning EN: front = English, back = Chinese gloss  

UI is **game-styled** (big type, stage chrome) — separate from Essential list sheet and from Library review chrome (can share low-level flip components later).

### 7.3 Rating (v1 simple)

| Action | Effect on word |
|--------|----------------|
| **Got it** (correct) | `correct_count++`; on mastery streak met → `mastered` |
| **Again** (wrong) | `wrong_count++`; status → `learning`; reset mastery streak; re-queue card |

**Mastery threshold (shipped):** **1 correct** = mastered (first “Got it” clears the word).  
No XP/coins are granted on either action.

### 7.4 Stage clear detection

After each review upsert:

```
if count(status='mastered' WHERE stage=current) == count(entries in stage catalog)
   AND current stage not already in stages_cleared
→ trigger progression (§9)
```

---

## 8. Economy (removed)

**Decision:** Life Path does **not** use XP, coins, titles, frames, or a reward shop.

| Artifact | Status |
|----------|--------|
| Profile `xp` / `coins` / `lifetime_xp` | **Inert** DB columns (always 0) — kept to avoid schema migration |
| `baby_to_child_rewards` | **Legacy** table; created/reset only; no Swift grant APIs |
| Catalog `clearReward` | **Removed** from JSON |
| Play UI | Stage progress + mastery only |

Progression reward is **growing into the next life stage**, not a currency.

---

## 9. Progression notify (“you grew up”)

### 9.1 When

On stage clear:

1. Append stage to `stages_cleared_json`.  
2. Set `pending_notify_json` to a structured payload (survive process death).  
3. Unlock next stage rows in `baby_to_child_list` (`locked` → `available`).  
4. Set `current_stage_id` / `highest_stage_id` to next stage.  
5. Present **Level-Up modal** (blocking, celebratory).

### 9.2 Notify payload

```json
{
  "type": "stage_clear",
  "fromStageId": "baby",
  "toStageId": "toddler",
  "title": { "en": "You grew up!", "zh": "你长大了！" },
  "body": {
    "en": "Baby words complete. Welcome to Toddler.",
    "zh": "婴儿词汇已全部掌握，欢迎进入幼儿阶段。"
  }
}
```

### 9.3 Surfaces

| Surface | Behavior |
|---------|----------|
| **In-app modal** | Primary — stage clear ceremony + Continue |
| **Session complete** | **Next level** starts the unlocked stage session |
| **Profile badge** | Current stage name on Life Path home |

Clear `pending_notify_json` only after user taps **Continue** on the modal (so relaunch can re-show).

---

## 10. Catalog (bundled content)

### 10.1 Layout

```
Sources/LifePath/   (or Resources/LifePath/)
  manifest.json
  life_path_en_v1.json
  life_path_zh_v1.json
```

Optional split: `en_baby.json`, `en_toddler.json`, … merged by catalog loader.

### 10.2 Entry schema

```json
{
  "listId": "life_path_en",
  "listVersion": 1,
  "language": "en",
  "stages": [
    {
      "id": "baby",
      "order": 0,
      "title": { "en": "Baby", "zh": "婴儿" },
      "subtitle": { "en": "First words", "zh": "开口词" },
      "targetCount": 50
    },
    {
      "id": "toddler",
      "order": 1,
      "title": { "en": "Toddler", "zh": "幼儿" },
      "subtitle": { "en": "Everyday talk", "zh": "日常用语" },
      "targetCount": 66
    }
  ],
  "entries": [
    {
      "id": "en_baby_001",
      "stageId": "baby",
      "rankInStage": 1,
      "front": "mama",
      "back": "妈妈",
      "phonics": null,
      "tags": ["people", "social"]
    }
  ]
}
```

### 10.3 Content sources (unchanged research intent)

- **Baby:** common first words (EN + Mandarin parallels).  
- **Toddler:** first-100 category structure (social, actions, food, body, …).  
- **Preschool+:** thematic + school lists; Chinese 词-first from grade materials.  

Overlap across stages allowed; each `entry_id` is unique. Same surface form in a later stage should be rare; if needed, new id + note in tags.

### 10.4 Essential catalogs

`essential_en_v1.json` / `essential_zh_v1.json` / `essential_vocab_progress` — **no changes required** by this plan.

---

## 11. App structure (Swift)

| Component | Responsibility |
|-----------|----------------|
| `LifePathCatalog` | Load/validate JSON, cache stages/entries |
| `LifePathModels` | Stage, Entry, Profile, NotifyPayload |
| `LifePathViewModel` | Profile, list rows, session, stage clear, level-up |
| `LifePathHomeView` | Stage map, mastery progress, Play CTA |
| `LifePathPlayView` | Flashcard full-stage session UI |
| `LifePathLevelUpView` | Blocking progression ceremony |
| `DatabaseManager` | List + profile CRUD (rewards table legacy only) |
| `L10n` | Strings for game (separate keys from Essential) |

### Navigation

- Entry points: Vocabulary area secondary button **“Life Path”** / game icon; optional empty-state **secondary** CTA (Essential remains primary empty CTA for library onboarding).  
- Host as `.sheet` or full-screen cover from `ContentView` (same pattern as Essential).  
- **Do not** fold into `EssentialVocabListView`.

### Preferences

```text
lifePath.language          // zh | en
lifePath.soundEnabled
lifePath.reduceMotion
```

---

## 12. UX wire (screens)

### A. Life Path Home

- Avatar + current stage name (“Baby”)  
- Progress: `mastered / total` for stage  
- Stage rail: Baby ✓ · Toddler 🔒 · …  
- Primary: **Play**  
- Secondary: Word list (current stage)  

### B. Play session

- Card stack / single card flip  
- Got it / Again  

### C. Level-up (notify)

- Full-screen: “You grew up!”  
- From Baby art → Toddler art  
- **Continue** → session complete → **Next level** starts unlocked stage  

### C′. Session complete

- Stats: correct / wrong for the session  
- Primary: **Next level**  
- Toolbar **Done** still dismisses Life Path  

### D. Stage word list (read-only + status)

- Shows baby_to_child_list for current/past stages  
- Filter: learning / mastered  
- Optional “Add to Vocabulary” per row  

---

## 13. Relationship diagram (systems)

```
                    ┌─────────────────────┐
                    │   User              │
                    └──────────┬──────────┘
           ┌───────────────────┼───────────────────┐
           ▼                                       ▼
 ┌─────────────────────┐                 ┌─────────────────────┐
 │ Essential Vocab     │                 │ Life Path Game      │
 │ (frequency list)    │                 │ (baby→child)        │
 │ triage only         │                 │ play + grow         │
 └──────────┬──────────┘                 └──────────┬──────────┘
            │ Add                                    │ optional Add
            ▼                                        ▼
            └────────────► flashcards (vocab) ◄──────┘
                              │
                              ▼
                         FSRS Study / Practice / Speaking
```

Both systems can feed the library; only Life Path has **stages, mastery progress, and growth notify**.

---

## 14. Implementation plan (phased)

### Shipped

- Schema: `baby_to_child_list` + `baby_to_child_profile` (+ legacy rewards table inert).  
- Catalog: baby + toddler + preschool (EN + ZH).  
- Play loop: full-stage session, Got it / Again, mastery.  
- Progression: stage clear → level-up modal → unlock next stage → **Next level**.  
- **No XP/coins economy.**

### Later

- Grade1+ content packs.  
- Optional Add to Vocabulary.  
- Sound / haptics / reduce motion.

**Out of scope:** shop, multiplayer, server sync, replacing Essential, XP/coins.

---

## 15. Success metrics

| Metric | Target |
|--------|--------|
| Start of fun | User completes first baby round in &lt; 3 minutes |
| Growth moment | ≥50% of users who master 10 baby words see level-up to toddler |
| Parallel systems | Essential still works with zero regressions |
| Growth clarity | User understands stage clear unlocks the next age |
| Return | Player re-opens Life Path after a session |

---

## 16. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Confused with Essential | Separate name (“Life Path”), separate entry point, different UI chrome |
| Grind to clear stage | Mastery is 1 correct; full-stage session + re-queue only on misses |
| Duplicate words vs Essential / library | Shared `front` uniqueness only at flashcard insert time; game list is independent |
| Table name alone insufficient | Profile + list tables required; rewards table is legacy only |
| Adult learners dislike “baby” | Subtitle “Stage 1 · First words”; avatar optional; fantasy is growth, not infantilization |
| Scope creep (shop, XP, grades 1–6) | Hard cut: stage mastery + ceremony only; no economy |

---

## 17. Decisions checklist (for implementation start)

- [x] Keep Essential Vocab frequency lists and UI  
- [x] New system, not a replace  
- [x] Primary progress table: `baby_to_child_list`  
- [x] Supporting: `baby_to_child_profile` (rewards table legacy/inert)  
- [x] Flashcard **game** play loop (not triage-only)  
- [x] Hard stage unlock; notify on grow-up  
- [x] **No** XP/coins economy (removed from product)  
- [x] Mastery: 1 correct = mastered  
- [ ] Auto-add to Vocabulary vs manual only (recommend **manual**)  
- [x] Content: baby + toddler + preschool shipped  

---

## 18. One-sentence technical summary

**Keep Essential as the frequency triage funnel; build a separate Life Path flashcard game whose per-word state lives in `baby_to_child_list`, whose player growth lives in `baby_to_child_profile`, and whose stage-clear ceremony unlocks the next life stage — starting as baby, through toddler and preschool, without XP or coins.**
