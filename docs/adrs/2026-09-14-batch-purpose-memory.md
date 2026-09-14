# Optional batch purpose, remembered as a fixed destination

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The owner often scans for a specific purpose, such as receipts for the 2026 tax year under business receipts. Documents from the same purpose should always land in the same folder and ledger. They shouldn't depend on Claude deciding the placement again for every batch.

## Options considered

1. **Ask for an optional purpose at Auto Scan.** The first filing for a purpose stores `purpose → folder + ledger`, and later batches reuse it without a placement request.
   - Pros:
     - Consistent destinations.
     - Fewer Claude calls.
     - Easy to predict.
   - Cons:
     - The first placement for a purpose sets the destination.
     - Wording variants of the same purpose create separate mappings.
2. **Pass the purpose as a hint only, deciding placement every time.**
   - Pros: flexible.
   - Cons: similar batches may scatter across folders.
3. **A predefined list of purposes managed in Settings.**
   - Pros: tidy.
   - Cons: setup work up front, and the owner wanted to just type one.

## Decision

We chose **option 1**:
- The purpose key is the trimmed text in lowercase with whitespace collapsed.
- Recent purposes appear as chips on the purpose sheet, so reusing the exact same wording takes one click.
- Claude still checks each document against the purpose. Documents that don't fit go to review.

## Consequences

- The purpose sheet can show where the batch will go ("Same as last time for this purpose") before scanning starts.
- A wrong first placement persists until the mapping is edited. A UI for editing mappings is a likely follow-up, not in v1.
- Setting a purpose on files dropped in by hand is deferred.
- **Revisit if:** near-duplicate purpose wordings become common (then match them loosely), or the owner wants to manage purposes in Settings.
