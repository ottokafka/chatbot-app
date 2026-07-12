# Life Path

# Plan: Baby → Child Flashcard Game (Life Path)

| Field | Value |
|-------|--------|
| **Status** | Implemented (v1: baby + toddler, play loop, rewards, level-up) |
| **Date** | 2026-07-12 |
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
│  Triage: Add / I know        │     │  Play: study cards, earn rewards │
│  → kind=vocab library        │     │  → grow stage + optional vocab   │
└──────────────────────────────┘     └──────────────────────────────────┘
```

**One-line pitch:**  
A life-path flashcard game where you start as a **baby**, clear baby words, get notified that you grew into a **toddler**, earn rewards, and keep aging through childhood stages — without touching the Essential frequency lists.

---

## 2. What this is (and is not)

### Is

- A **new game mode** with its own DB tables, catalog, ViewModel, and UI.
- A **flashcard game**: player studies words in the current life stage (flip / rate / advance).
- A **progression RPG-lite**: complete stage vocabulary → **grow up** (baby → toddler → …) with **celebration notify** + **rewards**.
- Optionally may **also** insert or link `kind = vocab` flashcards so words land in the library (see §6).

### Is not

- A redesign of FSRS core or `FlashcardKind`.
- A replacement for Essential Vocab.
- A third permanent “deck kind” in the library/gym model (game has its own run state; library stays vocab/example).
- Soft triage-only (Essential stays the triage product; this is **play + grow**).

---

## 3. Player fantasy & loop

```
Start life as Baby
    → Study baby vocabulary (flashcards)
    → Earn XP / coins / streak rewards
    → Clear stage requirement
    → NOTIFY: "You grew up! You're a Toddler now."
    → Unlock toddler vocabulary
    → Repeat through Pre-K → Grade 1 → … (content-capped per release)
```

### Core loop (session)

1. Open **Life Path** game.  
2. See avatar age/stage + progress bar for current stage.  
3. Play a **round** of flashcards from the **current stage only**.  
4. On each correct / good review: XP, coins, stage progress.  
5. On stage clear: **level-up ceremony** (notification + reward grant).  
6. Next session: new stage’s word pool.

### Secondary loop (optional library bridge)

After a word is “mastered” in the game (or on first success), offer **Add to Vocabulary** so it appears in the normal library — **does not** replace game progress.

---

## 4. Life stages (content ladder)

Shared stage IDs for EN + ZH catalogs. v1 content can ship only early stages.

| Stage ID | Display (EN) | Display (ZH) | Age fantasy | Curated words (target) | v1 ship? |
|----------|--------------|--------------|-------------|------------------------|----------|
| `baby` | Baby | 婴儿 | First words | ~50 | **Yes** |
| `toddler` | Toddler | 幼儿 | First 100–150 | ~150 | **Yes** |
| `preschool` | Preschool | 学前 | Daily life | ~250 | Yes if ready |
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
│  baby_to_child_profile     (player: stage, XP, …)    │
│  baby_to_child_list        (per-word game progress)  │
│  baby_to_child_rewards     (ledger of grants)        │
│  flashcards (optional link when user adds to vocab)  │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌─ LifePathViewModel + UI ─────────────────────────────┐
│  Stage map · Play session · Level-up modal · Shop?   │
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

### 6.3 `baby_to_child_rewards` (reward ledger)

```sql
CREATE TABLE IF NOT EXISTS baby_to_child_rewards (
    id              TEXT PRIMARY KEY,
    language        TEXT NOT NULL,
    reward_type     TEXT NOT NULL,  -- see §8
    amount          INTEGER NOT NULL DEFAULT 0,
    reason          TEXT NOT NULL,  -- 'review_correct' | 'stage_clear' | 'streak' | 'first_session' | ...
    stage_id        TEXT,
    entry_id        TEXT,
    meta_json       TEXT,           -- optional payload (title, icon key)
    created_at      REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_btc_rewards_lang_created
  ON baby_to_child_rewards(language, created_at);
```

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

UI is **game-styled** (big type, stage chrome, XP toast) — separate from Essential list sheet and from Library review chrome (can share low-level flip components later).

### 7.3 Rating (v1 simple)

| Action | Effect on word | XP | Coins |
|--------|----------------|----|-------|
| **Got it** (correct) | `correct_count++`; if `correct_count >= 2` and last was correct → `mastered` | +10 | +1 |
| **Again** (wrong) | `wrong_count++`; status → `learning`; reset mastery streak | +2 | 0 |
| **Skip** | no mastery change; slight delay `due_at` | 0 | 0 |

**Mastery threshold (shipped):** **1 correct** = mastered (first “Got it” clears the word).

### 7.4 Stage clear detection

After each review upsert:

```
if count(status='mastered' WHERE stage=current) == count(entries in stage catalog)
   AND current stage not already in stages_cleared
→ trigger progression (§9)
```

---

## 8. Reward system

### 8.1 Currencies

| Currency | Use |
|----------|-----|
| **XP** | Permanent growth meter; unlocks titles / avatar frames at thresholds |
| **Coins** | Spendable (v1: cosmetic only or bank for future shop) |

### 8.2 Earn table (v1)

| Event | XP | Coins | Notes |
|-------|----|-------|--------|
| Correct review | 10 | 1 | Base |
| First-time correct on a word | +5 bonus XP | — | `correct_count` went 0→1 |
| Word mastered | +25 | +5 | Once per `entry_id` |
| Stage cleared (grow up) | +100 | +50 | Plus ceremony |
| Daily first session | +15 | +5 | Per calendar day |
| Streak day 3 / 7 / 14 | +20 / +50 / +100 | +10 / +25 / +50 | Streak milestones |
| Perfect round (all correct) | +15 | +5 | Per session |

All grants append a row to `baby_to_child_rewards` and update `baby_to_child_profile.xp` / `coins` / `lifetime_xp`.

### 8.3 Spend / unlockables (v1 minimal)

| Unlock | Cost / condition |
|--------|------------------|
| Title: “First Words” | Clear `baby` |
| Title: “Toddler Talk” | Clear `toddler` |
| Avatar frame: Baby | Default |
| Avatar frame: Toddler | Clear `baby` (auto) |
| Avatar frame: Kid | Clear `preschool` |
| Coin sink (optional) | “Sticker pack” cosmetic — defer if no art |

v1 can ship **grants only** (no shop UI) and still feel rewarding via ceremony + XP bar + titles.

### 8.4 Anti-abuse

- Max XP per calendar day soft cap (e.g. 500) to block mindless farming.  
- Stage clear reward granted once (`stages_cleared_json` / reward reason unique check).

---

## 9. Progression notify (“you grew up”)

### 9.1 When

On stage clear, **before** switching `current_stage_id`:

1. Persist reward ledger + profile XP/coins.  
2. Append stage to `stages_cleared_json`.  
3. Set `pending_notify_json` to a structured payload (survive process death).  
4. Unlock next stage rows in `baby_to_child_list` (`locked` → `available`).  
5. Set `current_stage_id` / `highest_stage_id` to next stage.  
6. Present **Level-Up modal** (blocking, celebratory).

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
  },
  "rewards": [
    { "type": "xp", "amount": 100 },
    { "type": "coins", "amount": 50 },
    { "type": "title", "id": "first_words" },
    { "type": "frame", "id": "toddler" }
  ]
}
```

### 9.3 Surfaces

| Surface | Behavior |
|---------|----------|
| **In-app modal** | Primary — confetti / stage art / claim button |
| **Toast** | Secondary for small XP ticks during play |
| **System local notification** | Optional v1.1 if app backgrounded mid-clear |
| **Profile badge** | Persistent “Toddler” on Life Path home |

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
      "targetCount": 50,
      "clearReward": { "xp": 100, "coins": 50 }
    },
    {
      "id": "toddler",
      "order": 1,
      "title": { "en": "Toddler", "zh": "幼儿" },
      "subtitle": { "en": "Everyday talk", "zh": "日常用语" },
      "targetCount": 150,
      "clearReward": { "xp": 150, "coins": 75 }
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
| `LifePathModels` | Stage, Entry, RewardType, NotifyPayload |
| `LifePathViewModel` | Profile, list rows, session, awards, level-up |
| `LifePathHomeView` | Stage map, XP/coins, Play CTA |
| `LifePathPlayView` | Flashcard round UI |
| `LifePathLevelUpView` | Blocking progression ceremony |
| `DatabaseManager` | CRUD for three new tables |
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
- Progress: `mastered / total` for stage + XP bar  
- Coins / streak  
- Stage rail: Baby ✓ · Toddler 🔒 · …  
- Primary: **Play**  
- Secondary: Word list (current stage), Rewards history  

### B. Play session

- Card stack / single card flip  
- Got it / Again  
- Floating +XP toasts  
- End-of-round summary (correct count, coins)  

### C. Level-up (notify)

- Full-screen: “You grew up!”  
- From Baby art → Toddler art  
- Reward chips  
- **Claim & continue** → Home with Toddler unlocked  

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

Both systems can feed the library; only Life Path has **stages, XP, coins, growth notify**.

---

## 14. Implementation plan (phased)

### PR1 — Schema + catalog skeleton

- Create `baby_to_child_list`, `baby_to_child_profile`, `baby_to_child_rewards`.  
- Ship `life_path_*` JSON with **baby** stage only (~50 EN + 50 ZH).  
- `LifePathCatalog` load + unit tests.  
- Seed list rows on first open.

### PR2 — Play loop

- Home + Play session (Got it / Again).  
- Update list status, XP/coins, reward ledger.  
- Mastery + stage progress bar.

### PR3 — Progression + notify + rewards ceremony

- Stage clear → unlock toddler (catalog can still be small stub).  
- Level-up modal + `pending_notify_json`.  
- Titles / frames grant.

### PR4 — Toddler content + polish

- Full toddler lists.  
- Streak + daily bonus.  
- Optional Add to Vocabulary.  
- Sound / haptics / reduce motion.

### PR5 — Later stages

- Preschool, grade1, … content packs + balance pass on XP.

**Out of scope for first ship:** shop UI, multiplayer, server sync, replacing Essential.

---

## 15. Success metrics

| Metric | Target |
|--------|--------|
| Start of fun | User completes first baby round in &lt; 3 minutes |
| Growth moment | ≥50% of users who master 10 baby words see level-up to toddler |
| Parallel systems | Essential still works with zero regressions |
| Reward clarity | User can state coins/XP sources after one session |
| Retention proxy | Return next day streak ≥1 for engaged players |

---

## 16. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Confused with Essential | Separate name (“Life Path”), separate entry point, different UI chrome |
| Grind to clear stage | Mastery is 1 correct; full-stage session + re-queue only on misses |
| Duplicate words vs Essential / library | Shared `front` uniqueness only at flashcard insert time; game list is independent |
| Table name alone insufficient | Profile + rewards tables required; document all three as the “Life Path DB pack” |
| Adult learners dislike “baby” | Subtitle “Stage 1 · First words”; avatar optional; fantasy is growth, not infantilization |
| Scope creep (shop, grades 1–6) | Hard cut: baby + toddler + ceremony for v1 |

---

## 17. Decisions checklist (for implementation start)

- [x] Keep Essential Vocab frequency lists and UI  
- [x] New system, not a replace  
- [x] Primary progress table: `baby_to_child_list`  
- [x] Supporting: `baby_to_child_profile`, `baby_to_child_rewards`  
- [x] Flashcard **game** play loop (not triage-only)  
- [x] Hard stage unlock; notify on grow-up  
- [x] Reward system: XP + coins + stage titles/frames  
- [ ] Mastery algorithm final numbers (lock in PR2)  
- [ ] Auto-add to Vocabulary vs manual only (recommend **manual** v1)  
- [ ] v1 content: baby only vs baby+toddler (recommend **baby full + toddler full** if possible)

---

## 18. One-sentence technical summary

**Keep Essential as the frequency triage funnel; build a separate Life Path flashcard game whose per-word state lives in `baby_to_child_list`, whose player growth lives in `baby_to_child_profile`, and whose XP/coins/stage-clear ceremonies live in `baby_to_child_rewards` — starting as baby, notifying the player as they grow into toddler and beyond.**
