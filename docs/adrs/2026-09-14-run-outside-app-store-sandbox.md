# Run outside the App Store sandbox; sign locally

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The app reads and writes an Obsidian vault in `~/Library/Mobile Documents/iCloud~md~obsidian/…`, watches a staging folder the owner chooses, and talks to network scanners and the Anthropic API. It will be used on one Mac and not distributed.

## Options considered

1. **Not sandboxed, with hardened runtime and local signing.**
   - Pros:
     - Folder paths just work.
     - No entitlement or security-scoped bookmark plumbing.
     - Simplest to build and test.
   - Cons: no OS-enforced limit on file access.
2. **Sandboxed, with security-scoped bookmarks and device/network entitlements.**
   - Pros: the OS enforces file access limits, and it's ready for the App Store.
   - Cons:
     - More code, and bookmarks can go stale.
     - Extra friction for a tool nobody else will install.

## Decision

We chose **option 1**. The app enforces its own file boundary instead:
- it only reads and writes inside the configured staging and vault folders
- Claude's read-only tool paths are resolved (including symlinks) and checked against the vault root

## Consequences

- There's no App Store distribution path without extra work.
- File-access safety depends on the app's own path validation, which must be covered by tests, including traversal attempts.
- **Revisit if:** the app is shared with other people or distributed.
