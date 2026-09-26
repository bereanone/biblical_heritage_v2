# Bible Memory v2 — Audit and Design Report

Status: AUDIT AND DESIGN ONLY (2026-09-20). No code, schema, or installed app was changed by this work.
Section 2 (geofence app) is **pending**: its location has not been supplied yet.

Locked decisions from the owner (all honored below): live-linked `#tag` sets; Memory Item vs Memory
Membership split; one schedule per unique item; configurable workload; recall-before-replay; the
memory system comes looking for the user; Kokoro only (no AVSpeechSynthesizer); study the geofence
app first; FSRS is the lead candidate; extend the existing Bible Memory, no parallel stacks.

---------------------------------------------------------------------------------------------------

## Headline findings (read these first)

1. **The user's iPhone runs iOS 18.7.3** (`devicectl`, iPhone 15 Plus). **AlarmKit needs iOS 26**, so it
   cannot be tested on the actual device today, and the app's deployment target is iOS 15.0. The smallest
   viable "memory alarm" is therefore **actionable local notifications with pre-rendered Kokoro audio as
   the notification sound**, handled natively in Swift. AlarmKit becomes an optional later layer.
2. **Kokoro cannot run when the app is not running.** It is a 325 MB ONNX model in an in-process Dart
   isolate (`KokoroEngineHost`). It cannot run in a notification extension (tight memory cap; extensions
   also do not apply to local notifications) and cannot be started reliably from a background wake.
   The design works around this by **pre-rendering while the app is active** and letting iOS play the
   files. Only Kokoro ever makes the audio.
3. **The existing Bible Memory is not a memory-retrieval system yet.** Practice stage 1 shows the entire
   verse first, then hides every 5th/4th/3rd/2nd word. Scheduling is a fixed 1/7/30/90/180/365-day
   ladder. "Start Due Review" opens only the first due item. Tag import is a one-time **copy**, not a
   link. There is no notification code of any kind in the repo.
4. **Existing user memory data is tiny** (Mac v2 DB: 0 rows; Mac legacy DBs: 1 verse, 1 review; iPhone:
   3 verses in `#TempTags`, 0 reviews). Migration risk is low, but it must still be lossless and
   backed up first, because other devices/installs (App Store users) may hold more.
5. **Two real bugs found in existing code** (to fix during the rebuild, not now):
   - `upsertPassage` overwrites `group_name` with `null` when a verse is re-added from the reader
     (`bible_memory_repository.dart:192-207`; `_addRangeToMemory` passes no group).
   - Tag import reads `hash_tags` directly **without** the `trashed_at_utc` filter that the tag
     system uses everywhere else, so trashed entries can be imported (`bible_memory_support.dart:117-121,148-154`).

---------------------------------------------------------------------------------------------------

## 1. What exists now

### 1.1 Files and sizes (lines)

| Area | File | Lines | Notes |
|---|---|---|---|
| Data | `lib/features/reader/data/bible_memory_repository.dart` | 257 | `MemoryVerse` model + `BibleMemoryRepository` |
| UI | `lib/features/reader/presentation/bible_memory_screen.dart` | 503 | list, group dropdown, import/export, "Start Due Review" |
| UI | `.../bible_memory_practice_screen.dart` | 373 | first-letter typing drill |
| Support | `.../bible_memory_support.dart` | 506 | tag import, external list import/export, help dialog, Bible text lookup |
| Entry points | `viewer_range_actions_sheet.dart` (249), `bible_explorer_range_actions.dart` (622, calls `upsertPassage`), `viewer_mode_popup.dart`, `bible_explorer_navigation.dart` | | "Add to Memory" from the Bible reader; menu → Bible Memory |
| eLibrary | `library_book_reader_selection_menu.dart:192` | | "Add to Memory" button exists but is **disabled, no handler** (stub) |
| Schema | `lib/core/database/user_v2_schema.dart` | 1,256 | `memory_verses` created at line ~194 |
| Legacy import | `lib/core/bootstrap/startup_coordinator.dart` | | lists `memory_verses` as a "preserved unmapped" legacy table (lines ~750, ~929) |
| Kokoro | `kokoro_engine_host.dart` (89), `kokoro_mac_test_narrator.dart` (355), `kokoro_speech_worker.dart` (117), `narration_pronunciation.dart` (85), `bible_pronunciation_map.dart` (87) | | pronunciation assets in `assets/audio/pronunciation/` |
| Tag playback | `presentation/tag_playback/*` | ~2,100 across 11 files | planner, controller, Kokoro adapters, media binding |
| Audio session | `lib/core/audio/narration_media_session.dart` (318), `ios/Runner/NarrationMediaBridge.swift` (204) | | lock-screen/Now Playing, `UIBackgroundModes: audio` |
| Tags | `data/tags/unified_tag_read_adapter.dart` (1,239), `legacy_tag_adapter.dart` (604), `tag_quick_apply_helper.dart` (**5,252**), `tag_dollar_merge_service.dart` (1,096) | | monoliths; project rule: do not grow them |

No dependency for notifications, background tasks, alarms, Watch, or FSRS exists in `pubspec.yaml`
(only `audioplayers`, `sherpa_onnx`, `sqflite`, etc.). iOS has no entitlements file, no Watch target.

### 1.2 Database schema (`memory_verses`, in `user.db`)

```
id INTEGER PK AUTOINCREMENT, verse_ref TEXT NOT NULL UNIQUE, book_number, book_name, chapter, verse,
end_chapter, end_verse (DEFAULT 0 on legacy rows), verse_text (snapshot), group_name TEXT (free string),
review_step INT, next_due_at INT(ms), last_result TEXT('pass'|'retry'), total_reviews, total_misses,
created_at, updated_at
```

Weaknesses: identity is a **display string** (`"Romans 6:22"`, built from `book_name`); no per-review
history (only counters); no sync columns / soft delete (every other v2 table has `device_id`,
`revision`, `deleted_at`, `change_id`, ...); hard `DELETE`; text is a stale snapshot; `group_name` is
a loose string that may or may not match a real tag.

`user.db` uses `version: 1` with **idempotent `CREATE TABLE IF NOT EXISTS` + `ALTER TABLE ADD COLUMN`
in `UserV2Schema.ensure()`** — there is no `onUpgrade` chain. New tables must follow that pattern.

### 1.3 Current scheduling algorithm

Fixed ladder `[1, 7, 30, 90, 180, 365]` days. Pass → `review_step + 1` (capped) and next due = ladder
interval. Fail → step **unchanged**, due tomorrow (no lapse step-down, so a forgotten yearly verse
keeps its step). Pass = `totalStrikes <= 3` across the whole drill. No difficulty, no overdue
handling, no retention target, no workload limit, no ordering beyond `next_due_at ASC`.

### 1.4 Current recall/testing behavior

- Stage 1 shows the **full verse** (recognition, not recall). Stages 2-6 mask every 5th/4th/3rd/2nd/every
  word; the user types the **first letter** of each hidden word (3 strikes per word).
- Useful as a *learning* aid (graduated cueing). Not usable for a notification/audio review, not
  self-graded, no silence-to-retrieve step, and it contradicts recall-before-replay if used as the
  review. Keep it as the "Learn" mode; add a separate "Recite" review.
- "Start Due Review" opens only `due.first`; there is no session/queue.

### 1.5 Tag/group implementation

- Two parallel tag stores, read together by `UnifiedTagReadAdapter`:
  - **Legacy**: `hash_tags`/`dollar_tags`/`at_tags`, integer ids, tag identity = the **name string**
    (`#KeyTexts`); `renameTag` rewrites the `tag` column (`tag_quick_apply_helper.dart:810`).
  - **Unified**: `tag_groups` / `tag_items` (UUID ids), verse ranges with `verse_start/verse_end`.
- Chain ids: `legacy:hash:<url-encoded #name>` and `unified:<group uuid>`.
- Entry kinds inside a tag (`tagEntryTypeOf`): scripture, eLibrary passage (`note_format_json.kind =
  elibrary_note`), or note. Trashed rows carry `trashed_at_utc` / `trashed_at`.
- **Memory ↔ tag today is a snapshot**: `importTagGroup` copies each `hash_tags` verse into
  `memory_verses` with `group_name = '#Tag'` once. Later additions/removals never propagate. It ignores
  `dollar_tags`, `tag_items` (unified), ranges, eLibrary passages, notes, and trash state.
- Live data check: Mac v2 DB has 145 `hash_tags` rows in one tag and 2 groups / 38 unified items; the
  iPhone has 4 tag rows and 1 group. So the tag system is genuinely dual-backend.

### 1.6 TTS / playback reuse opportunities (all reusable as-is)

- `KokoroEngineHost` (ref-counted single engine) + `KokoroMacTestNarrator.renderClip()` (text →
  pronunciation map, KJV block-id patches, user corrections, lexicon → WAV file). This *is* the
  "Kokoro → KJV pronunciation layer".
- `TagClipRenderer` / `TagClipPlayer` ports and `AudioplayersTagClipPlayer` (two alternating players).
- `spokenBibleReference()` — "First John 1, verses 8 to 9" — reference speech.
- `NarrationMediaSession` + `NarrationMediaBridge.swift` — lock screen, interruptions, route loss.
- `TagPlaybackPlanner` — already turns scripture/eLibrary/note entries into speakable clips.
- WAV format: 24 kHz, 16-bit mono = 48,000 bytes/second (per `KokoroTagClipRenderer`).
- **Unknown**: iPhone synthesis speed (real-time factor) has never been measured (per project notes).

### 1.7 Notification / background infrastructure

None for scheduling. `Info.plist` has `UIBackgroundModes: [audio]` only (no `fetch`,
`processing`, no `BGTaskSchedulerPermittedIdentifiers`). `AppDelegate.swift` registers three bridges
(library root, tilt motion, narration media) via the implicit-engine pattern; no
`UNUserNotificationCenter` delegate. No entitlements file, no Watch target.
Deployment target iOS 15.0; Flutter 3.41.4; Xcode 27.

### 1.8 Incomplete / duplicated / fragile / stubbed

| Item | Detail |
|---|---|
| Stub | eLibrary "Add to Memory" is a disabled button. |
| Bug | `upsertPassage` update path wipes `group_name` (see headline #5). |
| Bug | Tag import ignores trash. |
| Fragile | Identity by display string; renaming a book/format breaks dedupe. |
| Fragile | Live tag link cannot rely on the tag *name*: rename rewrites it. |
| Missing | No history, no queue, no limits, no notifications, no sync columns. |
| Stale | Help text ("read it carefully, then review it repeatedly") describes passive repetition. |
| Legacy | `memory_verses` rows from an older device's DB are parked in `legacy_unmapped_import` rather than imported; none found in current DBs. |
| Rule | Do not add lines to `tag_quick_apply_helper.dart` (5,252) and similar; wire through small files. |

---------------------------------------------------------------------------------------------------

## 2. What the geofence app teaches us

**PENDING — location not yet supplied.** A folder named `GeoMuteLab` exists in `~/Development`, but it
has not been opened; the owner should confirm which project it is before it is inspected read-only.
Questions to answer once inspected: how notification categories/actions are registered; whether
responses are handled in native code or Dart; what runs when the UI is not active; what the Watch
actually receives; persistence used between background handler and app; deployment target; and
which pieces are still the right approach on iOS 18.7 / the current toolchain. Sections 3-7 below are
written to stay valid whichever way that comes out, but **the iOS architecture (section 4.3) is not final until
this review is done.**

---------------------------------------------------------------------------------------------------

## 3. What Apple actually permits

Legend: **G** = GUARANTEED BY iOS · **P** = POSSIBLE BUT NOT GUARANTEED · **N** = NOT PERMITTED / NOT RELIABLE.
Items marked ⚠ come from documentation/secondary sources and **must be proven on the physical iPhone
before the architecture depends on them** (Phase 0).

| Mechanism | Label | Reality for StudyBible |
|---|---|---|
| Local notification fires at a calendar time with the app terminated | **G** | Delivered by the OS (subject to the user's notification permission, Focus, Scheduled Summary). Pending requests persist across reboot. |
| Max pending local notifications | **G** (constraint) | **64**; the soonest 64 are kept. Needs a rolling window topped up whenever the app runs. A repeating calendar trigger counts as one. |
| Notification content is fixed at scheduling time | **G** (constraint) | Local notifications have no Notification Service Extension hook. Far-future slots must be generic ("Memory time"); only near-term slots can name a specific verse. |
| Custom notification sound (≤ 30 s, PCM/IMA4/µ-law/A-law in `.wav/.aiff/.caf`, in bundle or `Library/Sounds`) | **G** | A pre-rendered **Kokoro** clip ("Romans six, verse twenty-two") can be the alert sound itself, with the app terminated. Follows the ringer/Silent switch (not the media volume). Kokoro's 24 kHz 16-bit WAV is an allowed format. |
| Notification action taps (`UNNotificationAction`) from Lock Screen / banner | **G** | Works without unlocking if the action does not require authentication or foreground. |
| Action handled **in the background** when the app is not running | **P** ⚠ | iOS launches the app briefly to call `didReceive response`. Reliability after the user force-quits the app is disputed; verify. Handler must be tiny native Swift and finish in seconds. |
| Handler posts a follow-up local notification (e.g. the answer, with grade buttons) | **P** ⚠ | Standard pattern; depends on the background launch above. |
| More than a few actions per notification | **P** ⚠ | Compact banner shows fewer than the expanded view; exact counts vary by OS/UI. Design uses **≤ 4 actions per notification** (a two-step flow) to avoid the question. |
| Time Sensitive interruption level | **P** | Needs the `com.apple.developer.usernotifications.time-sensitive` entitlement/App ID capability (none exists now). Breaks through Focus only if the user has not disabled Time Sensitive for the app. |
| Critical alerts | **N** | Requires special Apple approval; not appropriate. |
| Apple Watch: iPhone notification mirrored to a paired Watch, with actions | **P** ⚠ | Watch shows the text and the action buttons; taps are delivered to the iPhone's notification delegate, no watchOS app required. Mirroring only occurs when the iPhone is locked/idle and the Watch is worn/unlocked. Custom Kokoro sound would not play on the Watch (haptic only). Paired Watch here: Watch6,17. |
| Kokoro/audio playback **from the Watch** | **N** | Needs a watchOS app, which cannot host Kokoro. Answer is delivered on the Watch as text. |
| AlarmKit (`AlarmManager`) | **P — iOS 26+ only** | Bypasses Silent and Focus, shows on Lock Screen/Dynamic Island/Watch, secondary button can run a `LiveActivityIntent`, needs `NSAlarmKitUsageDescription` and a widget extension with Live Activity UI. Custom sound is limited (<30 s, reports of it playing once). **Not available on this iPhone (iOS 18.7.3)** and not on the iOS 15 deployment target without availability gating. |
| App Intents / Shortcuts "Time of Day" automation → run an intent | **P** ⚠ | User must create the automation manually (apps cannot install them). An audio-playback intent may start playback from a background launch; must be spiked. Optional later layer. |
| Background audio *continuing* when already playing (screen locked) | **G** | Already implemented (`UIBackgroundModes: audio`, `.playback` session). |
| **Starting** Kokoro synthesis/speech from a terminated app | **N** | No supported way to begin engine + audio from nothing. Force-quit apps are not relaunched by background refresh. |
| Running Kokoro inside a notification action handler | **N** | Cold isolate boot of a 325 MB model within a seconds-long, memory-limited background window is not reliable. |
| Playing an already-rendered file natively (`AVAudioPlayer`) after a background action | **P** ⚠ | Needs the audio background mode + active session; works in many cases, not guaranteed. Prefer "alert sound is the audio" (G) over this. |
| Background App Refresh / `BGTaskScheduler` to top up the 64 slots | **P** | Opportunistic; iOS decides when. Never the only mechanism. |
| Focus / Do Not Disturb | **G** (constraint) | Ordinary notifications are silenced by Focus unless Time Sensitive is granted/allowed. |
| Headphones connected | **P** ⚠ | Alert sounds usually route to connected headphones; verify. In-app playback already pauses on route loss. |
| Restart | **G** | Scheduled notifications survive reboot. Audio/session state does not. |
| macOS | differs | Same `UNUserNotificationCenter` API; no AlarmKit, no `BGTaskScheduler`, no Watch. Mac app can run Kokoro live while open. Treat Mac as **in-app sessions + optional plain notifications**; the iPhone is the "comes looking for me" device. |

**Consequence for the spoken part.** A spoken prompt is achievable with a pre-rendered sound. A spoken
**answer** is achievable the same way when the answer clip is ≤ 30 s (most verses; long ranges fall back
to on-screen text plus "Hear it" inside the app). Neither uses AVSpeechSynthesizer.

---------------------------------------------------------------------------------------------------

## 4. Proposed architecture (smallest that works)

### 4.1 Domain model

```
memory_item        one row per unique thing being memorized. Owns FSRS state. Never deleted by tag changes.
memory_membership  "why is this item included": manual | tag | named_group. Many per item.
memory_review_log  append-only: every grade ever given (source of truth; state is derivable from it).
memory_settings    workload + retention + windows + FSRS parameters (one row / keyed values).
```

**Item is active ⇔ at least one membership is active.** Removing a tag entry only ends that
membership (`ended_at`). The item, its FSRS state, and its log are never touched. Re-adding later
re-activates (or creates a new membership row for) the *same* item, so learning resumes.
Content pointer (not a copy) is resolved at render time: verse text from `bible_base.db`, note text from
its source, eLibrary passage from its stored snapshot; a `content_hash` detects edits.

### 4.2 Scheduler (platform-independent Dart, no Flutter imports)

- New package-style module `lib/features/memory/scheduler/` (small files, 300-700 lines each), behind an
  interface `MemoryScheduler { review(state, rating, at) → state; retrievability(state, at); }`.
  FSRS is the implementation; SM-2 could be dropped in behind the same interface.
- **Queue builder** (pure function): inputs = items, settings, `now`; outputs = ordered session with
  `due`, `overdue`, `new`, `deferred` classified separately (details in section 4.4).
- Keep the existing `BibleMemoryRepository` **public API** (`upsertVerse/upsertPassage/loadAll/...`) as a
  facade over the new tables, so `bible_explorer_range_actions.dart` and other callers need no edits.

### 4.3 iOS delivery layer (provisional until the geofence review)

```
Dart (app active)                         Swift (native, tiny)                     iOS
─────────────────                         ────────────────────                     ───
Scheduler + queue builder ─plan JSON──►   MemoryNotificationBridge
Kokoro pre-render (prompt/answer WAVs) ─►   • registers UNNotificationCategories
   into Library/Sounds + audio cache        • schedules rolling ≤56 requests ─────► fires at window, terminated OK
                                            • didReceive(action):                    lock screen / Watch mirror
◄── drains journal at launch/resume ──      appends event to journal file,
    replays into FSRS (idempotent)          posts next notification (answer / next item)
```

- **Single source of truth stays in Dart/SQLite.** Swift never writes the database and never computes
  FSRS. It appends `{event_id, item_key, rating, timestamp}` lines to a small **journal file**; Dart
  replays them on next launch/resume using the *tap time*, deduplicating by `event_id`.
- **Plan snapshot** (`memory_session_plan.json`): the ordered items for the next window(s), with answer
  text and sound file names, so the Swift handler can post "answer" and "next item" without Dart.
- **Rolling notification schedule**: near-term slots (next ~24-48 h) name specific items; far slots are
  generic "Memory time — N due"; a final "tail" notification says to open the app to refill. Refill
  runs on app open/resume, after every notification action, and opportunistically via BG refresh.
- **Two-step flow (≤ 4 actions each):**
  1. *Prompt* — title **"Romans 6:22"**, body "Try to recite this verse." Sound = pre-rendered Kokoro
     reference. Actions: **Show Answer**, **Snooze 10 min**, **Skip for now**.
  2. *Answer* — posted by the handler when Show Answer is tapped. Body = verse text; sound = pre-rendered
     Kokoro reading (≤ 30 s). Actions: **Again · Hard · Good · Easy**.
  Grade tap → journal → (if the session cap allows) schedule the next prompt ~30 s later.
- **Foreground path** (always guaranteed): tapping the notification body opens the in-app Recite
  screen, which uses the live `KokoroEngineHost` as the tag playback does today.
- **Pre-render + cache policy:** render only what will be needed for the next ~48 h of prompts plus
  answers ≤ 30 s. Key = hash(content, voice, speed, pronunciation-map version). Size-capped LRU
  (default 100 MB, configurable), purge on content/pronunciation change, delete notification-sound
  copies once the notification is delivered or cancelled. Reference prompt ≈ 2-3 s ≈ 100-150 KB;
  a 30-word verse ≈ 10 s ≈ 480 KB as 24 kHz WAV. A 200-verse tag rendered in full would be ~100 MB, hence
  the "next 48 h only" rule. Rendering speed on iPhone is **unmeasured** (Phase 0).

### 4.4 Workload and deferral (all values configurable; none hard-coded)

| Setting | Proposed default | Range |
|---|---|---|
| New items introduced per day | 3 | 0-20 |
| Max reviews per day (due + overdue, excludes same-day learning repeats) | 30 | 0 (=unlimited) - 200 |
| Max session length | 12 items or 10 minutes | both adjustable |
| Learning-load guard: stop introducing new items while ≥ N items are still "young" | 10 | 0 (off) - 50 |
| Desired retention | 0.90 | 0.80-0.95 |
| Review windows | user-defined (see decisions) | 0-6 per day |

**Queue order:** (1) learning/relearning due now → (2) overdue, lowest retrievability first → (3) due
today → (4) new items up to the new-per-day budget. Classification stays visible:
*due*, *overdue*, *new*, *deferred today*.

**How deferral affects FSRS (and how to avoid corrupting it):**
- A card that is not shown is **not modified**. Deferral only changes what the session *presents*.
  Its true `due` stays; nothing is "postponed" or rescheduled behind its back.
- When it is finally reviewed, FSRS uses the *actual elapsed time* since `last_review`. A late "Good"
  correctly yields a larger stability gain than an on-time one; a late "Again" is a legitimate lapse.
  The scheduler is designed for this; no compensation is needed.
- Never record a skipped/snoozed/ignored notification as a review or a lapse.
- A large tag creates items in state **New** with an intro order (tag order); they trickle in at the
  new-per-day rate, so turning on a 200-verse tag never produces 200 reviews.
- Persistent backlog (overdue > ~2× the daily cap for a week) → **suggest** raising the cap, lowering
  retention, or pausing a tag. Never auto-reschedule.

### 4.5 Canonical identity / deduplication key (one item ↔ one FSRS state)

`item_key` is a deterministic string; `UNIQUE(item_key)`. Membership rows point at items by id.

| Kind | `item_key` | Ambiguity / notes |
|---|---|---|
| Bible verse | `bible:<translation>:<book_number>:<ch>:<v>-<ch>:<v>` (single verse = span of length 1) | Use `book_number`, never the book name string. Include translation now (KJV) so a future translation is not merged into it. |
| Verse range | same span key, e.g. `bible:kjv:45:6:20-6:23` | **Overlap is the hard case**: Romans 6:22 vs Romans 6:20-23. Recommended v1: **exact-span identity** — different spans are different items (they are different recitation tasks). Overlap is *detected and shown*, never silently merged, and never shares FSRS state. Later optional refinement: when a containing range is graded Good, offer to skip its child verses that session (no state change). |
| Note | `note:<notes.id UUID>` or `tagnote:<tag row id>` | Text is editable. Keep history on edit; store `content_hash` and flag "text changed" so the user can choose to keep or reset. |
| eLibrary passage | `elib:<stable work id>:<paragraph ordinal>:<sha1(normalized selected text)[:12]>` | Depends on `library_item_identity.dart`, which has uncommitted changes; the Pioneer import refactor is active, so block ids are not stable. Hash of the selected text is the anchor; memorize the stored snapshot. Confirm stable-id rules before Phase 2. |
| Word / phrase | `term:<lang>:<normalized term>` or `strongs:<G/H number>` | Answer = definition/gloss. |
| Question → Answer card | `qa:<uuid>` | User-authored, so identity is a UUID. Warn (don't merge) on near-duplicate question hashes. |

A tag entry is **not** an identity; the thing it points at is. Two tags containing Romans 6:22 yield
one item and two memberships.

### 4.6 Tag live-link details

- Membership row: `(item_id, source_type='tag', source_ref=<tag identity>, active, started_at, ended_at)`.
- `#tag` "memory on" = a **tag subscription** (`memory_tag_subscription`: tag identity, paused flag,
  included entry types, intro order). A **reconciler** diffs the subscribed tag's current entries
  against its memberships and opens/closes membership rows. It runs on Memory screen open, app start,
  and after tag edits.
- Trashed entries count as removed; restore-from-trash reactivates automatically. Removing a tag entry never touches the item's log.
- **Tag identity caveat:** legacy tags are keyed by name and `renameTag` rewrites it. Options: (a)
  subscribe by chain id and add a one-line "tag renamed" call in `renameTag` (that file is a 5,252-line
  monolith, so the owner must approve), or (b) detect a missing tag name, mark the subscription
  **orphaned** (never delete), and let the user re-link. Recommended: (b) first, (a) if approved.
- A pause is a subscription flag; it deactivates the memberships' *effect* for scheduling but keeps them,
  so resume is instant and nothing is lost.

### 4.7 FSRS — evaluation and choices

**Recommendation: FSRS-6, embedded locally, behind the `MemoryScheduler` interface.**

- **Package:** `fsrs` on pub.dev, **v2.0.1**, **MIT**, changelog "2.0.0: FSRS-6"; a port of py-fsrs
  from the `open-spaced-repetition` org; pure Dart, only depends on `meta`; all platforms; `toMap()`/`fromMap()`
  on cards and logs; supports custom 21-weight parameters, retention target, learning/relearning steps,
  max interval, optional fuzzing, and a retrievability function. Published ~15 months ago
  (unverified uploader; small package). **No optimizer.** ⚠ Verify the license file and that the JSON
  round-trip and retrievability match reference values in unit tests before adopting; consider vendoring
  it under `packages/` (the repo already vendors local packages) so behavior is pinned.
- **FSRS vs SM-2:** SM-2 is a fixed heuristic (ease factor, multiplicative interval); FSRS models
  stability/difficulty/retrievability, has a **target-retention knob** (this is exactly the workload
  dial), copes with overdue reviews, and FSRS-6 models same-day reviews. No strong technical reason
  to reject FSRS was found. Caveat: default weights come from flashcard populations; verse recitation may differ, hence the
  personalization path below.
- **State stored per item:** `state` (New/Learning/Review/Relearning), `step`, `stability`, `difficulty`,
  `due`, `last_review`, `reps`, `lapses`. Global: 21 weights, `desired_retention`, `learning_steps`,
  `relearning_steps`, `maximum_interval`, `enable_fuzzing`, parameter-set id (stamped on every log row).
- **Rating mapping (self-graded):** Again = could not recite / needed the answer; Hard = recited with major
  hesitation or errors; Good = recited with minor slips; Easy = effortless. The typed-letter drill may *suggest* a
  rating (0 strikes → Good/Easy, many → Again) but never applies it silently.
- **Initial defaults:** default 21 weights, retention 0.90, learning steps `[10m]`, relearning `[10m]`,
  max interval 365-730 days, fuzzing **deterministic** (seeded by item id + review count) so a log
  replay reproduces the same due dates.
- **Personalization:** Anki's FSRS guidance is on the order of **~1,000 reviews** before an optimized
  parameter set is reliably better than defaults. A single learner at ~30 reviews/day reaches that in
  roughly 5 weeks. Until then use defaults.
- **Where to optimize:** no Dart optimizer exists. Smallest path: keep the complete append-only
  `memory_review_log`, add an **export** and run the reference optimizer (Python `fsrs` optimizer or
  `fsrs-rs`) on the Mac, then paste the resulting weights into settings. On-device optimization
  (Rust via FFI) is a much larger later project and not recommended for v1.
- **Seeding from current data** (`review_step`, `next_due_at`, `last_result`, counters; no real history):
  with retention 0.90, FSRS interval ≈ stability, so `stability = ladder[step-1]` days for step ≥ 1;
  step 0 → state Learning/New. `difficulty` starts at the default and is nudged up by
  `total_misses / total_reviews`. `last_review = next_due_at − interval`. One **synthetic** log row with
  `source='legacy_seed'` records this and is **excluded from optimization**. Items keep their existing due date.

---------------------------------------------------------------------------------------------------

## 5. Proposed user experience

1. **Adding one verse.** Reader → select → *Add to Memory* (unchanged entry point). Creates (or finds)
   the item for that exact span plus a `manual` membership. Confirmation says "New — will start learning soon"
   or "Already in Memory (in #KeyTexts and 1 more) — your progress is kept."
2. **Memorizing a passage.** Select a range → *Add to Memory* creates one **range item** (recited as a unit).
   Optionally "Learn it in pieces" first, which is a learning aid using the existing drill, not extra scheduler items.
3. **Turning on memory for a `#tag`.** Tag screen (and Memory screen) → *Memory: Off/On*. On shows
   "40 verses — 3 new per day, first ones tomorrow," entry types included (scripture by default),
   and a Pause switch. Adding/removing entries in the tag later changes membership automatically.
4. **A brand-new item's first learning session.** Learn mode: read/hear it (Kokoro), then the existing
   graduated drill (hide 5th → 4th → 3rd → 2nd → every word). At the end the user grades the first recall;
   that becomes the item's first FSRS review. Repetition here is initial learning only; every later review
   is retrieval-first.
5. **A review arriving while StudyBible is closed.** At a review window a notification arrives with the
   Kokoro-spoken reference; title "Romans 6:22", body "Try to recite this verse." Silence is the retrieval.
6. **Responding from the Lock Screen.** Long-press → **Show Answer** (no unlock needed) → a second notification
   reads the verse in Kokoro's voice and shows the text with **Again / Hard / Good / Easy**; tapping one
   records the grade with its real timestamp. If iOS declines to run the background handler, tapping the
   notification opens the app to the Recite screen (guaranteed fallback).
7. **Responding from Apple Watch.** The mirrored notification appears on the wrist with the same buttons; the
   answer arrives as text (Watch cannot play Kokoro). Taps go to the iPhone's handler. Requires the
   iPhone locked/idle and the Watch worn.
8. **Grading recall.** In-app: prompt → optional silent countdown → reveal + Kokoro reads it → four grade
   buttons that show the *next interval* under each ("Good · 6 days"). The app never grades from speech.
9. **Missing a scheduled review.** Nothing is penalized and nothing is rescheduled. The item stays due (then
   "overdue"), climbs the queue by lowest retrievability, and shows in the next window. Ignored
   notifications trigger a gentle backoff (e.g. after 3 unanswered windows → once a day) so it never nags.
10. **Pausing a tag.** Pause keeps memberships, items, and history; nothing from that tag is scheduled
    while paused. Resume continues where it left off; overdue items re-enter gradually under the daily cap.
11. **Removing and later restoring an item.** Removing from a tag/manual list ends only that membership.
    History is kept. Re-adding shows "Welcome back — last reviewed 4 months ago, resuming at your
    previous strength," and it re-enters as a review (state and stability preserved), not as new.
12. **What's due and what's coming.** Memory screen "Today": due N · overdue N · new N · deferred N
    (with the daily budget), plus a forecast strip (next 7 days), per-item strength, and per-tag counts. The screen also
    shows the next scheduled window and whether notifications are on.

---------------------------------------------------------------------------------------------------

## 6. Database / migration plan

New tables (created in a new `memory_v2_schema.dart`, invoked with one line from
`UserV2Schema.ensure()`, matching the idempotent `IF NOT EXISTS` pattern; all with the standard sync
columns `device_id, revision, deleted_at, sync_status, last_synced_at, change_id`):

```sql
memory_item(
  id TEXT PRIMARY KEY,                -- uuid
  item_key TEXT NOT NULL UNIQUE,      -- canonical identity (section 4.5)
  kind TEXT NOT NULL,                 -- bible|note|elibrary|term|qa
  ref_json TEXT NOT NULL,             -- {book,ch,v,endCh,endV,translation} | {noteId} | ...
  content_hash TEXT, prompt_text TEXT, answer_snapshot TEXT,
  state TEXT, step INT, stability REAL, difficulty REAL, due_at INT, last_review_at INT,
  reps INT DEFAULT 0, lapses INT DEFAULT 0, intro_order INT,
  legacy_memory_verse_id INTEGER,     -- link back to memory_verses.id
  created_at, updated_at, + sync columns);

memory_membership(
  id TEXT PRIMARY KEY, item_id TEXT NOT NULL,
  source_type TEXT NOT NULL,          -- manual|tag|named_group
  source_ref TEXT,                    -- tag identity / group name
  active INT NOT NULL DEFAULT 1, started_at INT, ended_at INT,
  UNIQUE(item_id, source_type, source_ref), + sync columns);

memory_tag_subscription(
  id TEXT PRIMARY KEY, tag_identity TEXT NOT NULL UNIQUE, display_name TEXT,
  paused INT DEFAULT 0, entry_types TEXT, orphaned INT DEFAULT 0, created_at, + sync columns);

memory_review_log(                    -- append-only, source of truth
  id TEXT PRIMARY KEY, item_id TEXT NOT NULL, rating INT NOT NULL,
  reviewed_at INT NOT NULL, state_before TEXT, stability_before REAL, difficulty_before REAL,
  elapsed_days REAL, scheduled_days REAL, param_set_id TEXT,
  source TEXT,                        -- app|notification|watch|legacy_seed
  client_event_id TEXT UNIQUE,        -- idempotent replay from the notification journal
  + sync columns);

memory_settings(key TEXT PRIMARY KEY, value TEXT)   -- or reuse app_settings raw keys `memory.*`
```

**Migration (additive, reversible, verified):**
1. Copy `user.db` to `Backups/pre_memory_v2_<timestamp>/` using the app's existing backup pattern.
2. Create new tables. **`memory_verses` is never altered, renamed, or dropped.**
3. In one transaction, for each `memory_verses` row: build `item_key` from `book_number/chapter/verse/
   end_chapter/end_verse` (`end_* = 0` → same as start); create the item with seeded FSRS state (section 4.7)
   and `legacy_memory_verse_id`; add a synthetic `legacy_seed` log row.
4. Memberships from `group_name`: if the string matches an existing tag it becomes a **`named_group`**
   membership (static, exactly today's behavior), **not** a live tag link. The UI then offers "Link this group
   to `#Tag` (live)" per group, so nothing is silently added or removed. Null group → `manual`.
5. Verify inside the transaction: item count equals the number of distinct spans in `memory_verses`, every
   legacy id has exactly one item, and each item's `due_at` equals the legacy `next_due_at`. Any mismatch
   aborts the transaction and leaves the old table authoritative.
6. The facade repository reads the new tables; `memory_verses` remains as a frozen fallback for at least one
   release. Also consume any `legacy_unmapped_import` rows with `source_table='memory_verses'` if they appear.

Sync note: `Bible_App_Sync_Architecture.md` plans change logs across devices; today there is **no sync between
iPhone and Mac**, so their memory states are independent. Append-only log + derivable state
means two devices can later be merged by replaying the union of logs.

---------------------------------------------------------------------------------------------------

## 7. Phased implementation plan

Every phase installs with `flutter run --release -d 00008120-000E6C112632201E` (in-place upgrade;
**never `flutter install`**, never uninstall) and bumps the `pubspec.yaml` build number. New code
goes in new 300-700 line modules; no growth of the monolith tag files.

| Phase | Deliverable | Test on the iPhone |
|---|---|---|
| **0. Spike** (no StudyBible schema/UI change; separate scratch target or guided by the geofence app) | Notification prompt → action → follow-up notification with a bundled ≤30 s sound; measure Kokoro RTF on iPhone; test app-killed, locked, Focus, headphones, Watch mirroring | Yes: decides whether the whole delivery layer is viable |
| **1. Scheduler core** | FSRS-6 wrapper, identity keys, queue builder, limits, deterministic fuzz; unit tests incl. deferral/overdue/replay equivalence | `flutter test` (no device UI) |
| **2. Schema + migration + facade** | New tables, backup, seeding, verification; `BibleMemoryRepository` API preserved; group_name bug fixed | Yes: the 3 existing verses appear identically; due dates unchanged |
| **3. Recite review session** | Prompt → silence → reveal (Kokoro) → 4 grades with interval preview; replaces "Start Due Review" with a real queue; help text rewritten | Yes: full in-app cycle |
| **4. Tag live-link** | Subscription, reconciler, pause/resume, trash-aware, orphan handling; eLibrary "Add to Memory" wired | Yes: tag a verse → it appears; un-tag → history kept |
| **5. Workload + Today screen** | Settings UI, deferred/overdue/new counts, forecast | Yes |
| **6. Notifications** | Swift bridge, windows, rolling 64-slot schedule, journal + replay, two-step action flow, backoff | Yes: closed/locked; then Watch |
| **7. Pre-rendered audio** | Prompt/answer WAVs, cache cap and purge, storage screen | Yes: spoken prompt/answer from the lock screen |
| **8. Optional layers** | Review-log export for optimizer; Time-of-Day automation intent; AlarmKit (iOS 26 only) | AlarmKit not testable until the phone is on iOS 26 |

---------------------------------------------------------------------------------------------------

## 8. Decisions still needed from the owner

1. **Geofence app location** (blocks section 2 and the final iOS design).
2. **Review windows:** how many per day and at what times (proposal: 7:30, 12:30, 19:30).
3. **Legacy groups:** migrate as static groups with a one-tap "link to tag" (recommended) vs auto-link.
4. **Which entry types in a tag count for memory by default:** scripture only (recommended) vs also notes and eLibrary passages.
5. **Tag rename hook:** approve a one-line call from `renameTag` in the 5,252-line `tag_quick_apply_helper.dart`, or accept orphan detection only.
6. **Alarm strength:** are ordinary notifications (+ optional Time Sensitive) enough, or do you want to update the iPhone to iOS 26 to make AlarmKit testable?
7. **Notification backoff** after ignored windows (recommended: on; after 3 ignored, once daily).
8. **Default workload numbers** (3 new/day, 30 reviews/day, 10-minute sessions, retention 0.90) — confirm or change.

---------------------------------------------------------------------------------------------------

## 9. Proposed in-app instructions (plain language)

**Bible Memory: how it works**

**What goes into memory.** You can add a single verse, a passage, or a note. You can also turn on Memory for a
`#tag`. When a `#tag` is on Memory, everything in it is included, and anything you add to that tag later joins
automatically. If you take something out of the tag, it stops being scheduled because of that tag, but
StudyBible remembers how well you knew it. If you put it back later, you pick up where you left off.

**One verse, one schedule.** If Romans 6:22 is in three of your tags and you also added it yourself, it is still one
item with one schedule. Reviewing it once counts everywhere.

**Try first, then listen.** Memory works by pulling the verse out of your own mind, not by hearing it over and over.
You will see or hear the reference, then have a moment of silence to say the verse yourself. Then StudyBible
shows or reads the answer. Effort to remember is what makes it stick.

**Tell it how you did.**
- **Again**: I couldn't say it, or I needed the answer.
- **Hard**: I got it, but with real struggle or mistakes.
- **Good**: I said it with only small slips.
- **Easy**: I knew it instantly.

**The schedule adapts to you.** StudyBible estimates how well you currently remember each item and schedules the next
try shortly before you would probably forget it. Verses you know well come back less often; verses you struggle with come back sooner.

**Why the gaps get longer.** Each time you remember something, the memory gets stronger and lasts longer, so the next
review can wait longer: first tomorrow, then days, then weeks, then months.

**When you forget.** That's normal. Choose Again. The verse comes back soon and the gaps start short again, but it
usually comes back faster than the first time.

**You choose the pace.** In Settings you set how many new verses start each day, how many reviews a day, and how
long a session may last. If you have more due than fits, the extra reviews simply wait; nothing is lost or counted
against you. A big `#tag` is introduced a few verses at a time.

**Review windows and alarms.** Pick the times you're willing to review. At each time StudyBible can send a
notification with the reference spoken aloud. Try to say the verse, then tap **Show Answer**, then choose how you did,
right from the Lock Screen or your Apple Watch. If you don't respond, nothing is lost; the item is offered again
later. Turn notifications or windows off any time in Settings.

---------------------------------------------------------------------------------------------------

## Sources consulted (external)

- pub.dev `fsrs` package page and changelog (v2.0.1 MIT, FSRS-6 in 2.0.0) and its GitHub repository
  (`open-spaced-repetition/dart-fsrs`).
- Apple WWDC25 session 230, "Wake up to the AlarmKit API" (iOS 26 requirement, authorization, Silent/Focus behavior,
  secondary intent, Live Activity/widget extension requirement).
- Apple developer forums / third-party AlarmKit write-ups (custom-sound limits).
- Apple `UNUserNotificationCenter` documentation (64 pending local notification limit).
- Items marked ⚠ above are not confirmed from primary documentation and are Phase 0 test targets.
