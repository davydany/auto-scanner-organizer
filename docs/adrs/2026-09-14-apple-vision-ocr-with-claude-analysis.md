# Use Apple Vision for OCR and Claude for understanding

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

Filed PDFs must be **searchable**, which needs an invisible text layer with every word placed at its position on the page. The app also has to:
- read handwritten annotations such as "Paid 9/2, ck #2217"
- split mixed stacks into separate documents
- classify documents, name them, and choose a vault folder

The owner suggested a Claude model, possibly Haiku, "whichever is best for OCR".

## Options considered

1. **Vision OCR for the text layer, Claude for everything that needs understanding.**
   - Pros:
     - Vision is on-device, free, and returns bounding boxes.
     - Claude handles handwriting, splitting, and judgment well.
   - Cons: two systems to combine.
2. **Claude only**, transcribing text and positions.
   - Pros: one system.
   - Cons:
     - Claude doesn't reliably return per-word coordinates, so there's no dependable text layer.
     - It pays output tokens for full transcriptions.
3. **Vision only**, with rules for naming and filing.
   - Pros: free and offline.
   - Cons: can't reliably split stacks, interpret handwriting, or choose folders.

## Decision

We chose **option 1**:
- **Vision** (`VNRecognizeTextRequest`, accurate mode) produces the positioned text for the PDF layer and the `Extracted text` section of the note.
- **Claude** receives the page images plus the Vision text and returns structured JSON for splits, fields, handwriting, and placement.

## Consequences

- The searchable text layer doesn't depend on the network or on which model is chosen.
- Claude's output stays small: structured fields, not full transcriptions.
- The note's extracted text is Vision's reading. Handwriting that Vision misreads shows up correctly in Claude's handwriting fields but may be garbled in the raw text.
- Page images and OCR text are sent to the Anthropic API. This is a known privacy trade-off, documented in the spec (§14).
- **Revisit if:** Claude reliably provides word coordinates, or Vision's handwriting accuracy gets good enough to drop Claude from the reading step.
