# Use a watched staging folder as the boundary between scanning and processing

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The owner wants scans to land in a staging folder first, then be analyzed and filed into the vault. Scanning is local and fast. Analysis depends on the network and the Claude API, either of which can fail. Scans must never be lost.

## Options considered

1. **The scanner writes pages and `batch.json` into `staging/<batch-id>/`; a watcher picks up ready batches.**
   - Pros:
     - Scanning and analysis are separate steps.
     - Scans survive network and API failures.
     - Files dropped in by hand take the same path.
   - Cons:
     - Needs a readiness marker.
     - Needs a rule for when a dropped file has finished copying.
2. **Scanning hands pages to the analyzer in memory.**
   - Pros: simpler at first.
   - Cons:
     - A crash or API failure loses the scan.
     - No way to process files dropped in by hand.

## Decision

We chose **option 1**:
- A batch is ready when `batch.json` exists and isn't marked interrupted.
- Dropped files are adopted once their size stops changing for 5 seconds.
- Finished batches move to `staging/_done/`.
- Every step is recorded in an append-only job log, so processing resumes from the last completed step after a restart.

## Consequences

- Retry never requires rescanning.
- Staging can hold partial, interrupted batches, which the UI has to handle (*continue scanning* or *process these N pages*).
- `_done/` grows until the owner cleans it up. Automatic cleanup is deferred.
- **Revisit if:** the owner wants scans from other devices, such as a phone, fed in through a different path.
