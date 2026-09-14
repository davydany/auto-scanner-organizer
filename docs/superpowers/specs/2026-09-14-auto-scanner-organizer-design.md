# Auto Scanner Organizer — Design Spec

- **Date:** 2026-09-14
- **Status:** Draft, awaiting owner review
- **Classification:** Personal tool: one user, one Mac, not a product. It is still built to production standards (TDD, ADRs, docs).
- **UI mockups:** [Auto Scanner Organizer UI canvas](https://claude.ai/code/artifact/753e0fef-4f48-4196-92d4-9fbc55bc98dd). The source files are in `docs/design/ui-mockups/*.dc.html`.

## 1. Purpose

A native macOS app. The owner loads a mixed stack of paper into the scanner's feeder, presses **Auto Scan**, and optionally says what the batch is for. The app then:

1. scans every page into a staging folder
2. reads the pages, including handwritten annotations
3. splits the stack into separate documents
4. names each document properly
5. files each one as a **searchable PDF plus a Markdown note** in the right place in the Obsidian vault, so an LLM or Obsidian search can find it later

When it isn't confident, it asks the owner rather than guessing. When the batch has a purpose (for example "2026 taxes, business receipts"), it also records each document in a running ledger note.

### Success criteria

- A mixed stack of 3–10 documents becomes correctly split, named, and filed PDFs and notes with no manual steps when confidence is high.
- Uncertain splits, folders, amounts, purpose mismatches, and duplicates always wait in **Needs review**. Nothing is silently misfiled.
- The home screen shows every batch and what happened to each document.
- No scan is ever lost. Pages stay in staging until filing succeeds, and every failed step can be retried without rescanning.
- Notes are plain Markdown with a fixed property schema, so Obsidian search, Dataview, and LLM tools can query them.

## 2. Scope

**In scope (v1):**
- Scanner discovery, both USB and network. The owner's scanner is a Canon MF4700 Series on the network.
- Feeder or flatbed scanning, duplex, 300 dpi.
- Optional batch purpose.
- Watching the staging folder, including files dropped in by hand.
- On-device OCR.
- Claude analysis in two steps: read the stack, then file each document.
- Searchable PDF output, Markdown notes, and purpose ledgers.
- Review queue, history and audit log, retry.
- Settings: folders, AI, scanner.

**Deferred:**
- Learning from the owner's review choices.
- Automatically clearing out `_done/`.
- Scanning from a phone.
- Setting a purpose on files dropped in by hand.
- Re-filing documents that are already filed.
- Multiple users, feature flags, App Store distribution.

## 3. User flows

1. **Auto Scan.** The owner picks a scanner in the toolbar and presses Auto Scan. The purpose sheet opens with a text field, recent-purpose chips, and a preview of the remembered destination. The owner presses **Start scan** (or Return), or **Skip**. Pages stream into a new batch folder, and the batch appears on Home as *Scanning*, then *Processing*.
2. **Processing.** Each batch goes through: scanned → text recognized → read by Claude → filing. Each document either ends up **Filed** (with its name, folder, confidence, and a one-line reason) or goes to **Needs review**.
3. **Review.** The Needs review screen shows:
   - the page strip, where the owner can add or remove splits
   - a large page preview
   - title and date fields, with a preview of the resulting filename
   - fields read from handwriting
   - up to 3 folder suggestions with confidence, plus *Choose another folder…* and *New subfolder…*
   - when relevant: the ledger amount, the purpose mismatch reason, or a link to the likely duplicate

   **File** writes exactly the same outputs automatic filing would. **Skip for now** leaves the document queued.
4. **Failure.** The batch shows **Failed** with the reason and **Retry**, which resumes from the failed step. If scanning stopped partway, the card offers **Continue scanning into this batch** or **Process these N pages**.
5. **Batch detail.** Shows pages grouped by document (with Open note / Show in Finder) and a timeline of events with times, tokens, and cost.
6. **Settings.** Three tabs:
   - **Folders:** staging folder and vault folder, each with Choose….
   - **AI:** model, API key in Keychain with Test connection, auto-file threshold.
   - **Scanner:** default scanner with Test scanner, source, resolution, color, both sides.

## 4. Architecture

A single SwiftUI app target (macOS 26) plus a local Swift package, `ScanCore`, that holds all the logic. Every outside dependency sits behind a protocol, so the logic can be tested without hardware, network, or the real vault.

```
Auto Scan ─▶ Scanner ──▶ staging/<batch-id>/page-NNN.png + batch.json
                               │
          StagingWatcher ◀─────┘  (also adopts files dropped in by hand)
                │
          TextRecognizer (Apple Vision, on-device) ─▶ words + bounding boxes
                │
          Analyzer step 1 "Read stack"  (Claude, structured output)
                │   documents[], splits, fields, handwriting, purpose fit
                ▼
          Analyzer step 2 "File document" (Claude + read-only vault tools)
                │   skipped when a purpose mapping already fixes the folder
                ▼
          Decision rules ─▶ auto-file  or  Needs review (owner decides)
                │
          PDFBuilder ─▶ NoteWriter ─▶ LedgerWriter ─▶ Filer ─▶ archive raw scan to _done/
                │
          JobLog (append-only events) ─▶ History / Review / Detail UI
```

| Module (ScanCore) | Responsibility | Depends on (protocols) |
|---|---|---|
| `Scanning` | Discover scanners, run a feeder/flatbed scan, write pages and `batch.json` | `ScannerBrowsing`, `ScannerDevice` (ImageCaptureCore adapters) |
| `Staging` | Detect ready batches, adopt dropped files, archive to `_done/` | `FileSystem`, `Clock` |
| `OCR` | Page image → recognized lines with bounding boxes | `TextRecognizer` (Vision adapter) |
| `Analysis` | Claude requests for both steps, schema validation, cost accounting | `ClaudeTransport` (URLSession adapter), `VaultReader` |
| `Decisions` | Pure function: analysis + settings + vault state → file or review (with reasons) | none |
| `Output` | `PDFBuilder`, `NoteWriter`, `LedgerWriter`, filename rules, masking | `FileSystem` |
| `Filing` | Safe writes, collision naming, folder creation, duplicate check | `FileSystem`, `VaultReader` |
| `Jobs` | Append-only event log; batch and document status derived from events; resume after restart | `EventStore` (SwiftData adapter) |
| `Purposes` | Remember which folder and ledger each purpose uses; recent purposes | `PurposeStore` |
| `Settings` | Typed settings (UserDefaults); API key (Keychain) | `KeyValueStore`, `SecretStore` |

The app target holds only the SwiftUI views, view models, and the concrete adapters.

## 5. Scanning

- **Discovery:** `ICDeviceBrowser` with `ICDeviceTypeMask.scanner` for local, shared, and Bonjour scanners. The toolbar lists them, and the last-used scanner is the default.
- **Session:** open a session, select the functional unit (document feeder by default, or flatbed), then set:
  - resolution: 300 dpi
  - color mode: color, grayscale, or black & white
  - duplex: when the feeder supports it
  - transfer mode: file-based, PNG
- **Pages:** written to `staging/<batch-id>/page-NNN.png`, where `batch-id` is the local timestamp `YYYY-MM-DD-HHmmss`. Blank back sides from duplex scans are dropped when less than 0.5% of pixels are non-white after thresholding. The threshold is tuned in tests.
- **`batch.json`:** written when scanning finishes, and acts as the readiness marker:
  ```json
  { "id": "2026-09-13-224203", "source": "scanner", "scanner": "Canon MF4700 Series",
    "settings": {"unit": "feeder", "dpi": 300, "color": "color", "duplex": true},
    "purpose": "2026 taxes, business receipts", "pages": 7,
    "startedAt": "2026-09-13T22:42:03-04:00", "completedAt": "2026-09-13T22:42:38-04:00",
    "interrupted": null }
  ```
- **Interruptions:** a jam or disconnect writes `batch.json` with `interrupted: {"afterPage": 4, "reason": "paper jam"}`. The UI then offers *Continue scanning into this batch* (appends pages) or *Process these N pages*.

## 6. Staging watcher

- Watches the staging folder root with FSEvents.
- **Scanner batches** are ready when `batch.json` exists and isn't marked interrupted.
- **Files dropped in by hand** (`.pdf .png .jpg .jpeg .heic .tiff`) at the staging root are adopted once their size has stopped changing for 5 s. Each is moved into `drop-<timestamp>/` with a generated `batch.json` (`source: "drop"`, no purpose). PDF pages are rendered at 300 dpi with PDFKit.
- The watcher ignores `_done/` and any folder whose name starts with `.`.
- On launch, it matches the staging folder against the job log. Unknown batch folders are adopted, and unfinished jobs resume from their last completed step.

## 7. OCR

- `VNRecognizeTextRequest` with `.accurate` recognition and language correction on. Pages are processed concurrently, at most 4 at a time.
- Output per page: recognized lines, each with text, confidence, and a normalized bounding box.
- This output is used for the invisible text layer in the PDF (§10.3), for the `Extracted text` section of the note, and as extra input to Claude.

## 8. Claude integration

### 8.1 Transport

- No official Swift SDK exists. The app calls `POST https://api.anthropic.com/v1/messages` with `URLSession`, sending the headers `x-api-key` and `anthropic-version: 2023-06-01`.
- **Models:**

  | Setting | Model ID | Notes |
  |---|---|---|
  | Default | `claude-sonnet-5` | Adaptive thinking by default |
  | Option | `claude-opus-5` | |
  | Option | `claude-haiku-4-5` | Images capped at 1568 px |

  All three support image input and structured outputs. Implementation must check each current request shape against the claude-api skill docs; nothing is written from memory.
- **Images:** pages are downscaled to at most 2576 px on the long edge (1568 px for Haiku) and sent as JPEG at quality 85, base64-encoded, within the 32 MB request limit. If a batch exceeds the per-request image limit (to be confirmed during implementation), it is sent in consecutive chunks. Any document split that falls on a chunk boundary is always sent to review.
- **Caching:** prompt caching is on the system prompt and the vault folder index, since those are stable across requests.
- **Usage:** every request records `usage` (input and output tokens) and an estimated cost in the job log.
- **Retries:** errors 429, 5xx, and network failures are retried 3 times with exponential backoff, respecting `retry-after`. Error 400 fails immediately. A `stop_reason: "refusal"` sends the document to Needs review with the reason.

### 8.2 Step 1: Read stack (one request per batch)

**Input:**
- the page images
- the OCR text for each page
- the batch purpose, if any
- the fixed lists of allowed values (§10.2)

**Output**, as a strict JSON schema via `output_config.format`:

| Field | Type | Notes |
|---|---|---|
| `documents[].pages` | int[] | Consecutive, 1-based. Together the documents cover every page exactly once. |
| `documents[].split_confidence` | 0–1 | |
| `documents[].doc_type` | enum | From §10.2 |
| `documents[].title`, `from`, `doc_date` | string / null | `doc_date` is ISO, and null if absent |
| `documents[].summary` | string | 2–3 sentences |
| `documents[].tags` | string[] | Lowercase, hyphenated |
| `documents[].key_facts` | object | `amount_due`, `due_date`, `amount`, `currency`, `account_last4` (all optional) |
| `documents[].handwritten[]` | object[] | `page`, `raw_text`, plus optional `paid_on`, `amount_paid`, `payment_method`, `check_number` |
| `documents[].purpose_fit` | object / null | `fits` (bool), `reason`, `tax_year`, `tax_category`, `expense_category` |

The app then validates the result: page coverage is complete, pages are consecutive, and enum values are allowed. If validation fails, the app retries once with the validation errors included. If it fails again, the batch goes to review.

### 8.3 Step 2: File document (one request per document)

This step is skipped when the batch purpose already has a remembered folder (§11).

**Input:**
- the step 1 result for this document
- the vault folder index: every directory (excluding dot-folders), each with its note count
- the batch purpose, if any

**Tools** (read-only, run by the app, at most 8 calls per document):
- `list_folder(path)`: lists subfolders and `.md` note names.
- `read_note(path)`: returns the first 4,000 characters of a `.md` note.
- Every path is resolved, including symlinks, and must stay inside the vault root. Anything else returns a tool error.

**Final answer:** a `submit_placement` tool call with `strict: true`, containing:
- `folder`: vault-relative
- `new_subfolder`: optional, a single path segment
- `related_notes[]`
- `confidence`: 0–1
- `reason`: one sentence
- `alternatives[]`: up to 2, each with a folder and confidence

The app validates the answer: no `..`, no absolute paths, and any folder that doesn't exist must be exactly the parent plus `new_subfolder`.

### 8.4 Untrusted content

The text on scanned pages and in vault notes is treated as data, never as instructions; the system prompt says so explicitly. Claude has no write tools. All writes happen in `Filing` after the app has validated Claude's output.

## 9. Decision rules (`Decisions`, pure and table-tested)

A document is **auto-filed** only if all of the following hold:
1. `split_confidence` ≥ threshold, and the split isn't on a chunk boundary.
2. Placement `confidence` ≥ threshold, or the folder came from a remembered purpose.
3. The destination isn't a **new top-level vault folder**.
4. If the batch has a purpose: `purpose_fit.fits == true`, and when it goes into a ledger, `amount` is present.
5. No existing note in the destination has the same `doc_date` + `from` + `title` (possible duplicate).
6. The ledger for this purpose, if any, has valid markers (§10.4).
7. No request failed, was refused, or failed validation.

If any of these fails, the document goes to **Needs review**, with the failed rule(s) listed as its reasons. The threshold defaults to 0.75 and can be set from 0.50 to 1.00.

## 10. Outputs

### 10.1 Filenames

- Base name: `YYYY-MM-DD <From> - <Title>`, or `YYYY-MM-DD <Title>` when there is no sender.
- The date is `doc_date`. If there is none, the scan date is used and `doc_date_estimated: true` is set.
- Stripped characters: `/ \ : * ? " < > | # ^ [ ]` and control characters.
- Whitespace is collapsed, and the name is capped at 120 characters at a word boundary.
- The PDF and note share the base name. On a collision, append ` (2)`, ` (3)`, and so on, to both.

### 10.2 Note

**Properties** (YAML front matter, fixed keys, optional ones left out when empty):

| Key | Always | Notes |
|---|---|---|
| `title`, `doc_type`, `doc_date`, `pages`, `scanned_at`, `source`, `tags`, `filing_confidence` | yes | `source: "[[<base>.pdf]]"`; `tags` always includes `scanned` |
| `from`, `doc_date_estimated`, `related` | when known | `related` is a list of wikilinks |
| `amount_due`, `due_date`, `amount`, `currency`, `account_last4` | when present | |
| `paid_on`, `amount_paid`, `payment_method`, `check_number` | when read from handwriting | |
| `scan_purpose`, `tax_year`, `tax_category`, `expense_category`, `ledger` | when the batch has a purpose | `ledger: "[[<ledger note>]]"` |

**Allowed values:**
- `doc_type`: bill, statement, receipt, tax, insurance, medical, legal, letter, notice, manual, handwritten-note, other
- `tax_category`: business-receipt, business-income, personal-deduction, medical, charitable, property-tax, other
- `expense_category`: office-supplies, travel, meals, software, equipment, utilities, professional-services, other

**Body:**
1. `# <Title>, <From>`
2. `![[<base>.pdf]]`
3. `## Summary`
4. `## Handwritten notes`: each raw quote with the value it became
5. `## Key facts`
6. `## Related`: wikilinks
7. `## Extracted text`: `### Page N` followed by that page's OCR lines

**Masking:** before anything is written to the note, account numbers, card numbers (13–19 digits that pass the Luhn check), and SSN patterns are reduced to their last 4 digits, both in Claude's fields and in the OCR text. The PDF is never altered.

### 10.3 Searchable PDF

- `PDFBuilder` creates one page per scanned page at its original size, drawing the page image and then each OCR line as invisible text (text rendering mode 3, i.e. text that is drawn invisibly but can still be selected and searched).
- Text is placed at its bounding box and horizontally scaled to fit.
- **Acceptance test:** `PDFDocument(url:).string` contains the OCR text of every page.

### 10.4 Ledger note (purpose batches only)

- **Location:** the purpose's folder. **Name:** from the purpose, e.g. `2026 Business Receipts.md`.
- **Created if missing**, with front matter `type: ledger`, `scan_purpose`, `tax_year`, a heading, and a managed section:
  ```markdown
  <!-- auto-scanner:ledger:start -->
  | Date | From | Amount | Category | Document |
  |---|---|---|---|---|
  | 2026-09-02 | Staples | 84.17 USD | office-supplies | [[2026-09-02 Staples - Receipt]] |
  | **Total** |  | **84.17 USD** |  |  |
  <!-- auto-scanner:ledger:end -->
  ```
- **Update procedure**, run one at a time per ledger:
  1. Require exactly one start marker and one end marker.
  2. Parse the rows, keyed by the document link. Any row that won't parse sends the document to review.
  3. Insert the row, or update it if the key already exists.
  4. Sort rows by date.
  5. Recalculate Total. If the ledger mixes currencies, send the document to review.
  6. Write the file safely.
- **Scope:** only the managed section is rewritten; anything outside it is left untouched.
- **Retrying:** because the update keys on the document link, running it again after a failure produces the same ledger. A retry after "note written, ledger failed" updates only the ledger.

### 10.5 Filing order and safety

For each document, filing runs in this order:
1. Create `new_subfolder` if needed.
2. Write the PDF to a temp file in the destination folder, then move it into place.
3. Write the note the same way.
4. Update the ledger.
5. Record events.

When every document in a batch is filed, the raw batch folder moves to `staging/_done/<batch-id>/`. Documents that are still in review keep their batch folder in staging.

## 11. Purposes

- The purpose text is trimmed, and its normalized form (lowercase, collapsed whitespace) is the key.
- The first successful filing for a purpose, whether automatic or from review, stores `{purpose → folder, ledgerPath}`. Later batches with the same key skip Step 2 and use that folder. The purpose sheet shows this as "Same as last time for this purpose", with the ledger's row count and total.
- **Recent purposes:** the last 8 distinct ones, most recent first.

## 12. Persistence

- **Event log:** SwiftData, stored in `~/Library/Application Support/AutoScannerOrganizer/`.
  - `JobEvent { id, batchID, documentID?, at, kind, payload(JSON) }` is append-only.
  - Batch and document status, and the History list, are derived from events and never stored separately.
  - **Event kinds:** `scanStarted`, `pageScanned`, `scanCompleted`, `scanInterrupted`, `batchAdopted`, `ocrCompleted`, `stackRead`, `placementDecided`, `needsReview`, `reviewResolved`, `folderCreated`, `pdfWritten`, `noteWritten`, `ledgerUpdated`, `rawArchived`, `stepFailed`, `retryRequested`.
- **Other SwiftData records:** `PurposeMapping`.
- **Settings:** UserDefaults holds staging path, vault path, model ID, threshold, default scanner ID, source, dpi, color, and duplex.
- **Secrets:** the API key lives in the Keychain (generic password, service `AutoScannerOrganizer.anthropic`).
- **Logs** (`os.Logger`) never contain the API key, page images, or document text.

## 13. Error handling

| Condition | Behavior |
|---|---|
| 429 / 5xx / network | 3 retries with backoff, then **Failed**. Retry resumes at the failed step. |
| 400 / schema validation failure (after 1 corrective retry) | **Failed** or **Needs review** with the reason. |
| Refusal | **Needs review** with the category. |
| Scanner jam / disconnect | Pages so far are kept. Choice of *continue scanning* or *process N pages*. |
| Vault write failure (iCloud placeholder, permissions, disk) | **Failed** with the reason, and Retry. No partial files are left, because writes go to a temp file first. |
| Possible duplicate | **Needs review** with a link to the existing note. |
| Chosen folder missing at filing time | **Needs review** again. |
| Ledger markers invalid / unparseable rows / mixed currency | **Needs review**. The ledger is never rewritten by guessing. |
| App quit or crash mid-job | On launch, resumes from the last completed event. |

## 14. Security and privacy

- **Data sent to Anthropic:** page images, OCR text, the vault folder index, and the first 4,000 characters of each note Claude asks to read. Nothing else leaves the Mac.
- **File access:** reads and writes happen only inside the configured staging and vault folders. Tool paths are resolved (including symlinks) and checked against the vault root.
- The app runs outside the App Store sandbox, uses the hardened runtime, and is signed locally.
- **Secrets:** Keychain only. No `.env` files, and no secrets in the repo.

## 15. Testing (TDD)

The existing test suite must be green before new work starts. Each feature starts from a failing test.

- **Unit tests** (Swift Testing, with fakes for every protocol) cover:
  - Decisions rules, as a table of cases
  - filename rules and masking
  - `batch.json` parsing
  - watcher readiness
  - Analyzer request building and response validation, using recorded fixtures
  - Step 2 tool path validation, including traversal attempts
  - purpose mapping
  - status derived from the event log
  - resume after restart
- **Integration tests** (temp directories, real frameworks):
  - `PDFBuilder` output contains the OCR text
  - `NoteWriter` and `LedgerWriter` output match golden files
  - updating a ledger twice for the same document gives the same result
  - the ledger handles invalid markers
  - `Filing` against a temp vault handles collisions and new subfolders
  - Vision OCR recognizes a fixture page image
- **Live tests:** `make test-live` is opt-in. It sends a 3-document fixture stack to the configured model and checks the split and that the schema is valid.
- **Manual checklist** in `docs/guide/`: Canon feeder scan, duplex, jam recovery, network scanner discovery.
- **UI:** view models are unit-tested, and the screens are checked against the mockup canvas with screenshots.

## 16. Tooling and layout

```
app/AutoScannerOrganizer/        SwiftUI app target (views, view models, adapters)
packages/ScanCore/Sources/…      modules from §4
packages/ScanCore/Tests/…        unit + integration tests, fixtures
project.yml                      XcodeGen spec → AutoScannerOrganizer.xcodeproj (generated, gitignored)
Makefile  Brewfile  .swiftlint.yml  .swiftformat
docs/adrs/  docs/guide/  docs/design/  docs/superpowers/specs/
```

**Makefile targets:**
- `init`: `brew bundle` (xcodegen, swiftlint, swiftformat) plus `xcodegen generate`
- `start`: build and open the app
- `stop`, `restart`
- `teardown`: remove build output and the generated project
- `test`: `swift test` for ScanCore, plus `xcodebuild test` for the app
- `test-live`
- `lint`, `format`
- `check`: lint plus test
- `seed`: creates `./.sandbox/Staging` and `./.sandbox/Vault` with fixture scans and a small vault tree

`migrate` is not applicable; the app migrates its own SwiftData store.

## 17. How the owner's standard defaults apply

| Default | This app | Reason |
|---|---|---|
| Docker for local dev | Not used | ImageCaptureCore, Vision, and PDFKit are macOS-only |
| `/administration` page | Settings window (tests for connection and scanner), plus History as the audit log | No web server |
| Administrator / Super Admin roles | None | Single user |
| Feature flags | Not in v1 | Nothing to roll out |
| Encrypted DB column for credentials | macOS Keychain | The platform's secret store |
| Business repo layout (`app/`, `business/`) | `app/`, `packages/`, `docs/` | Personal tool, no business ops |

## 18. Decision records

The ADRs are in `docs/adrs/`, each dated 2026-09-14:
- native SwiftUI app
- Apple Vision for OCR, Claude for understanding
- Claude Sonnet 5 as the default model
- staging folder as the pipeline boundary
- vault note, filename, and ledger format
- batch purpose memory
- running outside the App Store sandbox
- no Docker for local development
- XcodeGen for the Xcode project

## 19. Open items to confirm during implementation

- The API's per-request image limit, which sets the chunk size in §8.1.
- Whether the Canon MF4700 driver exposes duplex and ICA-based feeder document detection. If it doesn't, the Both sides toggle is disabled with an explanation.
- The actual staging folder path. The mockups use `~/Documents/Scans/Staging` as a sample; the owner picks the real one in Settings.

## 20. Amendments (2026-09-14, Milestone 1 execution)

- **§9:** rule 5 compares masked, whitespace-collapsed, lowercased titles and senders (an empty sender counts as none); a non-finite threshold counts as 1.0 and a non-finite confidence fails its rule. See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md).
- **§10.1:** an empty sanitized title becomes `Untitled`; the 120-character cap cuts at a word boundary only if that keeps at least 60 characters, else hard-cuts; names differing only in letter case collide. See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md).
- **§10.2:** the Filer masks Claude's title, sender, payment method, check number, and ledger name/title/sender before naming and rendering (also in the filename); `account_last4` keeps only its last 4 digits; dashless SSNs are masked only after a label; card numbers allow 0–3 separators. See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md).
- **§10.4:** the ledger lives in the filing's purpose folder (`LedgerFiling.folder`, validated before any write); CRLF is preserved; currency is trimmed, uppercased, and must be three letters A–Z; rows sort by date then document name; ledger-step failures carry the filing result for retry. See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md).
- **§10.5:** the PDF and note are create-only writes and a failed note write removes the new PDF, so the ledger is the only replacing write; dot-folder destinations and empty ledger names are rejected before any write; notes symlinked from outside the vault or not valid UTF-8 are skipped as duplicates and treated as invalid ledgers. See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md).
- **§12:** ScanCore types persist only through `ScanCoreJSON` (snake_case, sorted keys, non-finite numbers as strings, explicit `batch_id`/`document_id` keys). See [execution decisions](../../adrs/2026-09-14-filing-core-execution-decisions.md) and [ScanCoreJSON format](../../adrs/2026-09-14-scancorejson-persistence-format.md).
