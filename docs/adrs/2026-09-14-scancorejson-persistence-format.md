# ScanCoreJSON is the single JSON format for persisting ScanCore types

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (implementation and review)

## Context

ScanCore's `Codable` types are decoded from Claude's responses and persisted by the app. Examples: `DocumentAnalysis`, `Placement`, `ReviewReason`, `JobEvent`, and `AppSettings`. Persisted JSON (event payloads, settings in UserDefaults) outlives the code that wrote it, so its key names and number encoding are hard to change later.

Milestone 1 surfaced three concrete problems with ad-hoc encoders:
- The fail-safe rules deliberately keep non-finite values: a `ReviewReason` carries a NaN or infinite confidence, and a corrupted threshold can be NaN. A default `JSONEncoder` throws `EncodingError.invalidValue` on them, exactly on the fail-safe path.
- `convertToSnakeCase` turns `batchID` into `batch_id`, but `convertFromSnakeCase` turns `batch_id` back into `batchId`. Without explicit keys, every persisted `JobEvent` would fail to decode.
- Claude's API uses snake_case, while Swift properties are camelCase.

## Options considered

1. **A bare `JSONEncoder`/`JSONDecoder` at each call site**, configured locally.
   - Pros: no shared code.
   - Cons: every writer must remember the same settings. One that forgets throws on NaN or writes camelCase keys that readers can't decode.
2. **Hand-written `Codable` per type**, encoding non-finite numbers and keys manually.
   - Pros: explicit.
   - Cons: repetitive, easy to get wrong, and the same problem gets fixed once per type.
3. **One shared configuration, `ScanCoreJSON.encoder()` / `ScanCoreJSON.decoder()`**, used for all persistence and for decoding Claude's responses.
   - Pros: consistent everywhere.
   - Cons: a writer that bypasses it still breaks.

## Decision

We chose **option 3**. `ScanCoreJSON` is the only JSON format for ScanCore types:
- **Keys:** snake_case on the wire (`convertToSnakeCase` / `convertFromSnakeCase`), camelCase in Swift.
- **Sorted keys** (`.sortedKeys`), so the same value always encodes to the same bytes. That keeps stored payloads, diffs, and tests deterministic.
- **Non-finite numbers** encode as the strings `"NaN"`, `"Infinity"`, and `"-Infinity"`, and the decoder accepts the same strings.
- **Acronym-suffixed properties get explicit `CodingKeys`.** For example, `JobEvent` maps `batchID = "batchId"` and `documentID = "documentId"`, so the wire keys are `batch_id` and `document_id` and they round-trip.
- **A bare `JSONEncoder`/`JSONDecoder` is not allowed** for ScanCore types. It throws on the non-finite values that the fail-safe rules keep, and its camelCase, unsorted output doesn't match data written through `ScanCoreJSON`.

## Consequences

- Persisting a `ReviewReason` with a NaN confidence, or settings with a NaN threshold, no longer throws. Decoding them keeps the fail-safe behavior: the document goes to review, and the threshold counts as 1.0.
- The decoder also accepts `"NaN"`/`"Infinity"` in Double fields of Claude's responses. This is safe: non-finite confidences fail their decision rules, and money fields are `Decimal`, which this strategy doesn't affect.
- Dictionary payload keys (e.g. `JobEvent.payload: [String: String]`) are not rewritten by the snake_case strategies.
- Every new property whose name ends in an acronym (`…ID`, `…URL`) needs an explicit `CodingKey`, with a round-trip test through `ScanCoreJSON`.
- Milestone 2 event payloads, and any other persistence of ScanCore types, must go through `ScanCoreJSON`.
- **Revisit if:** persisted data moves to a non-JSON store, or an external consumer needs a different JSON shape.
