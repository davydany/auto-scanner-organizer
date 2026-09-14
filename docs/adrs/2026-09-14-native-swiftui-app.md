# Build the app as a native SwiftUI Mac app

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** David (owner), Claude (design partner)

## Context

The app has to list the scanners on the Mac, including a network Canon MF4700 Series, and scan from the document feeder when the owner presses **Auto Scan**. It then does OCR, analyzes pages with Claude, and files searchable PDFs and Markdown notes into an Obsidian vault on iCloud Drive. It's a personal tool for one Mac. Xcode 26.6 and Swift 6.3 are installed.

## Options considered

1. **All-native SwiftUI app.**
   - Pros:
     - ImageCaptureCore (scanners), Vision (OCR), and PDFKit (searchable PDFs) are built in.
     - Only one language and one runtime.
     - Nothing extra to install.
   - Cons:
     - All logic is in Swift.
     - Changing prompts means rebuilding the app.
2. **Swift app that only scans, plus a Python worker** (ocrmypdf, Anthropic Python SDK).
   - Pros:
     - Prompts are faster to iterate.
     - There's an official Anthropic SDK.
   - Cons:
     - Two runtimes.
     - Bundling Python, Tesseract, and ocrmypdf into a Mac app is painful.
     - Tesseract handles handwriting worse than Vision.
3. **Folder-watcher menu-bar app only**, with scanning done in Canon's own software.
   - Pros: least code.
   - Cons: loses the in-app scanner list and the Auto Scan button, both of which were explicit requirements.

## Decision

We chose **option 1, a native SwiftUI app**. It's the only option that meets the scanner requirements without a second runtime, and Apple's frameworks cover scanning, OCR, and PDF output directly. All logic lives in a local Swift package, `ScanCore`, behind protocols, so it can be unit-tested without hardware.

## Consequences

- **Easier:**
  - Hardware access.
  - Packaging.
  - A single toolchain.
  - A native look and feel (macOS 26 glass styling fits the owner's design system).
- **Harder:**
  - There's no official Anthropic Swift SDK, so the app calls the Messages API over HTTP and must follow API changes itself (see the spec, §8.1).
- **Locked in:** macOS only.
- **Revisit if:** the app needs to run on another OS or be driven headless from a server.
