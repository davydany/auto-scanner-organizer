# Vault output: searchable PDF + Markdown note with fixed properties, date-first filenames, managed ledgers

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

Filed documents must be easy to find later with an LLM or Obsidian search. The owner requires a searchable PDF. Once notes exist in the vault, their format is expensive to change, because every existing note would need rewriting. Tax-related batches need a running log so the owner can review a year's receipts in one place.

## Options considered

1. **Searchable PDF + Markdown note** next to it. The note has fixed YAML properties, a summary, the handwritten notes, and the full extracted text.
   - Pros: Obsidian, Dataview, and any LLM tool can read the note directly.
   - Cons: two files per document.
2. **Searchable PDF only**, with metadata stored in the PDF's own fields.
   - Pros: tidier folders.
   - Cons: most LLM tools and Obsidian search don't read text inside PDFs well.
3. **Markdown note only**, with page images embedded.
   - Pros: one file.
   - Cons: no searchable PDF, which the owner requires.

Ledger options:
- **(a)** a ledger note per purpose, with rows the app upserts inside a managed section
- **(b)** properties only, with the owner running their own queries
- **(c)** no purpose-based placement at all

## Decision

We chose **option 1** and ledger **(a)**:
- **Filenames:** `YYYY-MM-DD <From> - <Title>`, dated by the document's own date. The PDF and note share one base name.
- **Note properties:** a fixed set of keys, with `doc_type`, `tax_category`, and `expense_category` limited to allowed lists (see the spec, §10.2).
- **Sensitive numbers:** masked to their last 4 digits in the note. The PDF is left unaltered.
- **Ledger:** one note per purpose. The app rewrites only the section between `<!-- auto-scanner:ledger:start/end -->`, upserts rows keyed by the document link, and recalculates the total. If anything in that section looks unexpected, the document goes to review instead of the app guessing.

## Consequences

- Notes can be queried consistently, and an LLM can rely on the property names.
- Changing property names later means migrating existing notes. That's a reason to keep the schema small and change it deliberately.
- If the owner edits inside the ledger's managed section in a way the app can't parse, filing stops for that ledger until it's fixed.
- The note's text is masked while the PDF isn't, so searching the vault for a full account number finds only the PDF.
- **Revisit if:** the owner's vault conventions change, for example to a different property naming style or folder-level index notes.
