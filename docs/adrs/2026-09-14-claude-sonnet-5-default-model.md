# Default to Claude Sonnet 5, selectable in Settings

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner)

## Context

The model reads handwriting, splits stacks, and picks folders. Mistakes mean misfiled documents, or more trips to the review queue. Volume is personal: roughly a few hundred pages a month. Current API pricing per 1M tokens (input / output):

| Model | Input | Output |
|---|---|---|
| Haiku 4.5 | $1 | $5 |
| Sonnet 5 | $2 | $10 |
| Opus 5 | $5 | $25 |

Sonnet 5 and Opus 5 accept images up to 2576 px on the long edge; Haiku 4.5 is capped at 1568 px. All three support structured outputs.

## Options considered

1. **Opus 5.** Best at handwriting and judgment, at roughly 4–6¢ per page. Slowest.
2. **Sonnet 5.** Close to Opus on printed documents, with full-resolution images, at roughly 2¢ per page.
3. **Haiku 4.5.** Cheapest (about 0.5–1¢ per page), but lower image resolution means more misreads of small print and handwriting.

## Decision

The owner chose **Claude Sonnet 5** (`claude-sonnet-5`) as the default. Settings lets the owner switch to `claude-opus-5` or `claude-haiku-4-5` at any time, and each batch's history records the model it used.

## Consequences

- The app builds each request according to the selected model: image size cap, thinking settings, and refusal handling.
- Per-page cost estimates shown in Settings must stay in line with the recorded usage.
- **Revisit if:** the review queue fills with misread handwriting (move to Opus 5), or costs matter more than accuracy (move to Haiku 4.5). Base the change on the recorded usage and review rates.
