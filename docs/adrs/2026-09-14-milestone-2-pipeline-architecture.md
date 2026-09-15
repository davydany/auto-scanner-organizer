# Milestone 2 pipeline architecture: adapter target, CLI runner, file-backed stores, resumable artifacts

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

Milestone 2 adds everything between a finished scan batch and a filed document:
- the staging watcher
- Apple Vision OCR
- the two Claude requests (read the stack, then file each document)
- read-only vault tools
- the batch processor that emits job events, retries, and resumes

The spec (§4) puts all logic in `ScanCore`, keeps outside dependencies behind protocols, and says concrete adapters live in the app target. The app target, however, only arrives in Milestone 3. The spec (§12) names SwiftData for the event log and purpose mappings, and the Keychain for the API key. Both are app-target concerns.

The owner wants to try the pipeline on real documents before the app exists. The spec (§13) requires that a batch resumes from its last completed step after a quit or crash without redoing OCR. That needs the step outputs persisted, not just the events.

## Options considered

1. **Framework adapters in a second library target of the same package, plus a command-line runner.** `ScanCore` stays pure (Foundation, CoreGraphics, CoreText, Synchronization). A new `ScanAdapters` target holds the Vision, ImageIO/PDFKit, URLSession, file-watching, and file-backed store adapters. An executable `scan-organizer` target wires them together.
   - Pros:
     - adapters are testable with `swift test` today
     - the Milestone 3 app reuses them unchanged
     - the owner can run the pipeline now
   - Cons: one more target than the spec's diagram shows.
2. **Adapters wait for the Milestone 3 app target; Milestone 2 ships logic only.**
   - Pros: matches the spec's §4 wording.
   - Cons:
     - nothing is runnable end to end until Milestone 3
     - OCR and HTTP code stay untested against real frameworks
3. **Put adapters directly in `ScanCore`.**
   - Pros: simplest layout.
   - Cons: every `ScanCore` test and consumer links Vision, URLSession, and CoreServices, which erodes the pure-core boundary the spec asks for.

For persistence before the app exists:

- **(a) Append-only JSON Lines event log and a JSON purpose store, written through `ScanCoreJSON`.**
  - Pros:
    - literally append-only
    - human-readable
    - dependency-free
  - Cons: no querying beyond a full read (acceptable for one owner's batches).
- **(b) SwiftData now.**
  - Cons: needs model macros and a container outside an app target, and brings forward Milestone 3 work.
- **(c) In-memory only.**
  - Cons: no resume across CLI runs, which contradicts spec §13.

## Decision

We chose **option 1 with (a)**.

- **Targets:** `packages/ScanCore` gains a `ScanAdapters` library and a `scan-organizer` executable (target `ScanOrganizerCLI`).
- **Live tests:** they sit in their own `LiveTests` target, gated by `SCANCORE_LIVE=1`.
- **Persistence:**
  - The event log is an append-only JSON Lines file.
  - Purpose mappings live in one JSON file.
  - Both live in a data directory (default `~/Library/Application Support/AutoScannerOrganizer/`) and are written through `ScanCoreJSON`.
  - Whether Milestone 3 keeps these stores or moves to SwiftData is decided in Milestone 3.
- **Resume artifacts:** each batch keeps its step outputs in a hidden `.scancore/` folder inside the batch folder, written through `ScanCoreJSON`:
  - OCR lines per page
  - the stack analysis
  - one placement per document

  The batch processor reads them back on resume instead of repeating OCR or Claude requests. The staging watcher ignores dot-folders, so these artifacts never look like batches.
- **API key:** the CLI reads it from the `ANTHROPIC_API_KEY` environment variable. The Keychain adapter stays in Milestone 3 (spec §14 requires the Keychain for the app).
- **Claude wire format:** request and response JSON uses its own encoder with explicit keys and sorted output (`ClaudeWireJSON`), not `ScanCoreJSON`. The API's snake_case names and JSON Schema documents must not pass through a key-conversion strategy, and byte-stable output keeps prompt-cache prefixes stable.
- **Read-stack chunk size (spec §19 open item):**
  - The API accepts 600 images per request for Sonnet 5 and Opus 5, and 100 for Haiku 4.5.
  - Once a request holds more than 20 images, a stricter per-image pixel limit applies and oversized images are rejected. That would cancel the 2576 px long edge.
  - So the read-stack step sends at most **20 pages per request**, in consecutive chunks.
  - A document split that falls on a chunk boundary goes to review (spec §8.1).
  - Each chunk is at most about 20 × 140 KB of base64, far below the 32 MB request limit.
- **Request shape:** no `thinking`, `effort`, or sampling parameters are sent, so one request shape works for all three models. Sonnet 5 and Opus 5 think adaptively by default, so `max_tokens` is sized generously (16,000 for reading a stack, 4,096 per placement turn). The placement tool loop echoes every assistant content block back verbatim, including thinking blocks.
- **Filing serialization:** one `BatchProcessor` actor per vault. The step from duplicate check to ledger update is synchronous actor-isolated code, so two batches can never interleave writes to the same folder or ledger.
- **Ledger note name:** the first placement for a purpose batch also proposes a Title Case ledger name (for example `2026 Business Receipts`), validated like a filename. If there is none, the sanitized purpose text is used. The purpose mapping then remembers it.
- **Dates in `ScanCoreJSON`:** dates are encoded as ISO 8601 (whole seconds), so `batch.json` and the event log stay human-readable. Nothing was persisted with the previous default, so there is no migration.
- **Review split editing:** editing page splits during review is deferred to Milestone 3, where the review screen exists. Milestone 2's review resolution covers folder, subfolder, title, date, sender, amount, and currency choices.

## Consequences

- `ScanCore` tests stay fast and framework-free.
- `ScanAdapters` tests exercise real Vision, ImageIO, PDFKit, and URLSession (with a stubbed `URLProtocol`, never the network).
- The owner can run `scan-organizer` against a real staging folder and vault once an API key is set. Its behavior matches what the Milestone 3 app will do, because the app will call the same batch processor.
- The event log file grows without bound. Compaction or rotation is deferred until it matters.
- A crash mid-append can leave a partial last line in the event log. The store ignores an undecodable final line, so no completed event is lost.
- The spec's §4 and §12 wording is superseded for Milestone 2 by this record, and spec §20 gains a Milestone 2 amendment when the milestone lands.
- Revisit if the Milestone 3 app needs querying or syncing that the flat files can't serve, or if SwiftData becomes necessary for the History screen.
