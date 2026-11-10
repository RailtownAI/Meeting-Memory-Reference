# WhiteboardApp — Design

> Status: **draft for review / work breakdown**. No code yet — this doc exists to make the
> design explicit so work can be divided.

## 1. Concept

A meeting-record app centered on the **whiteboard**. The user photographs a whiteboard
during/after a meeting; the app turns those photos into searchable meeting knowledge.

- **iOS (capture side):** user takes one or more whiteboard photos → an LLM generates a
  summary of the whiteboard's content → using calendar access, the capture is tied to the
  meeting it belongs to → photo reference + summary + meeting metadata are grouped and
  submitted to **railengine** (a vector database).
- **macOS (consumption side):** displays captured meeting data and runs an LLM agent that
  browses the railengine database to answer questions like *"what decisions were made in
  last week's meeting?"*
- **Privacy model:** the **original photo stays private in the user's iCloud**, referenced
  only by an ID. Only the summary, metadata, and that photo-reference ID are sent to
  railengine — the binary image never goes to the vector DB. Personal calendar details such as
  **attendees and the meeting title are kept off railengine**: only a calendar event identifier
  (plus scheduled times) is stored, and those details are refetched **on-device** from the calendar
  when needed.

## 2. High-level architecture

```
        iOS app (capture)                         macOS app (browse / ask)
   ┌───────────────────────────┐           ┌───────────────────────────┐
   │  Camera / photo capture   │           │  Browse & display UI      │
   │  Calendar (EventKit)      │           │  LLM agent (RAG) query UI │
   │  LLM summary (vision)     │           │  app-local models         │
   │  app-local models         │           └─────────────┬─────────────┘
   └─────────────┬─────────────┘                         │
                 │  map app-model ⇄ WBCoreModel          │  map WBCoreModel ⇄ app-model
                 └───────────────┬───────────────────────┘
                                 ▼
                   ┌─────────────────────────────────┐
                   │        WhiteboardCore           │
                   │  • WBCoreModel (server contract)│
                   │  • railengine read/write        │  (retrieval + ingest SDKs, hidden)
                   │  • iCloud photo store (by id)   │
                   └───────┬───────────────┬─────────┘
                           │               │
                 summary + │               │ photo binary (private)
                 metadata +│               │
                 photo-ref ▼               ▼
                 ┌────────────────┐   ┌──────────────────────────┐
                 │   railengine   │   │  Shared iCloud container │
                 │ (vector DB)    │   │  (photo by ID)           │
                 └────────────────┘   └──────────────────────────┘

Shared utility: RailtracksSwift — design-pattern assist, imported directly by all three modules.
```

## 3. Module responsibilities

| Module | Owns | Must NOT contain |
|---|---|---|
| **WhiteboardCore** | `WBCoreModel` (canonical server contract); railengine ingest/retrieval wrapped behind its own API; shared-iCloud photo store (write/read by ID); `WBKeychainStore` (auth-key CRUD); mapping helpers | Any UI, any UIKit/AppKit/SwiftUI, any app-specific view concerns; **LLM orchestration** |
| **iOS app** | Capture flow (camera/photo), calendar matching, LLM summary (via RailtracksSwift), its own app-local models | Direct railengine SDK calls; server contract logic |
| **macOS app** | Browse/display UI, LLM agent/query (via RailtracksSwift, using Core retrieval as its data source), its own app-local models | Direct railengine SDK calls; server contract logic |
| **RailtracksSwift** | Cross-cutting utility / design-pattern helpers | — (imported directly by Core, iOS, and macOS) |

The two railengine SDKs (`Railengine` retrieval, `RailengineIngest`) live **only** in Core
and are hidden behind Core's public API. `RailtracksSwift` is a direct dependency of all
three modules.

## 4. Model isolation (core design principle)

**Rule:** `WBCoreModel` is the single canonical model used to read/write railengine and the
iCloud photo reference. Each app keeps its **own internal models** for UI/work, and maps
to/from `WBCoreModel` **only at the server-access boundary** (i.e., when calling into Core).

```
  iOS app-model  ──map──▶  WBCoreModel  ◀──map──  macOS app-model
                             │
                     (railengine + iCloud ref)
```

Rationale:
- Each app's UI/domain model can evolve independently without touching the server contract.
- The server contract stays stable and has no app-specific concerns baked in.
- Core stays UI-agnostic; the mapping is the only coupling point.

## 5. Data flow

### 5a. Capture (iOS)
1. User photographs the whiteboard (one or more shots).
2. Photo written to the **shared iCloud container** → returns a stable **photoID**.
3. LLM (vision) generates a **summary** of the whiteboard content.
4. Calendar (EventKit) → find the meeting whose time window contains the capture → meeting metadata.
5. iOS builds its app-model, then **maps → WBCoreModel** `{ id, summary, meeting metadata, photoID, captureDate, ... }`.
6. Core **ingests** into railengine (embedding of summary + metadata + photoID).
   The **photo binary stays in iCloud** — only the reference travels.

### 5b. Query / browse (macOS)
1. User asks a question (or browses).
2. Mac app → Core → railengine **retrieval** (vector search) → `WBCoreModel` results.
3. LLM **agent** uses retrieved context to compose an answer.
4. For display, Mac app fetches the photo **by photoID** from the shared iCloud container.
5. Core **maps WBCoreModel → Mac app-model** for display.

### 5c. Meeting enrichment on selection (iOS)
When a meeting becomes the displayed one (auto-selected latest, or manually picked from the cached
list), iOS runs a two-step **off-main, cancel-on-swap** background task:
1. **Resolve-or-ingest the calendar record** — `WBiOSMeetingSyncService` (iOS-only, since only iOS
   ingests): mint the `WBMeetingID`, look it up via Core's retrieval store; if absent, build a
   PII-free `WBCalendarRecord` from EventKit and ingest it, then write the resolved `meetingId` back
   onto the display model.
2. **Load captured content** — `WBMeetingContentLoader` (**Core**, shared with macOS): fetch the
   meeting's whiteboard records most-recent-first; photos stream in lazily by `imageId`.

This is the concrete instance of the §10 write/read split — step 1 (write) is iOS-only; step 2
(read) is shared Core. Re-runs are deduped by the deterministic `WBMeetingID`; a forced pull-to-refresh
re-runs even when the meeting is unchanged.

### 5d. Capture → review → save (iOS)
The concrete capture pipeline that shipped (supersedes the high-level sketch in 5a):
1. **Capture** — the shared `WBiOSImageCaptureModel` presents the camera or photo library. The
   capture button is gated on a selected meeting, so a capture always has one to link to.
2. **Review & Save** — `WBiOSImageReviewView` shows the photo; on appear it runs two analyses from a
   **single** JPEG encode: `WBImageSummarizeService` (Gemini vision via `ImageSummarizeAgent`) for the
   **title** and **summary**, and `WBOCRService` (on-device Vision) for **`ocrText`**. The record's
   remaining fields — markdown / keywords / action items — are still left empty (see §9 #1). The user
   can **Retake** (re-runs both) and confirm or change the **linked meeting**; Save is enabled only
   once a title + summary exist. Leaving via Cancel cancels both in-flight analyses.
3. **Save** — Save pushes `WBiOSSaveResultView`, which runs `WBWhiteboardSaveService` (Core): mint a
   fresh per-capture `UUID` (§7 "Whiteboard record identity") → upload the photo to iCloud (skipped
   only when a retry already uploaded it) → ingest a `WBWhiteboardRecord`. Upload gates ingest, so a
   record never exists without its photo. The screen shows a spinner, then the outcome (saved /
   failed) and signals Home to refresh its captures. There is **no dedup** — re-saving is a new
   capture (§7).

The saved capture appears as a row in Home's **"Recent Captures"** — records fetched by `meetingId`,
photos loaded lazily per row from iCloud by `imageId`.

**OCR reading order (known limitation).** Vision returns one observation per detected text segment,
in no guaranteed reading order, so `WBOCRService` reconstructs that order geometrically: segments are
grouped into horizontal bands — same band when their vertical centres fall within half a line height,
which absorbs the skew of a hand-held photo — then bands run top-to-bottom and each band reads
left-to-right, newline-joined into the single string `ocrText` ingests (ingestion takes one string, so
the join happens once and serves both the UI and the record). Each segment is compared against its
band's **first** member rather than its most recent, so a long, gently sloping line can split across
bands; the alternative lets a band drift arbitrarily far down the photo, which is worse. That
tolerance is the knob to turn if ordering looks wrong on real captures. Recognition quality on
handwriting is not yet good enough to put in front of the user, so the review screen's OCR section is
hidden behind `WBiOSImageReviewViewModel.isOCRSectionVisible` — the text is still recognized and still
ingested, so macOS detail and search see it.

## 6. Photo storage decision

**Chosen: app-owned shared iCloud container, photo referenced by an app-minted ID.**
Rejected: routing photos through the user's Photos library + iCloud Photos sync.

Why (summary):
- **Portable identity** — we mint the ID; `PHAsset.localIdentifier` is not portable across devices.
- **Privacy** — a scoped app container vs. requiring full Photo Library access.
- **Sync control** — iCloud Photos sync cannot be programmatically triggered; a lag/optimize-storage state would break determinism.
- **Integrity & UX** — we own lifecycle; no dangling refs; no pollution of the personal camera roll.

Mechanism: **image data passes through an app-owned iCloud store, referenced by the app-minted ID.**
The *specific* iCloud facility is an implementation detail, not a design commitment — both CloudKit
(private DB + `CKAsset`) and an iCloud Drive ubiquity container (filename = ID) satisfy the contract:
write-by-ID on iOS, fetch-by-ID on macOS/iOS, on-demand download, and sync-state awareness. Same
**shared container** across both targets (same team). *Current implementation:* Core's `WBFileStore`
uses an **iCloud Drive ubiquity container** (photos at `Documents/Photos/<imageID>`); this can change
without touching callers, which only ever deal in the ID.

**Local caching is delegated to the iCloud facility, not the app.** With the current iCloud Drive
container, a downloaded photo is materialized as a local file, so repeat reads hit the local copy with
no cloud round-trip; the OS may evict it to a dataless placeholder under storage pressure, triggering a
re-download on the next read. The app keeps **no on-disk cache of its own**, and currently **no
in-memory decoded-image cache** — re-displaying a row re-reads the local file and re-decodes it, so an
in-memory `UIImage` cache remains an optional future optimization.

## 7. Cross-cutting concerns & open decisions

- **Apple Developer Program membership** — required for iCloud/CloudKit (and App Store). Blocking for the iCloud work.
- **Shared iCloud container ID** across iOS + macOS (same team). Bundle-ID unification is a *separate* choice (universal purchase).
- **LLM provider & placement** — **DECIDED.** Handled by **RailtracksSwift** as the facilitator; each
  app selects provider/model from the library's enums. Orchestration is **app-side** (iOS: vision
  summary; macOS: agent/RAG using Core's retrieval as its data source). Core does **not** orchestrate the LLM.
- **auth / key storage** — **DECIDED.** Credentials stored in **Keychain via a shared
  `WBKeychainStore` in Core** (Security `SecItem` API with `kSecUseDataProtectionKeychain: true` →
  uniform iOS/macOS behavior; entitlements are the only per-target part). Storage is **per-app**
  (each app writes to its own keychain — no shared access group, no iCloud sync), but both use the
  **same key identifiers** (constants defined in Core's `WBKeychainStore`) so both apps address the
  items identically; only the physical keychain differs. There are **two rail engine servers** —
  **whiteboard** and **calendar** — so **five credentials** are stored:
  - **Gemini API key** — the LLM provider key.
  - **`ENGINE_TOKEN`** (×2: whiteboard, calendar) — rail engine **ingestion** token per server.
  - **`ENGINE_PAT`** (×2: whiteboard, calendar) — rail engine **retrieval** PAT per server. These
    **expire**; expiry handling (warn/refresh) is a **future** concern — v1 just stores the string.
- **Calendar matching** — **DECIDED.** Primary heuristic: photo timestamp within the event window,
  **plus a trailing grace buffer** (`[start − ε, end + δ]`, δ ≈ 10–15 min) since photos are taken as
  the meeting wraps. Consider only real timed meetings (skip all-day/declined). On multiple matches,
  pick nearest by start; if still ambiguous or no match → leave meeting **empty**.
  **Known limitation:** a meeting that runs *well past* its scheduled end pushes the timestamp beyond
  the grace buffer → no auto-match → empty. Recovering these depends on the **manual-link** feature,
  which is therefore the designated fallback for significant schedule overruns (not purely optional).
- **Meeting identity (`WBMeetingID`)** — **DECIDED.** A meeting *occurrence* is identified by
  **`"<eventUID>#<startEpoch>"`** (`eventUID` = `calendarItemExternalIdentifier`; `startEpoch` =
  occurrence start in whole seconds). Deterministic and human-readable, minted in **Core**
  (`WBMeetingID.mint`) so iOS (ingest) and macOS (retrieve-only) compute the identical id and resolve
  the same railengine record; it is also the record's `id`/`meetingId` and the dedup key (the engine
  assigns its own `EventId` on ingest — see §9 #14).
  *Fallback:* swap for an encoded/hashed form if a raw `eventUID` ever trips the engine's id length or
  the `$.meetingId:<value>` query delimiter.
- **Whiteboard record identity** — **DECIDED (revised in WB-44).** A captured whiteboard is identified
  by a **fresh `UUID` minted per capture** in Core (`WBWhiteboardSaveService.makeIDs()`), used as
  **both** the record `id` (railengine's `eventId` must parse as a UUID) and the iCloud photo filename
  (`imageId`). It is **non-deterministic by design**: re-processing the same photo mints new ids, so
  there is **no dedup** — every capture is a distinct record with its own iCloud copy.
  - *Why:* it lets the **same whiteboard photo be attached to multiple meetings** with no special
    casing — the easy solution. (The original WB-7 design derived both ids from a **SHA-256 of the
    JPEG bytes** so identical bytes collapsed into one content-addressed record; that made
    multi-meeting reuse awkward, and the client-side `$.id:` dedup pre-check was unreliable anyway
    because the engine assigns its own `EventId` on ingest — see §9 #14.)
  - *Trade-off:* re-processing an identical whiteboard now **accumulates duplicate photo files and
    engine records** (extra iCloud storage + rows), with no automatic collapse. Accepted for
    simplicity — see the future "reuse existing capture" affordance in §9 #15.
  - *Ordering guarantee:* upload gates ingest — the photo is uploaded to iCloud (skipped if already
    present) **before** the record is ingested, and ingest runs only if the upload succeeds, so no
    railengine record ever exists without its iCloud photo. The ids are minted **once per capture**
    and reused across retries, so a retry after a failed ingest re-ingests without re-uploading.
- **iCloud quota** — photos count against the user's private iCloud storage; consider compression / max-resolution / thumbnail strategy.
- **Offline & retries** — capture may happen offline; queue ingest and photo upload with retry.
- **Multiple photos per meeting** — data model must support N photos grouped under one meeting capture.
- **Logging** — a shared `WBLog` facade in `WhiteboardCore` (swift-log backed) is bootstrapped **per
  app at launch** (`WBLog.setup()` in each `App` init). The facade lives in Core so any layer can log;
  the launch-time bootstrap stays app-owned. Usage conventions live in `coding-style.md`.

## 8. Work breakdown (candidate epics)

Foundational first (E1–E3 are in Core and unblock the apps). **UI is pulled as far forward as
possible** — see *Sequencing* below. The `Depends on` column splits each UI epic into its mock-backed
**shell** vs. its real **wiring**.

| ID | Epic | Depends on |
|----|------|-----------|
| **E1** | Core data model & mapping contracts — **artifact-oriented `WBCoreModel`** (a meeting capture holds an extensible set of typed artifacts: photo ref, summary, and future transcript/audio/diagram) + app-model mapping shape; Core's public APIs expressed as **protocols** (enable mock/real dependency injection — see §10) | — |
| **E2** | railengine integration in Core (ingest + retrieval wrappers behind a **protocol-based** Core API so apps can inject mock or real; retrieval supports **single-meeting** and **cross-meeting** queries; records tagged with meeting id/date metadata) | E1 |
| **E3** | Shared iCloud photo store in Core (write/read by ID, shared container) | E1 |
| **E4** | iOS capture flow — **UI shell** (camera, review, confirm) needs only local state; upload-to-iCloud wiring gates on E3 | shell: — · upload: E3 |
| **E5** | iOS **photo processing** — modular/swappable step producing artifacts; LLM vision summary is the first implementation; multi-step orchestration delegated to **RailtracksSwift's workflow system** (no custom pipeline) | E1 |
| **E6** | iOS calendar integration (EventKit, meeting matching; store the **calendar event identifier + scheduled times** — attendees and title are refetched on-device, never persisted to the model or sent to railengine, see §9 #3) | — |
| **E7** | iOS assembly + ingest (build WBCoreModel, submit to railengine) | E1,E2,E4,E5,E6 |
| **E8** | macOS browse/display UI — renders mock `WBCoreModel` → app-local model | shell: E1 · real data: E2,E10 |
| **E9** | macOS query/agent (RAG over railengine + LLM) — **UI shell** (query box, results, answer) mock-backed; real agent wiring later | shell: E1 · agent: E2 + RailtracksSwift |
| **E10** | macOS photo fetch from iCloud for display | E3 |
| **E11** | Cross-cutting: entitlements, auth, error/sync handling, privacy review | E2,E3 |
| **E12** | iOS **browse/display UI** (view captured meetings/artifacts; mirrors E8 + E10) — shell uses placeholder images; real photo fetch gates on E3 | shell: E1 · real photos: E3 |

Natural split (by track): **Core (E1–E3)**, **iOS (E4–E7, E12)**, **macOS consumption (E8–E10)**,
with E11 shared. For the current **2-person team** (no dedicated Core owner), see **§10** for how Core
is divided and how both sides work in parallel.

**UI note:** there is no separate UI design phase — each epic that surfaces UI (E4, E8, E9, E12)
includes its own per-platform UI build, produced by the implementer from the team's existing
**rough design guideline**. Independent per-platform UI is intentional (see §2/§4).

### Sequencing — UI-first

UI is deliberately pulled to the front so developers have a **live UI to test against** from early on.
Each UI epic splits into a mock-backed **shell** (gated only on the E1 contract) and its real **wiring**
(gated on the relevant service). Build the shell first, then swap mocks for real implementations via
dependency injection (a one-line change) as the wiring lands.

- **Phase 0 — freeze the contract (joint, small):** E1 — `WBCoreModel` + Core protocols.
- **Phase 1 — UI shells in parallel (right after E1), mock-backed:**
  - iOS: E4 capture screens (stubbed save), E12 browse shell (placeholder images)
  - macOS: E8 browse shell, E9 query shell (mock retrieval + stubbed agent)
  - Navigation scaffolding and empty/loading/error states can begin **day 1**, even before E1.
- **Phase 2 — real wiring behind the protocols (runs in parallel with Phase 1):**
  - Core: E2, E3 (write half = iOS owner, read half = macOS owner, per §10)
  - iOS: E5, E6, E7 · macOS: E9 real agent, E10 photo fetch · E11 throughout.

**Caveat:** expect a **polish pass once real data flows** — actual summary lengths, photo aspect ratios,
and agent answer formatting will nudge layouts. Keep each mock faithful to `WBCoreModel` so the swap
stays clean.

## 9. Future requirements & planned injection points

Not in initial scope, but recorded so the design leaves room for them.

1. **Modular photo processing.** The photo → artifacts step (E5) is a swappable module behind an
   abstraction, replaceable with richer work later (privacy-text redaction, LLM-generated Mermaid
   diagrams when a diagram is detected, etc.). Multi-step orchestration is delegated to
   **RailtracksSwift's built-in workflow system** — we deliberately do **not** build our own pipeline.
   *Design impact:* processing output is **0..N typed artifacts**, not a single summary → drives the
   artifact-oriented `WBCoreModel` (E1). Redaction produces a derived image; decide whether the original,
   the redacted copy, or both are retained in iCloud.

2. **Query modes (macOS).** Two usage patterns: **single-meeting** query (browse one meeting's data)
   and **cross-meeting** query (semantic search across meetings, e.g., "decisions last week").
   *Design impact:* primarily a railengine data-organization concern — tag each record with meeting id
   + date as filterable metadata; Core's retrieval API exposes both scopes (E2).

3. **Attendee notifications.** Email attendees when a report is ready. *Design impact:* attendees
   (like the meeting title) are **personal information and are never stored in `WBCoreModel` or sent
   to railengine** — only the calendar event identifier is kept. A consumer refetches attendees
   **on-device from EventKit** via that identifier when needed. The send itself is a **post-ingest injection point** that gathers
   attendee emails on-device at send time (+ **Contacts** permission if needed) and likely needs a
   **backend/server capability** for actual delivery. *Current implementation:* calendar ingest sends
   **`organizerRef = ""` and `participantRefs = []`** (no people at all) and re-resolves attendees
   on-device via EventKit — even simpler than the opaque-reference scheme, which stays deferred.

4. **Additional meeting data types.** Text/audio transcripts and other data attached to a meeting later.
   *Design impact:* same as #1 — the artifact-oriented `WBCoreModel` absorbs new types without schema
   churn. Binaries (audio) → iCloud by ID (like photos); text (transcript, diagram source) → vectorized
   into railengine and/or stored. No structural change needed if E1 is built extensibly.

5. **iOS query UI (later).** iOS currently has no complex "ask the LLM" query experience — that is
   macOS-first. Once macOS proves out the agent/RAG solution (E9), a similar capability may be added to
   iOS with a **different, platform-appropriate UI** (same underlying task via Core retrieval +
   RailtracksSwift, different presentation). *Design impact:* none structurally — Core's retrieval API
   and the agent pattern are already shared-capable; only a new iOS UI + wiring is needed.

6. **Railengine SDK — silent decode-drop and discarded relevance score.** The typed
   `searchVectorStore<T>` overload in `Railengine.swift` decodes each hit with
   `documents.compactMap { try? contentDecoder.decode($0.content) }`: any result whose `content`
   fails to decode into the model is **silently dropped** (`try?` swallows the error, `compactMap`
   removes the `nil`), so decode failures are invisible and undebuggable. That same typed path also
   **discards** each hit's vector-relevance `SearchDocument.score`. Both behaviors live in the
   Railengine SDK, which we own.

7. **Whiteboard capture pipeline — LANDED (WB-7, WB-44, WB-49).** The
   capture → mint `imageId` → upload to iCloud → ingest `WBWhiteboardRecord` path is wired end-to-end
   (§5d), so iOS's "Recent Captures" section (Core `WBMeetingContentLoader` + lazy photo load) is
   exercised against real data rather than fixtures. The POC uploader / iCloud-browser spikes that
   stood in for it were deleted in WB-49, and the Search tab they hung off is a "Coming soon"
   placeholder again. *Design impact:* none; the read path was already built and now has real data.

8. **`imageId` / record-id convention — DECIDED in WB-7, REVISED in WB-44.** WB-7 derived both ids
   from the photo's SHA-256 (`imageId` = first 12 hex chars, record `id` = a deterministic GUID) for
   content-addressed dedup. WB-44 replaced this with a **fresh per-capture `UUID` used as both ids**
   (non-deterministic, no dedup) so the same photo can be reused across meetings — see §7 "Whiteboard
   record identity" and its trade-off. Kept here for history.

9. **Calendar "true sync."** On a retrieval hit the sync service currently trusts the stored record.
   Future: diff it against the live EventKit occurrence (title / times / location / recurrence) and
   re-ingest on divergence, so a meeting edited after first ingest stays in sync (`TODO` marked in
   `WBiOSMeetingSyncService`).

10. **Stale state on mid-session calendar-access loss (edge case, deferred).** If calendar access is
    revoked (or a calendar fetch errors) *after* a meeting was already displayed, `load()` sets
    `.accessDenied`/`.empty` but doesn't clear `selectedID`/`capturesState`, so the "Recent Captures"
    section can linger under the permission/empty message. Judged too edge-case for the first build;
    when hardening, clear the displayed selection + captures on those paths.

11. **Show capture metadata when iCloud is unavailable.** `loadCaptures` currently short-circuits to
    `.iCloudUnavailable` before fetching records, so with iCloud off the user sees only the message,
    not the list. Records (title/timestamp) come from railengine and don't need iCloud — a future
    improvement is to still show the rows with placeholder thumbnails and surface the
    iCloud-unavailable state per-photo, rather than hiding the whole section.

12. **Avoid redundant image-summarize LLM calls (cost).** The review screen's `summarize()` can fire
    more than once for the *same* image — e.g. if `.task` re-runs when the retake camera cover
    dismisses (fullScreenCover's effect on the presenter's appear/disappear is iOS-version-dependent).
    The cancel-on-restart guard keeps this **correct** (only the latest run applies its title/summary),
    but `Task.cancel()` is cooperative and may not abort the in-flight Gemini **vision** request — so a
    spurious re-fire can cost an extra API round-trip (tokens + latency). Future: gate on image
    identity (a `summarizeIfNeeded()` keyed to `ObjectIdentifier(image)`) so summarization runs exactly
    once per distinct image. Deferred as a demo-acceptable cost.

13. **Refresh app state after a delete-all.** The Settings "Delete All Data" action wipes both
    railengine engines and the iCloud photos, but doesn't invalidate other tabs' already-loaded
    state — Home's "Recent Captures" (and the resolved meeting) keep showing deleted entries until a
    pull-to-refresh. Future: have delete-all signal the affected screens to reload (or reload Home on
    appear) so the UI reflects the wipe immediately across tabs.

14. **Railengine `EventId` is server-assigned — raise with the backend team.** On ingest the engine
    assigns its *own* `EventId` and does **not** adopt the record `id` we send. Consequences we had to
    work around: (a) records can't be fetched by our id via `getStorageDocumentByEventId` (it 404s),
    so lookup/dedup goes through a JSONPath **content** query (`$.id:`, like calendar's `$.meetingId:`)
    instead; (b) ingest is an **insert, not an id-keyed upsert**, so re-ingesting the same content id
    creates duplicate documents — our client-side pre-check is the only guard, and it's
    race/eventual-consistency-prone. **Action:** ask the backend team whether the client can
    supply/override the `EventId` (or whether ingest can upsert by a caller-provided key). If yes, we
    could look records up by id directly, drop the JSONPath dedup, and get real idempotency.

15. **Duplicate whiteboard captures accumulate (WB-44 trade-off).** Identity is now a fresh
    per-capture `UUID` with no dedup (§7 "Whiteboard record identity"), so re-processing an identical
    whiteboard uploads another iCloud copy and ingests another record — storage and engine rows grow
    with every re-save. Accepted deliberately, as the simplest way to let the **same photo link to
    multiple meetings**. Future: a "reuse existing capture" affordance (pick an already-saved
    photo/record to attach to another meeting) or an opt-in dedup, so intentional reuse doesn't
    duplicate the underlying photo.

16. **Save is final, but the swipe-back gesture is an unguarded gap.** Once the user taps Save and
    lands on `WBiOSSaveResultView`, saving is intended to be a commit point — there's deliberately no
    "back to Review" affordance, and the nav back button is hidden
    (`.navigationBarBackButtonHidden(true)`). However, hiding the back button does **not** reliably
    disable the interactive left-edge **swipe-back** pop on all iOS versions, so a user could still
    swipe back to the review screen. Future: disable the interactive pop on the result screen (or
    otherwise guard it) so "Save is final" is truly enforced.

17. **Scope delete-all to the current user's own items.** Settings' "Delete All Data" currently wipes
    *every* document in both railengine engines and *all* iCloud photos — on a shared/multi-user engine
    that would destroy everyone's data. Future: delete only the records + photos belonging to the
    signed-in user (across all three stores). **The mechanism for attributing an item to "me" is
    unknown for now** — e.g. a per-user owner/key field on ingested records, or scoping by the user's
    account identity — to be designed, and likely needs backend support (see §9 #14).

18. **`WBActionItem.status` is reserved, not specified (WB-14).** Action items extracted from a
    whiteboard are ingested with `status` set to the `WBActionItem.statusUnknown` sentinel
    (`"unknown"`) and `assigneeRef` left `nil`. This is deliberate: a photo of a whiteboard records
    that a task *exists*, not whether it's done or who owns it, and no lifecycle is specified yet.
    The field is **reserved space** — nothing reads it, nothing transitions it, and there is no
    mark-done affordance on any screen. Future: define the permitted values (e.g. `open` / `done`,
    which is what `WBActionItem`'s own doc comment suggests), decide where a transition is authored
    (macOS "Action Items" browse view is the obvious host), and how it's written back — note that
    ingest is insert-not-upsert (§9 #14), so updating an item's status is not simply a re-ingest.
    Resolving assignees to real people also depends on `assigneeRef` gaining a defined format.
    *Design impact:* none today; any consumer that filters on status must treat `"unknown"` as a
    first-class value rather than assuming `open`/`done`.

19. **iCloud photo loading is implemented twice, and only macOS caches.**
    `WBMacOSICloudWhiteboardImageProvider` resolves an `imageId` to a decoded image and holds it in a
    `static NSCache`; iOS's `WBiOSMeetingViewModel.captureImage(imageID:)` does the same fetch and
    decode with **no cache**, so Home re-reads iCloud every time a capture row re-renders. The two
    also enter Core through different doors — macOS calls `WBFileStore.photoData` directly, iOS goes
    through `WBMeetingContentLoader.photoData`, which is a one-line passthrough to that same
    function. Future: give Core one photo-access path that owns the fetch **and** the cache (keyed by
    `imageId`), leaving each app a decode into `UIImage`/`NSImage`. *Design impact:* none to the
    contract; it removes a redundant public entry point from Core and closes a real iOS performance
    gap rather than just deduplicating.

20. **Wire-date encoding/decoding is spread across all three modules and disagrees.**
    `WBWhiteboardRecord` defines the wire forms (ISO-8601 strings plus epoch seconds) and the
    sentinels (empty string, epoch `0`), but the rules for reading and writing them live outside
    Core: `WBMacOSWhiteboardRecordAdapter` parses ISO with *and* without fractional seconds, falls
    back to epoch, then to `.now`; `WBiOSCapture` ignores `capturedAt` entirely and reads only
    `capturedAtEpoch`, showing "Unknown time" otherwise; and both writers
    (`WBWhiteboardSaveService`, `WBiOSMeetingSyncService`) construct their own plain
    `ISO8601DateFormatter`. A timestamp carrying fractional seconds therefore parses on macOS and
    degrades to "Unknown time" on iOS. Future: Core owns the encode/decode of its own wire formats,
    with the apps mapping only the resulting `Date`s into their display models. *Design impact:*
    strengthens §4 rather than bending it — the app-local models still differ, but interpreting the
    **contract** stops being duplicated per platform.

21. **Contact-photo caching and permission priming are duplicated per platform.**
    `WBiOSAttendeeViewModel.loadPortrait` and `WBMacOSContactsAttendeeImageProvider.avatar` are the
    same algorithm step for step — check a `static NSCache` keyed by attendee id, prime access via
    `canRequestAccess`/`requestAccess()`, call `photoThumbnailData(email:name:)`, decode, cache,
    return — differing only in `UIImage` vs `NSImage`. Core already owns the lookup
    (`WBContactPhotoService`); what's copied is the policy around it. Future: move the cache and the
    access priming into Core, leaving each app the decode. *Design impact:* none; purely removes a
    second copy of a policy that should have one owner.

**Net effect on current design:** the one meaningful early adjustment is making `WBCoreModel` (E1)
**artifact-oriented/extensible** rather than fixed `{summary, photoID}` fields — this single change
accommodates #1 and #4. #2 shapes the retrieval API (E2); #3 adds attendee capture now (E6) plus a
future backend injection point; #5 is a later iOS-UI addition; and #6 is a noted Railengine-SDK
problem (silent decode-drop / discarded score). Nothing conflicts with decisions already made.

## 10. Ownership & collaboration (2-person team)

Team: **iOS (you)** and **macOS (other)**. There is no dedicated Core owner — Core is split by role.

### Contract-first
Before splitting, jointly freeze the contract: the artifact-oriented `WBCoreModel` and Core's **public
API as protocols** (ingest, retrieval, photo store, keychain — signatures only). Commit it; both sides
then code against a stable surface. Whoever leads the architecture drives this step.

### Split Core by write/read, aligned to platform
| Owner | Role | Core they own |
|---|---|---|
| **iOS (MS)** | producer | Core **write/ingest** + photo **write** |
| **macOS (FS)** | consumer | Core **read/retrieval** + photo **read** |
| **Joint (lead)** | — | `WBCoreModel`, `WBKeychainStore`, shared plumbing — frozen first, changed via PR |

Because iOS writes and macOS reads, each builds the exact Core half its app needs, so the two rarely
touch the same files. Per-target entitlements (iCloud, keychain access) are configured by each platform
owner for their own app.

### Work in parallel via mocks (no seed data)
Once `WBCoreModel` is frozen, each side mocks the other's protocol:
- **macOS** writes a **mock retrieval** returning sample `WBCoreModel` results → maps to its local model →
  builds all browse/query/agent UI → swaps in the real Core retrieval later (one-line DI change).
- **iOS** **stubs the ingest** protocol to build the capture flow before Core's real write path exists.

This works precisely because of model isolation (§4): behind the protocol, a fake Core is
indistinguishable from the real one. No backend seeding, and neither side waits on the other.

### Mechanics (kept light for two people)
- One file per concern in Core (`WBCoreModel.swift`, `WBIngest.swift`, `WBRetrieval.swift`,
  `WBPhotoStore.swift`, `WBKeychainStore.swift`) → merge conflicts stay rare.
- PR + review on Core changes (especially the joint files); app-only changes can be lighter.
- Keep the `RailtracksSwift` version pins (project + package) in sync; coordinate bumps.
- **Tests:** unit tests are welcome, but neither `WhiteboardCore` nor the app targets currently
  have a test target — adding tests means adding a `testTarget` to `Package.swift` (Core) and/or a
  test target to the app(s). Left out for now to avoid a dangling empty target.
