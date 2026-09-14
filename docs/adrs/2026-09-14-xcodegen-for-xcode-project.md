# Generate the Xcode project with XcodeGen; keep logic in a local Swift package

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The app is built and tested from the command line, by Claude and by the Makefile, as well as in Xcode. Hand-maintained `.xcodeproj` files are hard to diff and merge, and awkward to create without the Xcode GUI. The design keeps all logic testable with `swift test`, independent of the app target.

## Options considered

1. **XcodeGen `project.yml`, with the generated `.xcodeproj` gitignored**, plus a local `packages/ScanCore` Swift package.
   - Pros:
     - The project definition is readable and diffable.
     - The project can be recreated with one command.
     - Tests are fast via SwiftPM.
   - Cons: one extra tool, installed via Homebrew.
2. **A committed `.xcodeproj`**, plus the local package.
   - Pros: no extra tool.
   - Cons: noisy diffs, and fragile to create or edit from scripts.
3. **SwiftPM only**, building the `.app` bundle by hand.
   - Pros: no project file at all.
   - Cons: signing, entitlements, asset catalogs, and app bundling all become custom scripts.

## Decision

We chose **option 1**. `make init` runs `brew bundle` and then `xcodegen generate`. `ScanCore` holds all pipeline logic behind protocols. The app target holds only the SwiftUI views, view models, and concrete framework adapters.

## Consequences

- Contributors must run `make init` before opening the project in Xcode.
- Project settings changes go in `project.yml`, never in Xcode's UI, because regenerating overwrites them.
- **Revisit if:** XcodeGen stops keeping up with Xcode releases. The fallback is committing the generated project.
