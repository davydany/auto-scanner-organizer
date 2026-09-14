# Filing core: decisions made while executing Milestone 1

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (implementation and review)

## Context

Milestone 1 built the `ScanCore` filing core from the approved spec (`docs/superpowers/specs/2026-09-14-auto-scanner-organizer-design.md`). Task reviews and the final whole-branch review found cases the spec doesn't settle: empty or very long titles, names that differ only by letter case on case-insensitive volumes, sensitive numbers inside Claude's titles, ledger failures that aren't parse errors, hand-edited or symlinked vault notes, and non-finite numbers. Once notes exist in the owner's vault, these choices are expensive to change. So each one is recorded here, and the spec's §20 Amendments points to this ADR.

Related: [ScanCoreJSON as the single JSON persistence format](2026-09-14-scancorejson-persistence-format.md).

## Options considered

For each decision, the realistic alternative was one of these:
- **Follow the spec text literally.** Examples: always cut at a word boundary, compare duplicates exactly, write the ledger beside the document. Each of these either lost data (a truncated title, an overwritten PDF) or split a purpose's ledger.
- **Guess or repair.** Examples: normalize a whole ledger file to LF, default a missing currency, fill in an empty ledger name. This silently rewrites owner content, which the spec forbids for ledgers.
- **Fail safe.** Reject the input before any write, or send the document to review with a reason. This is the option chosen throughout, because the spec's success criterion is that nothing is silently misfiled or lost.

## Decision

### Filename fallbacks (§10.1)
- A title that sanitizes to empty becomes `Untitled`, so the name keeps the `YYYY-MM-DD <From> - <Title>` shape with no dangling separator.
- The 120-character cap cuts at the last space only when that keeps at least 60 characters. Otherwise it hard-cuts at 120. Trailing ` -` is always trimmed.
- Collision suffixes (` (2)`, ` (3)`, …) treat an existing `.pdf` or `.md` whose name differs only in letter case as taken. The default macOS and iCloud Drive volumes are case-insensitive.

### Duplicate matching (§9 rule 5)
- Both the candidate's `title`/`from` and each note's front-matter values are compared after the same normalization: mask sensitive numbers, collapse every run of whitespace to one space and trim, then lowercase.
- A sender that is empty after normalization counts as no sender, on both sides. A nil sender matches only a note without one.
- Ledger notes (`type: ledger`) are never duplicate candidates.

### Masking at the Filer boundary (§10.2)
- `Filer.file` masks Claude's fields once, before building the base name and rendering: `title`, `from`, and each handwritten `payment_method` and `check_number`. It also masks the ledger filing's name, title, and sender.
- `account_last4` keeps only its last 4 ASCII digits and is left out when it has none.
- Related note names stay unmasked, because they must match existing vault notes. NoteWriter keeps masking the summary, handwriting quotes, and page text.
- **SSNs:** `123-45-6789` and `123 45 6789` are always masked. A dashless 9-digit number is masked only right after an SSN, Social Security, TIN, or Taxpayer ID label.
- **Card numbers:** 13–19 digits that pass Luhn, with 0–3 separator characters (space or `-`) allowed between digits.

### Create-only document writes (§10.5, §13)
- The PDF and note are written with `FileSystem.createNewFile`. It writes a hidden `.<UUID>.tmp` file in the destination folder, then moves it into place, and the move refuses an existing destination. A filed document never replaces a file, even one a stale listing missed.
- If the note write fails, the Filer removes the PDF it just created and rethrows. A newly created subfolder may remain.
- The ledger note is the only replacing write (a temp file, then an atomic rename).

### Ledger placement and format (§10.4)
- `LedgerFiling.folder` is the purpose's vault-relative folder, and the ledger note is created or updated there. The Filer resolves the folder through `VaultPathGuard` before any write. After creating the document's subfolder, it requires the folder to be an existing directory, and otherwise throws `folderMissing`. The note's link stays `[[<ledger name>]]`.
- A ledger that uses CRLF keeps CRLF: parse detects `\r\n` and render re-emits it. New ledgers use LF. A file with mixed endings fails safe as `markersMissing`.
- Currency is trimmed and uppercased, and must be exactly three letters A–Z, or `upsert` throws `invalidCurrency` before any row changes. `usd` and `USD` are the same currency.
- Rows sort by date, then by document note name, so the order is deterministic.

### Fail-safe on non-finite numbers (§9)
- A non-finite auto-file threshold, whether passed to `FilingDecider` or stored in `AppSettings`, counts as the upper bound of 1.0.
- A non-finite split or placement confidence fails its rule, so the document goes to review with the raw value in the reason.

### Hidden folders and empty ledger names (§10.5)
- Any `/`-separated component that starts with `.` in the destination folder or the ledger folder is rejected with `hiddenFolder` before anything is resolved or written. `.` and `..` are path navigation and remain `VaultPathGuard`'s concern. A dot-prefixed `new_subfolder` keeps its existing `invalidSubfolder` error.
- A ledger name that sanitizes to empty (e.g. `???`) is rejected with `invalidLedgerName` before any write, instead of producing a hidden `.md` file and a `[[]]` link.

### Symlink-safe reads and non-UTF-8 notes (§14)
- Directory listings don't resolve symlinks. So `findDuplicate` skips any note whose canonical location is outside the vault. `ledgerIsValid` returns false, and `updateLedger` throws `markersMissing`, for a ledger note that resolves outside the vault.
- Notes are decoded with the failable `String(data:encoding: .utf8)`. Non-UTF-8 notes are skipped as duplicate candidates, and a non-UTF-8 ledger is treated as invalid (sent to review).

### LedgerFailure wrapping for retries (§10.4 "Retrying")
- `FilingError.ledgerUpdateFailed(LedgerFailure, result:)` wraps every error from the ledger step: `.ledger(LedgerError)` for parse, marker, and currency problems, and `.io(String)` for anything else, such as a failed read or write. The caller always keeps the `FilingResult` of the document already written.
- A retry calls `Filer.updateLedger` with that result's base name and the ledger folder, and never re-runs `Filer.file` (which would file a ` (2)` copy). `updateLedger` masks the filing itself, so a retry with the caller's unmasked values reaches the same ledger note.

## Consequences

- Nothing in the filing core overwrites or deletes an owner file. The trade-off is that more documents go to review: titles differing only by case, hidden destinations, invalid currencies, and hand-edited or symlinked notes.
- A title that legitimately contains a long labeled number shows it masked in the filename and note. The PDF keeps the original.
- Milestone 2 callers must always supply `LedgerFiling.folder`: the purpose's folder, which for a purpose's first batch is the first document's filing folder. They must also handle `hiddenFolder`, `invalidLedgerName`, and `LedgerFailure`.
- Known edge case: masking runs before line breaks are folded, so a card or account number that Claude splits across a line break inside a title is not masked.
- **Revisit if:** the owner files onto a case-sensitive volume and wants case-distinct names, wants dot-folders as destinations, or a ledger needs to hold multiple currencies.
