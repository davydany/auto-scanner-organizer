# No Docker for local development; Makefile drives the native toolchain

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The owner's standard is Docker plus a Makefile for local development. This app depends on ImageCaptureCore, Vision, and PDFKit, which exist only on macOS and can't run in Linux containers. There are no server-side services to containerize.

## Options considered

1. **Native toolchain (Xcode, SwiftPM) driven by a Makefile** with the standard targets.
   - Pros: works with the frameworks the app needs.
   - Cons: breaks the owner's usual Docker convention.
2. **Docker for the platform-independent parts only.**
   - Pros: partly follows the convention.
   - Cons: two dev environments, and the core pipeline still can't be tested in them.

## Decision

We chose **option 1**:
- **Brewfile:** installs the tools (XcodeGen, SwiftLint, SwiftFormat).
- **Makefile targets:** `init`, `start`, `stop`, `restart`, `teardown`, `test`, `test-live`, `lint`, `format`, `check`, `seed`. `seed` creates a sandbox staging folder and sandbox vault in `.sandbox/`, so development never touches the real vault. `migrate` is not applicable; the app migrates its own SwiftData store.

## Consequences

- Development and CI need macOS runners.
- The Makefile contract still matches the owner's other projects, so the commands feel familiar.
- **Revisit if:** a server-side component is added, such as a shared processing service.
