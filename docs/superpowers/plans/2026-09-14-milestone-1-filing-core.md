# Milestone 1: Filing Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `ScanCore` Swift package's filing core. It takes a Claude analysis result, page images, and OCR lines, and produces the correct vault outputs: a searchable PDF, a Markdown note, and ledger rows. It also includes filing decisions, path safety, the job event log, purpose memory, and settings. Everything is unit- and integration-tested, and nothing needs a scanner, the network, or the real vault.

**Architecture:**
- A local SwiftPM package at `packages/ScanCore`, containing pure value types and small enums with static functions.
- Every outside dependency (file system, event store, purpose store, key-value store) sits behind a `Sendable` protocol, with in-memory or local implementations.
- The SwiftUI app, the scanner, OCR, and Claude come in Milestones 2 and 3.

**Tech Stack:** Swift 6.3 toolchain, SwiftPM (tools 6.2), Swift Testing, Foundation, CoreGraphics, CoreText, PDFKit (tests only), SwiftLint and SwiftFormat via Homebrew.

**Spec:** `docs/superpowers/specs/2026-09-14-auto-scanner-organizer-design.md`. Read §9 (decision rules), §10 (outputs), §11 (purposes), §12 (persistence), and §14 (security) before starting.

## Global Constraints

- **Package manifest:** starts with `// swift-tools-version: 6.2`, declares `platforms: [.macOS(.v26)]`, and uses Swift 6 language mode (strict concurrency). Every public type is `Sendable`.
- **Tests:** Swift Testing only (`import Testing`, `@Test`, `#expect`, `#require`). Run them with `swift test --package-path packages/ScanCore` from the repo root.
- **Dependencies:** `ScanCore` has no third-party runtime dependencies.
- **Lint:** `make lint` (SwiftLint `--strict`) must pass before each commit. No `try!`, no force casts.
- **Filename characters to strip:** `/ \ : * ? " < > | # ^ [ ]` and control characters. Names are capped at 120 characters, cut at a word boundary.
- **`doc_type` values:** `bill, statement, receipt, tax, insurance, medical, legal, letter, notice, manual, handwritten-note, other`
- **`tax_category` values:** `business-receipt, business-income, personal-deduction, medical, charitable, property-tax, other`
- **`expense_category` values:** `office-supplies, travel, meals, software, equipment, utilities, professional-services, other`
- **Ledger markers**, exactly: `<!-- auto-scanner:ledger:start -->` and `<!-- auto-scanner:ledger:end -->`
- **Auto-file threshold:** default `0.75`, clamped to `0.50...1.00`.
- **Branch:** `feat/m1-filing-core`, created in Task 1 from `design/auto-scanner-organizer-spec`.
- **Commits:** one per task. Every commit message ends with these two lines:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj
  ```
- **Review fix rounds** land as separate follow-up commits on top of the reviewed commits, never by amending or rewriting them. This supersedes "one per task" above: a task may span several commits.
- **Makefile recipe lines** must be indented with a TAB character, not spaces.

## File Structure

```
Brewfile                                   tool dependencies (xcodegen, swiftlint, swiftformat)
Makefile                                   init, test, lint, format, check, teardown
.swiftlint.yml, .swiftformat               lint/format config
packages/ScanCore/Package.swift
packages/ScanCore/Sources/ScanCore/
  ScanCore.swift                           module version marker
  Model/CalendarDay.swift                  YYYY-MM-DD value type
  Model/DocumentAnalysis.swift             enums + Claude step-1 result types
  Model/Placement.swift                    Claude step-2 result type
  Model/ScanCoreJSON.swift                 shared JSON decoder/encoder config
  Output/FilenameBuilder.swift             §10.1 filename rules + collisions
  Output/SensitiveNumberMasker.swift       §10.2 masking
  Output/Money.swift                       Decimal formatting
  Output/YAML.swift                        front-matter scalar formatting
  Output/NoteContent.swift                 input model for NoteWriter
  Output/NoteWriter.swift                  §10.2 note rendering
  Output/Ledger.swift                      §10.4 ledger parse/upsert/render
  Output/SearchablePDFBuilder.swift        §10.3 image + invisible text PDF
  Decisions/FilingDecider.swift            §9 rules
  Filing/FileSystem.swift                  FileSystem protocol + LocalFileSystem
  Filing/VaultPathGuard.swift              §14 containment checks
  Filing/FrontMatterReader.swift           reads existing notes' properties
  Filing/Filer.swift                       §10.5 filing order, duplicates, ledgers
  Jobs/JobEvent.swift                      event + kinds
  Jobs/EventStore.swift                    protocol + InMemoryEventStore
  Jobs/BatchProjection.swift               status derived from events
  Purposes/Purposes.swift                  PurposeKey, PurposeMapping, stores
  Settings/AppSettings.swift               settings model + repository
packages/ScanCore/Tests/ScanCoreTests/     one test file per source file (named <Source>Tests.swift)
```

---

### Task 1: Package scaffold and tooling

**Files:**
- Create: `Brewfile`, `Makefile`, `.swiftlint.yml`, `.swiftformat`
- Create: `packages/ScanCore/Package.swift`
- Create: `packages/ScanCore/Sources/ScanCore/ScanCore.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/ScanCoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: the `ScanCore` library target, the `ScanCoreTests` test target, and the `make init|test|lint|format|check|teardown` targets that every later task uses.

- [ ] **Step 1: Create the branch**

```bash
git checkout design/auto-scanner-organizer-spec
git checkout -b feat/m1-filing-core
```

- [ ] **Step 2: Write the package manifest**

`packages/ScanCore/Package.swift`:
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanCore", targets: ["ScanCore"]),
    ],
    targets: [
        .target(name: "ScanCore"),
        .testTarget(name: "ScanCoreTests", dependencies: ["ScanCore"]),
    ]
)
```

- [ ] **Step 3: Write the failing smoke test**

`packages/ScanCore/Tests/ScanCoreTests/ScanCoreTests.swift`:
```swift
import Testing
@testable import ScanCore

@Test func moduleVersionIsSet() {
    #expect(ScanCore.version == "0.1.0")
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --package-path packages/ScanCore`
Expected: build FAILS with `cannot find 'ScanCore' in scope`. The target has no sources yet, so SwiftPM may instead report that it has no source files; either failure counts.

- [ ] **Step 5: Add the module marker**

`packages/ScanCore/Sources/ScanCore/ScanCore.swift`:
```swift
/// Namespace marker for the ScanCore module.
public enum ScanCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --package-path packages/ScanCore`
Expected: `✔ Test moduleVersionIsSet() passed`

- [ ] **Step 7: Add the tooling files**

`Brewfile`:
```ruby
brew "xcodegen"
brew "swiftlint"
brew "swiftformat"
```

`Makefile` (recipe lines start with a TAB):
```make
SCANCORE := packages/ScanCore

.PHONY: init test lint format check teardown

init:
	brew bundle --file=Brewfile

test:
	swift test --package-path $(SCANCORE)

lint:
	swiftlint lint --strict

format:
	swiftformat $(SCANCORE)

check: lint test

teardown:
	rm -rf $(SCANCORE)/.build
```

`.swiftlint.yml`:
```yaml
included:
  - packages/ScanCore/Sources
  - packages/ScanCore/Tests
excluded:
  - packages/ScanCore/.build
disabled_rules:
  - trailing_comma
  - todo
  - nesting
  - vertical_parameter_alignment
line_length:
  warning: 180
  error: 240
function_parameter_count:
  warning: 14
  error: 16
cyclomatic_complexity:
  ignores_case_statements: true
identifier_name:
  min_length: 1
  max_length: 60
type_body_length:
  warning: 400
file_length:
  warning: 500
function_body_length:
  warning: 80
```

`.swiftformat`:
```
--swiftversion 6.2
--indent 4
--maxwidth 160
--wraparguments before-first
--disable redundantSelf,trailingCommas
```

- [ ] **Step 8: Install the tools and run lint and tests**

Run: `make init && make check`
Expected: `brew bundle` reports all dependencies satisfied, SwiftLint reports `Found 0 violations`, and the tests pass.

- [ ] **Step 9: Commit**

```bash
git add Brewfile Makefile .swiftlint.yml .swiftformat packages/ScanCore
git commit -m "chore(scancore): scaffold ScanCore package and dev tooling" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 2: Domain model (CalendarDay, analysis types, placement, JSON)

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Model/CalendarDay.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Model/DocumentAnalysis.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Model/Placement.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Model/ScanCoreJSON.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/CalendarDayTests.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/DocumentAnalysisTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct CalendarDay: Codable, Sendable, Hashable, Comparable, CustomStringConvertible`, with:
    - `init?(_ string: String)`
    - `init?(year: Int, month: Int, day: Int)`
    - `static func from(_ date: Date, timeZone: TimeZone) -> CalendarDay`
    - `description` renders as `"YYYY-MM-DD"`
  - `enum DocType`, `enum TaxCategory`, `enum ExpenseCategory`: `String` raw values, `Codable, Sendable, CaseIterable`.
  - `struct KeyFacts { amountDue: Decimal?, dueDate: CalendarDay?, amount: Decimal?, currency: String?, accountLast4: String? }`
  - `struct HandwrittenAnnotation { page: Int, rawText: String, paidOn: CalendarDay?, amountPaid: Decimal?, paymentMethod: String?, checkNumber: String? }`
  - `struct PurposeFit { fits: Bool, reason: String, taxYear: Int?, taxCategory: TaxCategory?, expenseCategory: ExpenseCategory? }`
  - `struct DocumentAnalysis { pages: [Int], splitConfidence: Double, docType: DocType, title: String, from: String?, docDate: CalendarDay?, summary: String, tags: [String], keyFacts: KeyFacts, handwritten: [HandwrittenAnnotation], purposeFit: PurposeFit? }`
  - `struct StackAnalysis { documents: [DocumentAnalysis] }`
  - `struct Placement { folder: String, newSubfolder: String?, relatedNotes: [String], confidence: Double, reason: String, alternatives: [PlacementAlternative] }`
  - `struct PlacementAlternative { folder: String, confidence: Double }`
  - `enum ScanCoreJSON { static func decoder() -> JSONDecoder; static func encoder() -> JSONEncoder }`, using snake_case keys.
  - All of these structs are `Codable, Sendable, Equatable`, with memberwise `public init`.

- [ ] **Step 1: Write the failing CalendarDay tests**

`packages/ScanCore/Tests/ScanCoreTests/CalendarDayTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct CalendarDayTests {
    @Test func parsesValidISODay() throws {
        let day = try #require(CalendarDay("2026-08-28"))
        #expect(day.year == 2026)
        #expect(day.month == 8)
        #expect(day.day == 28)
        #expect(day.description == "2026-08-28")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "26-08-28", "2026-8-28", "", "2026-08-28T00:00:00"])
    func rejectsInvalidStrings(_ input: String) {
        #expect(CalendarDay(input) == nil)
    }

    @Test func ordersChronologically() throws {
        let earlier = try #require(CalendarDay("2026-01-31"))
        let later = try #require(CalendarDay("2026-02-01"))
        #expect(earlier < later)
    }

    @Test func buildsFromDateInTimeZone() throws {
        // 2026-09-14T02:30:00Z is still Sept 13 in New York (UTC-4).
        let date = Date(timeIntervalSince1970: 1_789_353_000)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(CalendarDay.from(date, timeZone: newYork).description == "2026-09-13")
    }

    @Test func roundTripsThroughJSONAsString() throws {
        let day = try #require(CalendarDay("2026-09-02"))
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-09-02\"]")
        #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == [day])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter CalendarDayTests`
Expected: build FAILS with `cannot find 'CalendarDay' in scope`.

- [ ] **Step 3: Implement CalendarDay**

`packages/ScanCore/Sources/ScanCore/Model/CalendarDay.swift`:
```swift
import Foundation

/// A calendar date with no time or time zone, rendered as `YYYY-MM-DD`.
public struct CalendarDay: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day)
        guard year >= 1, components.isValidDate else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func from(_ date: Date, timeZone: TimeZone) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // Components from a real Date are always valid.
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDay(year: 1970, month: 1, day: 1)!
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let raw = try String(from: decoder)
        guard let parsed = CalendarDay(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected YYYY-MM-DD, got \(raw)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        try description.encode(to: encoder)
    }
}
```
Note: the `!` on the 1970 fallback is a literal known-valid date. If SwiftLint flags `force_unwrapping` (it's opt-in and not enabled in this config), replace it with a `private static let epoch` built from `DateComponents`.

- [ ] **Step 4: Run the CalendarDay tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter CalendarDayTests`
Expected: all 5 tests pass. The parameterized test reports 6 cases.

- [ ] **Step 5: Write the failing analysis-decoding tests**

`packages/ScanCore/Tests/ScanCoreTests/DocumentAnalysisTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct DocumentAnalysisTests {
    static let stackJSON = """
    {
      "documents": [
        {
          "pages": [1, 2],
          "split_confidence": 0.93,
          "doc_type": "bill",
          "title": "Electric Bill",
          "from": "Dominion Energy",
          "doc_date": "2026-08-28",
          "summary": "August electric bill.",
          "tags": ["utilities", "primary-residence"],
          "key_facts": { "amount_due": 142.18, "due_date": "2026-09-18", "account_last4": "4417" },
          "handwritten": [ { "page": 1, "raw_text": "Paid 9/2", "paid_on": "2026-09-02" } ],
          "purpose_fit": null
        },
        {
          "pages": [3],
          "split_confidence": 0.61,
          "doc_type": "handwritten-note",
          "title": "Gutter Cleaning Payment",
          "from": null,
          "doc_date": null,
          "summary": "Note about gutter cleaning.",
          "tags": [],
          "key_facts": {},
          "handwritten": [
            { "page": 3, "raw_text": "pd 9/3 ck #2217 $180", "paid_on": "2026-09-03",
              "amount_paid": 180.00, "payment_method": "check", "check_number": "2217" }
          ],
          "purpose_fit": { "fits": true, "reason": "Home expense", "tax_year": 2026,
                           "tax_category": "business-receipt", "expense_category": "professional-services" }
        }
      ]
    }
    """

    @Test func decodesStackAnalysisFromSnakeCaseJSON() throws {
        let stack = try ScanCoreJSON.decoder().decode(StackAnalysis.self, from: Data(Self.stackJSON.utf8))
        #expect(stack.documents.count == 2)

        let bill = stack.documents[0]
        #expect(bill.pages == [1, 2])
        #expect(bill.docType == .bill)
        #expect(bill.docDate == CalendarDay("2026-08-28"))
        #expect(bill.keyFacts.amountDue == Decimal(string: "142.18"))
        #expect(bill.keyFacts.accountLast4 == "4417")
        #expect(bill.handwritten.first?.paidOn == CalendarDay("2026-09-02"))
        #expect(bill.purposeFit == nil)

        let note = stack.documents[1]
        #expect(note.docType == .handwrittenNote)
        #expect(note.from == nil)
        #expect(note.handwritten.first?.checkNumber == "2217")
        #expect(note.purposeFit?.taxCategory == .businessReceipt)
        #expect(note.purposeFit?.expenseCategory == .professionalServices)
    }

    @Test func rejectsUnknownDocType() {
        let json = Self.stackJSON.replacingOccurrences(of: "\"bill\"", with: "\"invoice\"")
        #expect(throws: DecodingError.self) {
            try ScanCoreJSON.decoder().decode(StackAnalysis.self, from: Data(json.utf8))
        }
    }

    @Test func enumRawValuesMatchSpec() {
        #expect(DocType.allCases.map(\.rawValue) == [
            "bill", "statement", "receipt", "tax", "insurance", "medical", "legal",
            "letter", "notice", "manual", "handwritten-note", "other",
        ])
        #expect(TaxCategory.allCases.map(\.rawValue) == [
            "business-receipt", "business-income", "personal-deduction", "medical",
            "charitable", "property-tax", "other",
        ])
        #expect(ExpenseCategory.allCases.map(\.rawValue) == [
            "office-supplies", "travel", "meals", "software", "equipment",
            "utilities", "professional-services", "other",
        ])
    }

    @Test func decodesPlacement() throws {
        let json = """
        { "folder": "Personal/Properties/Primary Residence", "new_subfolder": "Utilities",
          "related_notes": ["Primary Residence"], "confidence": 0.91, "reason": "Utility bill for the home.",
          "alternatives": [ { "folder": "Personal/Finances", "confidence": 0.4 } ] }
        """
        let placement = try ScanCoreJSON.decoder().decode(Placement.self, from: Data(json.utf8))
        #expect(placement.newSubfolder == "Utilities")
        #expect(placement.relatedNotes == ["Primary Residence"])
        #expect(placement.alternatives == [PlacementAlternative(folder: "Personal/Finances", confidence: 0.4)])
    }
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter DocumentAnalysisTests`
Expected: build FAILS with `cannot find 'ScanCoreJSON' in scope`.

- [ ] **Step 7: Implement the model types**

`packages/ScanCore/Sources/ScanCore/Model/ScanCoreJSON.swift`:
```swift
import Foundation

/// Shared JSON configuration: snake_case keys on the wire, camelCase in Swift.
public enum ScanCoreJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
```

`packages/ScanCore/Sources/ScanCore/Model/DocumentAnalysis.swift`:
```swift
import Foundation

public enum DocType: String, Codable, Sendable, CaseIterable {
    case bill, statement, receipt, tax, insurance, medical, legal, letter, notice, manual
    case handwrittenNote = "handwritten-note"
    case other
}

public enum TaxCategory: String, Codable, Sendable, CaseIterable {
    case businessReceipt = "business-receipt"
    case businessIncome = "business-income"
    case personalDeduction = "personal-deduction"
    case medical
    case charitable
    case propertyTax = "property-tax"
    case other
}

public enum ExpenseCategory: String, Codable, Sendable, CaseIterable {
    case officeSupplies = "office-supplies"
    case travel, meals, software, equipment, utilities
    case professionalServices = "professional-services"
    case other
}

public struct KeyFacts: Codable, Sendable, Equatable {
    public var amountDue: Decimal?
    public var dueDate: CalendarDay?
    public var amount: Decimal?
    public var currency: String?
    public var accountLast4: String?

    public init(amountDue: Decimal? = nil, dueDate: CalendarDay? = nil, amount: Decimal? = nil,
                currency: String? = nil, accountLast4: String? = nil) {
        self.amountDue = amountDue
        self.dueDate = dueDate
        self.amount = amount
        self.currency = currency
        self.accountLast4 = accountLast4
    }
}

public struct HandwrittenAnnotation: Codable, Sendable, Equatable {
    public var page: Int
    public var rawText: String
    public var paidOn: CalendarDay?
    public var amountPaid: Decimal?
    public var paymentMethod: String?
    public var checkNumber: String?

    public init(page: Int, rawText: String, paidOn: CalendarDay? = nil, amountPaid: Decimal? = nil,
                paymentMethod: String? = nil, checkNumber: String? = nil) {
        self.page = page
        self.rawText = rawText
        self.paidOn = paidOn
        self.amountPaid = amountPaid
        self.paymentMethod = paymentMethod
        self.checkNumber = checkNumber
    }
}

public struct PurposeFit: Codable, Sendable, Equatable {
    public var fits: Bool
    public var reason: String
    public var taxYear: Int?
    public var taxCategory: TaxCategory?
    public var expenseCategory: ExpenseCategory?

    public init(fits: Bool, reason: String, taxYear: Int? = nil, taxCategory: TaxCategory? = nil,
                expenseCategory: ExpenseCategory? = nil) {
        self.fits = fits
        self.reason = reason
        self.taxYear = taxYear
        self.taxCategory = taxCategory
        self.expenseCategory = expenseCategory
    }
}

/// One document found by Claude's "read stack" step (spec §8.2).
public struct DocumentAnalysis: Codable, Sendable, Equatable {
    public var pages: [Int]
    public var splitConfidence: Double
    public var docType: DocType
    public var title: String
    public var from: String?
    public var docDate: CalendarDay?
    public var summary: String
    public var tags: [String]
    public var keyFacts: KeyFacts
    public var handwritten: [HandwrittenAnnotation]
    public var purposeFit: PurposeFit?

    public init(pages: [Int], splitConfidence: Double, docType: DocType, title: String, from: String? = nil,
                docDate: CalendarDay? = nil, summary: String, tags: [String] = [], keyFacts: KeyFacts = KeyFacts(),
                handwritten: [HandwrittenAnnotation] = [], purposeFit: PurposeFit? = nil) {
        self.pages = pages
        self.splitConfidence = splitConfidence
        self.docType = docType
        self.title = title
        self.from = from
        self.docDate = docDate
        self.summary = summary
        self.tags = tags
        self.keyFacts = keyFacts
        self.handwritten = handwritten
        self.purposeFit = purposeFit
    }
}

public struct StackAnalysis: Codable, Sendable, Equatable {
    public var documents: [DocumentAnalysis]

    public init(documents: [DocumentAnalysis]) {
        self.documents = documents
    }
}
```

`packages/ScanCore/Sources/ScanCore/Model/Placement.swift`:
```swift
import Foundation

public struct PlacementAlternative: Codable, Sendable, Equatable {
    public var folder: String
    public var confidence: Double

    public init(folder: String, confidence: Double) {
        self.folder = folder
        self.confidence = confidence
    }
}

/// Claude's "file document" answer (spec §8.3).
public struct Placement: Codable, Sendable, Equatable {
    public var folder: String
    public var newSubfolder: String?
    public var relatedNotes: [String]
    public var confidence: Double
    public var reason: String
    public var alternatives: [PlacementAlternative]

    public init(folder: String, newSubfolder: String? = nil, relatedNotes: [String] = [], confidence: Double,
                reason: String, alternatives: [PlacementAlternative] = []) {
        self.folder = folder
        self.newSubfolder = newSubfolder
        self.relatedNotes = relatedNotes
        self.confidence = confidence
        self.reason = reason
        self.alternatives = alternatives
    }
}
```

`KeyFacts` must decode from `{}` (all keys absent). Synthesized `Codable` does this for optionals. `tags` and `handwritten` are always present in Claude's schema, so they stay non-optional.

- [ ] **Step 8: Run all tests to verify they pass**

Run: `swift test --package-path packages/ScanCore`
Expected: all tests pass, including `decodesStackAnalysisFromSnakeCaseJSON` and `rejectsUnknownDocType`.

- [ ] **Step 9: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): add analysis domain model and CalendarDay" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 3: FilenameBuilder

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Output/FilenameBuilder.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/FilenameBuilderTests.swift`

**Interfaces:**
- Consumes: `CalendarDay` (Task 2).
- Produces: `enum FilenameBuilder`, with:
  - `static let maxLength = 120`
  - `static func sanitize(_ text: String) -> String`
  - `static func baseName(date: CalendarDay, from: String?, title: String) -> String`
  - `static func uniqueBaseName(_ base: String, existingFileNames: Set<String>) -> String`. `existingFileNames` holds the names of every file in the destination folder, e.g. `"x.pdf"`.

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/FilenameBuilderTests.swift`:
```swift
import Testing
@testable import ScanCore

struct FilenameBuilderTests {
    let day = CalendarDay("2026-08-28")!

    @Test func buildsDateFromTitle() {
        #expect(FilenameBuilder.baseName(date: day, from: "Dominion Energy", title: "Electric Bill")
            == "2026-08-28 Dominion Energy - Electric Bill")
    }

    @Test func omitsSenderWhenMissingOrBlank() {
        #expect(FilenameBuilder.baseName(date: day, from: nil, title: "Gutter Note") == "2026-08-28 Gutter Note")
        #expect(FilenameBuilder.baseName(date: day, from: "  ", title: "Gutter Note") == "2026-08-28 Gutter Note")
    }

    @Test func stripsForbiddenCharactersAndCollapsesWhitespace() {
        #expect(FilenameBuilder.sanitize("Q3/Q4: \"Final\" [draft] #2 ^x | a*b?<c>\\d") == "Q3Q4 Final draft 2 x abcd")
        #expect(FilenameBuilder.sanitize("Line one\nLine\ttwo   end") == "Line one Line two end")
    }

    @Test func truncatesAtWordBoundaryWithinLimit() {
        let title = String(repeating: "Word ", count: 40)
        let name = FilenameBuilder.baseName(date: day, from: "Sender", title: title)
        #expect(name.count <= FilenameBuilder.maxLength)
        #expect(name.hasPrefix("2026-08-28 Sender - Word"))
        #expect(!name.hasSuffix(" "))
        #expect(name.hasSuffix("Word"))
    }

    @Test func returnsBaseWhenNoCollision() {
        #expect(FilenameBuilder.uniqueBaseName("2026-08-28 A - B", existingFileNames: ["other.pdf"]) == "2026-08-28 A - B")
    }

    @Test func appendsCounterWhenPdfOrNoteExists() {
        let existing: Set<String> = ["2026-08-28 A - B.pdf", "2026-08-28 A - B (2).md"]
        #expect(FilenameBuilder.uniqueBaseName("2026-08-28 A - B", existingFileNames: existing) == "2026-08-28 A - B (3)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter FilenameBuilderTests`
Expected: build FAILS with `cannot find 'FilenameBuilder' in scope`.

- [ ] **Step 3: Implement**

`packages/ScanCore/Sources/ScanCore/Output/FilenameBuilder.swift`:
```swift
import Foundation

/// Filename rules from spec §10.1.
public enum FilenameBuilder {
    public static let maxLength = 120

    private static let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]

    public static func sanitize(_ text: String) -> String {
        var cleaned = ""
        for character in text {
            if character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                cleaned.append(" ")
            } else if !forbidden.contains(character) {
                cleaned.append(character)
            }
        }
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func baseName(date: CalendarDay, from: String?, title: String) -> String {
        let cleanTitle = sanitize(title)
        let cleanFrom = from.map(sanitize) ?? ""
        let name = cleanFrom.isEmpty ? "\(date) \(cleanTitle)" : "\(date) \(cleanFrom) - \(cleanTitle)"
        return truncate(name)
    }

    public static func uniqueBaseName(_ base: String, existingFileNames: Set<String>) -> String {
        func isTaken(_ candidate: String) -> Bool {
            existingFileNames.contains("\(candidate).pdf") || existingFileNames.contains("\(candidate).md")
        }
        guard isTaken(base) else { return base }
        var counter = 2
        while isTaken("\(base) (\(counter))") {
            counter += 1
        }
        return "\(base) (\(counter))"
    }

    private static func truncate(_ name: String) -> String {
        guard name.count > maxLength else { return name }
        let prefix = String(name.prefix(maxLength))
        let atWordBoundary = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        return atWordBoundary.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter FilenameBuilderTests`
Expected: all 6 tests pass.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): add filename rules and collision naming" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 4: SensitiveNumberMasker

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Output/SensitiveNumberMasker.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/SensitiveNumberMaskerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum SensitiveNumberMasker { static func mask(_ text: String) -> String }`. It masks:
  - SSNs: `123-45-6789` becomes `•••-••-6789`
  - card numbers of 13–19 digits that pass the Luhn check: becomes `•••• 1111`
  - account, member, policy, and routing numbers of 6+ digits that follow a label: becomes `Account number: ••••7890`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/SensitiveNumberMaskerTests.swift`:
```swift
import Testing
@testable import ScanCore

struct SensitiveNumberMaskerTests {
    @Test func masksSocialSecurityNumbers() {
        #expect(SensitiveNumberMasker.mask("SSN 123-45-6789 on file") == "SSN •••-••-6789 on file")
    }

    @Test func masksLuhnValidCardNumbers() {
        #expect(SensitiveNumberMasker.mask("Card 4111 1111 1111 1111 charged") == "Card •••• 1111 charged")
        #expect(SensitiveNumberMasker.mask("Card 4111-1111-1111-1111") == "Card •••• 1111")
        #expect(SensitiveNumberMasker.mask("4111111111111111") == "•••• 1111")
    }

    @Test func leavesLuhnInvalidLongNumbersAlone() {
        #expect(SensitiveNumberMasker.mask("Ref 4111 1111 1111 1112") == "Ref 4111 1111 1111 1112")
    }

    @Test func masksLabeledAccountNumbers() {
        #expect(SensitiveNumberMasker.mask("Account number: 1234567890") == "Account number: ••••7890")
        #expect(SensitiveNumberMasker.mask("Acct # 55-1234-99 due") == "Acct # ••••3499 due")
        #expect(SensitiveNumberMasker.mask("August bill, account number 9876543210.") == "August bill, account number ••••3210.")
    }

    @Test(arguments: [
        "Call 703-555-1234",
        "Amount due $142.18 by 2026-09-18",
        "pd 9/3 ck #2217 $180",
        "Policy renews 2026-10-01",
    ])
    func leavesOrdinaryNumbersAlone(_ text: String) {
        #expect(SensitiveNumberMasker.mask(text) == text)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter SensitiveNumberMaskerTests`
Expected: build FAILS with `cannot find 'SensitiveNumberMasker' in scope`.

- [ ] **Step 3: Implement**

`packages/ScanCore/Sources/ScanCore/Output/SensitiveNumberMasker.swift`:
```swift
import Foundation

/// Masks sensitive numbers in note text (spec §10.2). PDFs are never altered.
public enum SensitiveNumberMasker {
    public static func mask(_ text: String) -> String {
        maskLabeledAccountNumbers(maskCardNumbers(maskSocialSecurityNumbers(text)))
    }

    static func maskSocialSecurityNumbers(_ text: String) -> String {
        text.replacing(/\b\d{3}-\d{2}-(\d{4})\b/) { match in
            "•••-••-\(match.1)"
        }
    }

    static func maskCardNumbers(_ text: String) -> String {
        text.replacing(/\b(?:\d[ -]?){12,18}\d\b/) { match in
            let digits = String(match.0.filter(\.isNumber))
            guard (13...19).contains(digits.count), passesLuhn(digits) else { return String(match.0) }
            return "•••• \(digits.suffix(4))"
        }
    }

    static func maskLabeledAccountNumbers(_ text: String) -> String {
        text.replacing(/(?i)\b(acct|account|member|policy|routing)(\s*(?:no\.?|number|#))?\s*[:#]?\s*((?:\d[ -]?){5,}\d)/) { match in
            let number = match.3
            let digits = String(number.filter(\.isNumber))
            let label = String(match.0).dropLast(number.count)
            return "\(label)••••\(digits.suffix(4))"
        }
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }
}
```
If the Swift regex literal with `(?i)` fails to compile, use `.ignoresCase()` on a literal that omits `(?i)`: `/\b(acct|account|member|policy|routing).../.ignoresCase()`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter SensitiveNumberMaskerTests`
Expected: all tests pass. The parameterized test reports 4 cases.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): mask SSNs, card and account numbers in note text" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 5: NoteWriter (Money, YAML, NoteContent)

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Output/Money.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Output/YAML.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Output/NoteContent.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Output/NoteWriter.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/NoteWriterTests.swift`

**Interfaces:**
- Consumes:
  - `DocumentAnalysis`, `KeyFacts`, `HandwrittenAnnotation`, `CalendarDay` (Task 2)
  - `SensitiveNumberMasker.mask` (Task 4)
- Produces:
  - `enum Money { static func format(_ amount: Decimal) -> String }`: always 2 decimals, no grouping, `.` separator.
  - `enum YAML { static func string(_:) -> String; static func list(_:) -> String; static func wikilink(_:) -> String; static func confidence(_:) -> String }` (internal).
  - `struct NoteContent: Sendable, Equatable { baseName, analysis, docDate, docDateEstimated, scannedAt, timeZone, filingConfidence, relatedNotes, scanPurpose, ledgerNoteName, pageTexts }`, with a public init where `relatedNotes`, `scanPurpose`, and `ledgerNoteName` default to empty or nil.
  - `enum NoteWriter { static func render(_ note: NoteContent) -> String }`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/NoteWriterTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct NoteWriterTests {
    let newYork = TimeZone(identifier: "America/New_York")!
    // 2026-09-14T02:42:03Z == 2026-09-13T22:42:03-04:00
    let scannedAt = Date(timeIntervalSince1970: 1_789_353_723)

    @Test func rendersFullBillNote() {
        let analysis = DocumentAnalysis(
            pages: [1, 2], splitConfidence: 0.93, docType: .bill, title: "Electric Bill", from: "Dominion Energy",
            docDate: CalendarDay("2026-08-28"), summary: "August electric bill, account number 9876543210.",
            tags: ["utilities", "scanned"],
            keyFacts: KeyFacts(amountDue: Decimal(string: "142.18"), dueDate: CalendarDay("2026-09-18"), currency: "USD", accountLast4: "4417"),
            handwritten: [HandwrittenAnnotation(page: 1, rawText: "Paid 9/2", paidOn: CalendarDay("2026-09-02"))]
        )
        let note = NoteContent(
            baseName: "2026-08-28 Dominion Energy - Electric Bill", analysis: analysis, docDate: CalendarDay("2026-08-28")!,
            docDateEstimated: false, scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.91,
            relatedNotes: ["Primary Residence"], pageTexts: ["DOMINION ENERGY\nAmount due $142.18", "Page two text"]
        )

        let expected = """
        ---
        title: "Electric Bill"
        doc_type: bill
        doc_date: 2026-08-28
        from: "Dominion Energy"
        pages: 2
        scanned_at: 2026-09-13T22:42:03-04:00
        source: "[[2026-08-28 Dominion Energy - Electric Bill.pdf]]"
        tags: ["scanned", "utilities"]
        filing_confidence: 0.91
        related: ["[[Primary Residence]]"]
        amount_due: 142.18
        due_date: 2026-09-18
        currency: "USD"
        account_last4: "4417"
        paid_on: 2026-09-02
        ---

        # Electric Bill, Dominion Energy

        ![[2026-08-28 Dominion Energy - Electric Bill.pdf]]

        ## Summary

        August electric bill, account number ••••3210.

        ## Handwritten notes

        - "Paid 9/2" → paid_on 2026-09-02

        ## Key facts

        - Amount due: 142.18 USD
        - Due date: 2026-09-18
        - Account: ••••4417

        ## Related

        - [[Primary Residence]]

        ## Extracted text

        ### Page 1

        DOMINION ENERGY
        Amount due $142.18

        ### Page 2

        Page two text

        """
        #expect(NoteWriter.render(note) == expected)
    }

    @Test func rendersPurposeFieldsAndEstimatedDate() {
        let analysis = DocumentAnalysis(
            pages: [3], splitConfidence: 0.9, docType: .handwrittenNote, title: "Gutter Cleaning Payment",
            summary: "Paid gutter cleaning.", keyFacts: KeyFacts(amount: Decimal(180), currency: "USD"),
            handwritten: [HandwrittenAnnotation(page: 3, rawText: "pd 9/3 ck #2217 $180", paidOn: CalendarDay("2026-09-03"),
                                                amountPaid: Decimal(180), paymentMethod: "check", checkNumber: "2217")],
            purposeFit: PurposeFit(fits: true, reason: "Home service receipt", taxYear: 2026,
                                   taxCategory: .businessReceipt, expenseCategory: .professionalServices)
        )
        let note = NoteContent(
            baseName: "2026-09-13 Gutter Cleaning Payment", analysis: analysis, docDate: CalendarDay("2026-09-13")!,
            docDateEstimated: true, scannedAt: scannedAt, timeZone: newYork, filingConfidence: 1.0,
            scanPurpose: "2026 taxes, business receipts", ledgerNoteName: "2026 Business Receipts", pageTexts: ["pd 9/3 ck #2217"]
        )
        let output = NoteWriter.render(note)

        #expect(output.contains("doc_date: 2026-09-13\ndoc_date_estimated: true\n"))
        #expect(!output.contains("from:"))
        #expect(output.contains("amount: 180.00\ncurrency: \"USD\"\n"))
        #expect(output.contains("paid_on: 2026-09-03\namount_paid: 180.00\npayment_method: \"check\"\ncheck_number: \"2217\"\n"))
        #expect(output.contains("""
        scan_purpose: "2026 taxes, business receipts"
        tax_year: 2026
        tax_category: business-receipt
        expense_category: professional-services
        ledger: "[[2026 Business Receipts]]"
        ---
        """))
        #expect(output.contains("# Gutter Cleaning Payment\n\n"))
        #expect(output.contains("- \"pd 9/3 ck #2217 $180\" → paid_on 2026-09-03, amount_paid 180.00, payment_method check, check_number 2217"))
        #expect(output.contains("## Key facts\n\n- Amount: 180.00 USD"))
        #expect(!output.contains("## Related"))
    }

    @Test func escapesQuotesInYAMLStrings() {
        let analysis = DocumentAnalysis(pages: [1], splitConfidence: 1, docType: .letter, title: "He said \"hi\"", summary: "x")
        let note = NoteContent(baseName: "b", analysis: analysis, docDate: CalendarDay("2026-01-01")!, docDateEstimated: false,
                               scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.8, pageTexts: [])
        #expect(NoteWriter.render(note).contains("title: \"He said \\\"hi\\\"\"\n"))
    }

    @Test func formatsMoneyWithTwoDecimals() {
        #expect(Money.format(Decimal(string: "142.18")!) == "142.18")
        #expect(Money.format(Decimal(180)) == "180.00")
        #expect(Money.format(Decimal(string: "1234.567")!) == "1234.57")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter NoteWriterTests`
Expected: build FAILS with `cannot find 'NoteContent' in scope`.

- [ ] **Step 3: Implement Money and YAML**

`packages/ScanCore/Sources/ScanCore/Output/Money.swift`:
```swift
import Foundation

public enum Money {
    /// Formats with exactly two decimals, `.` separator, no grouping (e.g. `1234.57`).
    public static func format(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
    }
}
```

`packages/ScanCore/Sources/ScanCore/Output/YAML.swift`:
```swift
import Foundation

/// Minimal YAML scalar formatting for note front matter. Strings are always double-quoted.
enum YAML {
    static func string(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    static func list(_ values: [String]) -> String {
        "[" + values.map(string).joined(separator: ", ") + "]"
    }

    static func wikilink(_ name: String) -> String {
        string("[[\(name)]]")
    }

    static func confidence(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
```

- [ ] **Step 4: Implement NoteContent and NoteWriter**

`packages/ScanCore/Sources/ScanCore/Output/NoteContent.swift`:
```swift
import Foundation

/// Everything NoteWriter needs to render one filed document's Markdown note.
public struct NoteContent: Sendable, Equatable {
    public var baseName: String
    public var analysis: DocumentAnalysis
    public var docDate: CalendarDay
    public var docDateEstimated: Bool
    public var scannedAt: Date
    public var timeZone: TimeZone
    public var filingConfidence: Double
    public var relatedNotes: [String]
    public var scanPurpose: String?
    public var ledgerNoteName: String?
    public var pageTexts: [String]

    public init(baseName: String, analysis: DocumentAnalysis, docDate: CalendarDay, docDateEstimated: Bool,
                scannedAt: Date, timeZone: TimeZone, filingConfidence: Double, relatedNotes: [String] = [],
                scanPurpose: String? = nil, ledgerNoteName: String? = nil, pageTexts: [String]) {
        self.baseName = baseName
        self.analysis = analysis
        self.docDate = docDate
        self.docDateEstimated = docDateEstimated
        self.scannedAt = scannedAt
        self.timeZone = timeZone
        self.filingConfidence = filingConfidence
        self.relatedNotes = relatedNotes
        self.scanPurpose = scanPurpose
        self.ledgerNoteName = ledgerNoteName
        self.pageTexts = pageTexts
    }
}
```

`packages/ScanCore/Sources/ScanCore/Output/NoteWriter.swift`:
```swift
import Foundation

/// Renders the Markdown note for a filed document (spec §10.2).
public enum NoteWriter {
    public static func render(_ note: NoteContent) -> String {
        frontMatter(note) + "\n" + body(note)
    }

    static func frontMatter(_ note: NoteContent) -> String {
        let analysis = note.analysis
        var lines = ["---"]
        lines.append("title: \(YAML.string(analysis.title))")
        lines.append("doc_type: \(analysis.docType.rawValue)")
        lines.append("doc_date: \(note.docDate)")
        if note.docDateEstimated { lines.append("doc_date_estimated: true") }
        if let from = analysis.from, !from.isEmpty { lines.append("from: \(YAML.string(from))") }
        lines.append("pages: \(analysis.pages.count)")
        lines.append("scanned_at: \(timestamp(note.scannedAt, in: note.timeZone))")
        lines.append("source: \(YAML.wikilink(note.baseName + ".pdf"))")
        lines.append("tags: \(YAML.list(tags(analysis.tags)))")
        lines.append("filing_confidence: \(YAML.confidence(note.filingConfidence))")
        if !note.relatedNotes.isEmpty {
            lines.append("related: [" + note.relatedNotes.map(YAML.wikilink).joined(separator: ", ") + "]")
        }
        lines += keyFactProperties(analysis.keyFacts)
        lines += handwrittenProperties(analysis.handwritten)
        if let purpose = note.scanPurpose {
            lines.append("scan_purpose: \(YAML.string(purpose))")
            if let fit = analysis.purposeFit {
                if let year = fit.taxYear { lines.append("tax_year: \(year)") }
                if let category = fit.taxCategory { lines.append("tax_category: \(category.rawValue)") }
                if let category = fit.expenseCategory { lines.append("expense_category: \(category.rawValue)") }
            }
            if let ledger = note.ledgerNoteName { lines.append("ledger: \(YAML.wikilink(ledger))") }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    static func body(_ note: NoteContent) -> String {
        let analysis = note.analysis
        var sections: [String] = []
        let heading: String
        if let from = analysis.from, !from.isEmpty {
            heading = "# \(analysis.title), \(from)"
        } else {
            heading = "# \(analysis.title)"
        }
        sections.append("\(heading)\n\n![[\(note.baseName).pdf]]")
        sections.append("## Summary\n\n" + SensitiveNumberMasker.mask(analysis.summary))
        if !analysis.handwritten.isEmpty {
            sections.append("## Handwritten notes\n\n" + analysis.handwritten.map(handwrittenLine).joined(separator: "\n"))
        }
        let facts = keyFactLines(analysis.keyFacts)
        if !facts.isEmpty {
            sections.append("## Key facts\n\n" + facts.joined(separator: "\n"))
        }
        if !note.relatedNotes.isEmpty {
            sections.append("## Related\n\n" + note.relatedNotes.map { "- [[\($0)]]" }.joined(separator: "\n"))
        }
        var extracted = "## Extracted text"
        for (index, text) in note.pageTexts.enumerated() {
            extracted += "\n\n### Page \(index + 1)\n\n" + SensitiveNumberMasker.mask(text)
        }
        sections.append(extracted)
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func tags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return (["scanned"] + tags).filter { seen.insert($0).inserted }
    }

    private static func timestamp(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func keyFactProperties(_ facts: KeyFacts) -> [String] {
        var lines: [String] = []
        if let value = facts.amountDue { lines.append("amount_due: \(Money.format(value))") }
        if let value = facts.dueDate { lines.append("due_date: \(value)") }
        if let value = facts.amount { lines.append("amount: \(Money.format(value))") }
        if let value = facts.currency { lines.append("currency: \(YAML.string(value))") }
        if let value = facts.accountLast4 { lines.append("account_last4: \(YAML.string(value))") }
        return lines
    }

    private static func handwrittenProperties(_ annotations: [HandwrittenAnnotation]) -> [String] {
        var lines: [String] = []
        if let value = annotations.lazy.compactMap(\.paidOn).first { lines.append("paid_on: \(value)") }
        if let value = annotations.lazy.compactMap(\.amountPaid).first { lines.append("amount_paid: \(Money.format(value))") }
        if let value = annotations.lazy.compactMap(\.paymentMethod).first { lines.append("payment_method: \(YAML.string(value))") }
        if let value = annotations.lazy.compactMap(\.checkNumber).first { lines.append("check_number: \(YAML.string(value))") }
        return lines
    }

    private static func handwrittenLine(_ annotation: HandwrittenAnnotation) -> String {
        var derived: [String] = []
        if let value = annotation.paidOn { derived.append("paid_on \(value)") }
        if let value = annotation.amountPaid { derived.append("amount_paid \(Money.format(value))") }
        if let value = annotation.paymentMethod { derived.append("payment_method \(value)") }
        if let value = annotation.checkNumber { derived.append("check_number \(value)") }
        let quote = "- \"\(SensitiveNumberMasker.mask(annotation.rawText))\""
        return derived.isEmpty ? quote : "\(quote) → " + derived.joined(separator: ", ")
    }

    private static func keyFactLines(_ facts: KeyFacts) -> [String] {
        var lines: [String] = []
        let currency = facts.currency.map { " \($0)" } ?? ""
        if let value = facts.amountDue { lines.append("- Amount due: \(Money.format(value))\(currency)") }
        if let value = facts.dueDate { lines.append("- Due date: \(value)") }
        if let value = facts.amount { lines.append("- Amount: \(Money.format(value))\(currency)") }
        if let value = facts.accountLast4 { lines.append("- Account: ••••\(value)") }
        return lines
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter NoteWriterTests`
Expected: all 4 tests pass. If `rendersFullBillNote` fails, print both strings and compare line by line. The expected literal is the spec, so fix the implementation, not the expectation, unless the expectation contradicts spec §10.2.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): render Markdown notes with fixed front matter" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 6: Ledger (parse, upsert, render)

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Output/Ledger.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/LedgerTests.swift`

**Interfaces:**
- Consumes:
  - `CalendarDay`, `ExpenseCategory` (Task 2)
  - `Money.format`, `YAML.string` (Task 5)
- Produces:
  - `struct LedgerRow: Sendable, Equatable { date: CalendarDay, from: String, amount: Decimal, currency: String, category: ExpenseCategory, documentNoteName: String }`, with a public memberwise init.
  - `enum LedgerError: Error, Equatable, Sendable`, with cases `markersMissing`, `markersDuplicated`, `unparseableRow(String)`, and `mixedCurrency(existing: String, new: String)`.
  - `struct LedgerDocument: Sendable, Equatable`, with:
    - `static let startMarker`, `static let endMarker`
    - `static func new(title: String, purpose: String, taxYear: Int?) -> LedgerDocument`
    - `static func parse(_ markdown: String) throws -> LedgerDocument`
    - `private(set) var rows: [LedgerRow]`
    - `var total: Decimal`
    - `mutating func upsert(_ row: LedgerRow) throws`
    - `func render() -> String`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/LedgerTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct LedgerTests {
    let staples = LedgerRow(date: CalendarDay("2026-09-02")!, from: "Staples", amount: Decimal(string: "84.17")!,
                            currency: "USD", category: .officeSupplies, documentNoteName: "2026-09-02 Staples - Receipt")
    let delta = LedgerRow(date: CalendarDay("2026-09-10")!, from: "Delta", amount: Decimal(string: "412.60")!,
                          currency: "USD", category: .travel, documentNoteName: "2026-09-10 Delta - Flight Receipt")

    @Test func newLedgerRendersEmptyManagedTable() {
        let expected = """
        ---
        type: ledger
        scan_purpose: "2026 taxes, business receipts"
        tax_year: 2026
        ---

        # 2026 Business Receipts

        Documents filed by Auto Scanner Organizer for this purpose.

        <!-- auto-scanner:ledger:start -->
        | Date | From | Amount | Category | Document |
        |---|---|---|---|---|
        | **Total** |  | **0.00** |  |  |
        <!-- auto-scanner:ledger:end -->

        """
        let ledger = LedgerDocument.new(title: "2026 Business Receipts", purpose: "2026 taxes, business receipts", taxYear: 2026)
        #expect(ledger.render() == expected)
    }

    @Test func upsertSortsRowsByDateAndTotals() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(delta)
        try ledger.upsert(staples)
        #expect(ledger.rows.map(\.from) == ["Staples", "Delta"])
        #expect(ledger.total == Decimal(string: "496.77"))
        #expect(ledger.render().contains("""
        | 2026-09-02 | Staples | 84.17 USD | office-supplies | [[2026-09-02 Staples - Receipt]] |
        | 2026-09-10 | Delta | 412.60 USD | travel | [[2026-09-10 Delta - Flight Receipt]] |
        | **Total** |  | **496.77 USD** |  |  |
        """))
    }

    @Test func upsertIsIdempotentPerDocument() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(staples)
        var corrected = staples
        corrected.amount = Decimal(string: "90.00")!
        try ledger.upsert(corrected)
        try ledger.upsert(corrected)
        #expect(ledger.rows == [corrected])
    }

    @Test func parseAndRenderPreserveTextOutsideMarkers() throws {
        let original = """
        # My receipts

        Owner notes above the table.

        <!-- auto-scanner:ledger:start -->
        | Date | From | Amount | Category | Document |
        |---|---|---|---|---|
        | 2026-09-10 | Delta | 412.60 USD | travel | [[2026-09-10 Delta - Flight Receipt]] |
        | **Total** |  | **412.60 USD** |  |  |
        <!-- auto-scanner:ledger:end -->

        Owner notes below the table.

        """
        var ledger = try LedgerDocument.parse(original)
        #expect(ledger.rows == [delta])
        #expect(ledger.render() == original)

        try ledger.upsert(staples)
        let updated = ledger.render()
        #expect(updated.hasPrefix("# My receipts\n\nOwner notes above the table.\n\n<!-- auto-scanner:ledger:start -->\n"))
        #expect(updated.hasSuffix("<!-- auto-scanner:ledger:end -->\n\nOwner notes below the table.\n"))
        #expect(try LedgerDocument.parse(updated).rows == [staples, delta])
    }

    @Test func rejectsMissingOrDuplicatedMarkers() {
        #expect(throws: LedgerError.markersMissing) { try LedgerDocument.parse("# No table here\n") }
        let doubled = "\(LedgerDocument.startMarker)\n\(LedgerDocument.endMarker)\n\(LedgerDocument.startMarker)\n\(LedgerDocument.endMarker)\n"
        #expect(throws: LedgerError.markersDuplicated) { try LedgerDocument.parse(doubled) }
        let reversed = "\(LedgerDocument.endMarker)\n\(LedgerDocument.startMarker)\n"
        #expect(throws: LedgerError.markersMissing) { try LedgerDocument.parse(reversed) }
    }

    @Test func rejectsUnparseableRows() {
        let badRow = "| 2026-13-01 | X | 1.00 USD | travel | [[a]] |"
        let markdown = "\(LedgerDocument.startMarker)\n\(badRow)\n\(LedgerDocument.endMarker)\n"
        #expect(throws: LedgerError.unparseableRow(badRow)) { try LedgerDocument.parse(markdown) }
    }

    @Test func rejectsMixedCurrencies() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(staples)
        var euros = delta
        euros.currency = "EUR"
        #expect(throws: LedgerError.mixedCurrency(existing: "USD", new: "EUR")) { try ledger.upsert(euros) }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter LedgerTests`
Expected: build FAILS with `cannot find 'LedgerRow' in scope`.

- [ ] **Step 3: Implement**

`packages/ScanCore/Sources/ScanCore/Output/Ledger.swift`:
```swift
import Foundation

public struct LedgerRow: Sendable, Equatable {
    public var date: CalendarDay
    public var from: String
    public var amount: Decimal
    public var currency: String
    public var category: ExpenseCategory
    public var documentNoteName: String

    public init(date: CalendarDay, from: String, amount: Decimal, currency: String, category: ExpenseCategory,
                documentNoteName: String) {
        self.date = date
        self.from = from
        self.amount = amount
        self.currency = currency
        self.category = category
        self.documentNoteName = documentNoteName
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    case markersMissing
    case markersDuplicated
    case unparseableRow(String)
    case mixedCurrency(existing: String, new: String)
}

/// A purpose ledger note. Only the section between the markers is ever rewritten (spec §10.4).
public struct LedgerDocument: Sendable, Equatable {
    public static let startMarker = "<!-- auto-scanner:ledger:start -->"
    public static let endMarker = "<!-- auto-scanner:ledger:end -->"
    static let header = "| Date | From | Amount | Category | Document |"
    static let separator = "|---|---|---|---|---|"

    public private(set) var rows: [LedgerRow]
    private let prefixLines: [String]
    private let suffixLines: [String]

    private init(rows: [LedgerRow], prefixLines: [String], suffixLines: [String]) {
        self.rows = rows
        self.prefixLines = prefixLines
        self.suffixLines = suffixLines
    }

    public static func new(title: String, purpose: String, taxYear: Int?) -> LedgerDocument {
        var prefix = ["---", "type: ledger", "scan_purpose: \(YAML.string(purpose))"]
        if let taxYear { prefix.append("tax_year: \(taxYear)") }
        prefix += ["---", "", "# \(title)", "", "Documents filed by Auto Scanner Organizer for this purpose.", ""]
        return LedgerDocument(rows: [], prefixLines: prefix, suffixLines: [""])
    }

    public static func parse(_ markdown: String) throws -> LedgerDocument {
        let lines = markdown.components(separatedBy: "\n")
        let starts = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == startMarker }
        let ends = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == endMarker }
        guard starts.count <= 1, ends.count <= 1 else { throw LedgerError.markersDuplicated }
        guard let start = starts.first, let end = ends.first, start < end else { throw LedgerError.markersMissing }

        var rows: [LedgerRow] = []
        for line in lines[(start + 1)..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == header || trimmed == separator || trimmed.hasPrefix("| **Total**") {
                continue
            }
            rows.append(try parseRow(trimmed))
        }
        return LedgerDocument(rows: rows, prefixLines: Array(lines[..<start]), suffixLines: Array(lines[(end + 1)...]))
    }

    public var total: Decimal {
        rows.reduce(Decimal(0)) { $0 + $1.amount }
    }

    public mutating func upsert(_ row: LedgerRow) throws {
        if let conflicting = rows.first(where: { $0.documentNoteName != row.documentNoteName && $0.currency != row.currency }) {
            throw LedgerError.mixedCurrency(existing: conflicting.currency, new: row.currency)
        }
        rows.removeAll { $0.documentNoteName == row.documentNoteName }
        rows.append(row)
        rows.sort { ($0.date, $0.documentNoteName) < ($1.date, $1.documentNoteName) }
    }

    public func render() -> String {
        var managed = [Self.startMarker, Self.header, Self.separator]
        for row in rows {
            let from = row.from.replacingOccurrences(of: "|", with: "/")
            managed.append("| \(row.date) | \(from) | \(Money.format(row.amount)) \(row.currency) | \(row.category.rawValue) | [[\(row.documentNoteName)]] |")
        }
        let currency = rows.first.map { " \($0.currency)" } ?? ""
        managed.append("| **Total** |  | **\(Money.format(total))\(currency)** |  |  |")
        managed.append(Self.endMarker)
        let prefix = prefixLines.isEmpty ? "" : prefixLines.joined(separator: "\n") + "\n"
        let suffix = suffixLines.isEmpty ? "" : "\n" + suffixLines.joined(separator: "\n")
        return prefix + managed.joined(separator: "\n") + suffix
    }

    private static func parseRow(_ line: String) throws -> LedgerRow {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count == 7, cells[0].isEmpty, cells[6].isEmpty else { throw LedgerError.unparseableRow(line) }
        let amountParts = cells[3].split(separator: " ")
        guard let date = CalendarDay(cells[1]),
              amountParts.count == 2,
              let amount = Decimal(string: String(amountParts[0]), locale: Locale(identifier: "en_US_POSIX")),
              let category = ExpenseCategory(rawValue: cells[4]),
              cells[5].hasPrefix("[["), cells[5].hasSuffix("]]")
        else { throw LedgerError.unparseableRow(line) }
        return LedgerRow(date: date, from: cells[2], amount: amount, currency: String(amountParts[1]),
                         category: category, documentNoteName: String(cells[5].dropFirst(2).dropLast(2)))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter LedgerTests`
Expected: all 7 tests pass.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): parse, upsert and render purpose ledgers" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 7: SearchablePDFBuilder

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Output/SearchablePDFBuilder.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/SearchablePDFBuilderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RecognizedLine: Codable, Sendable, Equatable { text: String, confidence: Float, boundingBox: CGRect }`. `boundingBox` is normalized to 0...1 with a bottom-left origin, the same convention Vision uses.
  - `struct PDFPageInput: @unchecked Sendable { image: CGImage, lines: [RecognizedLine], dpi: Double }`
  - `enum SearchablePDFError: Error, Equatable, Sendable { case noPages, contextCreationFailed }`
  - `enum SearchablePDFBuilder`, with:
    - `static func build(pages: [PDFPageInput]) throws -> Data`
    - `static func pageSize(for page: PDFPageInput) -> CGSize`, which returns the size in PDF points (1/72 inch)

This technique has already been verified on this machine: text drawn with `setTextDrawingMode(.invisible)` via `CTLineDraw` can be extracted with `PDFDocument.string`.

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/SearchablePDFBuilderTests.swift`:
```swift
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import ScanCore

struct SearchablePDFBuilderTests {
    func blankImage(width: Int = 850, height: Int = 1100) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func embedsInvisibleTextThatCanBeExtracted() throws {
        let page = PDFPageInput(image: try blankImage(), lines: [
            RecognizedLine(text: "Dominion Energy Electric Bill", confidence: 0.99, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.03)),
            RecognizedLine(text: "Amount due $142.18", confidence: 0.98, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.03)),
        ], dpi: 100)
        let data = try SearchablePDFBuilder.build(pages: [page])
        let document = try #require(PDFDocument(data: data))
        let text = document.string ?? ""
        #expect(text.contains("Dominion Energy Electric Bill"))
        #expect(text.contains("Amount due $142.18"))
    }

    @Test func sizesPagesFromPixelsAndDPI() throws {
        let page = PDFPageInput(image: try blankImage(width: 850, height: 1100), lines: [], dpi: 100)
        #expect(SearchablePDFBuilder.pageSize(for: page) == CGSize(width: 612, height: 792))
        let document = try #require(PDFDocument(data: try SearchablePDFBuilder.build(pages: [page])))
        let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(bounds.width - 612) < 0.5)
        #expect(abs(bounds.height - 792) < 0.5)
    }

    @Test func buildsOnePDFPagePerInputPage() throws {
        let image = try blankImage()
        let pages = (1...3).map { index in
            PDFPageInput(image: image, lines: [
                RecognizedLine(text: "page number \(index)", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.03)),
            ], dpi: 100)
        }
        let document = try #require(PDFDocument(data: try SearchablePDFBuilder.build(pages: pages)))
        #expect(document.pageCount == 3)
        #expect(document.page(at: 1)?.string?.contains("page number 2") == true)
    }

    @Test func rejectsEmptyInput() {
        #expect(throws: SearchablePDFError.noPages) { try SearchablePDFBuilder.build(pages: []) }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter SearchablePDFBuilderTests`
Expected: build FAILS with `cannot find 'PDFPageInput' in scope`.

- [ ] **Step 3: Implement**

`packages/ScanCore/Sources/ScanCore/Output/SearchablePDFBuilder.swift`:
```swift
import CoreGraphics
import CoreText
import Foundation

public struct RecognizedLine: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Float
    /// Normalized (0...1) rectangle with a bottom-left origin, as returned by Vision.
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct PDFPageInput: @unchecked Sendable {
    public var image: CGImage
    public var lines: [RecognizedLine]
    public var dpi: Double

    public init(image: CGImage, lines: [RecognizedLine], dpi: Double) {
        self.image = image
        self.lines = lines
        self.dpi = dpi
    }
}

public enum SearchablePDFError: Error, Equatable, Sendable {
    case noPages
    case contextCreationFailed
}

/// Builds a PDF whose pages are the scanned images with an invisible, selectable text layer (spec §10.3).
public enum SearchablePDFBuilder {
    public static func build(pages: [PDFPageInput]) throws -> Data {
        guard !pages.isEmpty else { throw SearchablePDFError.noPages }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw SearchablePDFError.contextCreationFailed }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw SearchablePDFError.contextCreationFailed
        }
        for page in pages {
            draw(page, in: context)
        }
        context.closePDF()
        return data as Data
    }

    public static func pageSize(for page: PDFPageInput) -> CGSize {
        CGSize(width: Double(page.image.width) * 72 / page.dpi, height: Double(page.image.height) * 72 / page.dpi)
    }

    private static func draw(_ page: PDFPageInput, in context: CGContext) {
        let box = CGRect(origin: .zero, size: pageSize(for: page))
        let boxData = withUnsafeBytes(of: box) { Data($0) } as CFData
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
        context.draw(page.image, in: box)
        context.setTextDrawingMode(.invisible)
        for line in page.lines where !line.text.isEmpty {
            drawInvisible(line, pageBox: box, in: context)
        }
        context.endPDFPage()
    }

    private static func drawInvisible(_ line: RecognizedLine, pageBox: CGRect, in context: CGContext) {
        let rect = CGRect(
            x: line.boundingBox.minX * pageBox.width,
            y: line.boundingBox.minY * pageBox.height,
            width: line.boundingBox.width * pageBox.width,
            height: line.boundingBox.height * pageBox.height
        )
        let font = CTFontCreateWithName("Helvetica" as CFString, max(rect.height * 0.9, 1), nil)
        let attributed = NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let naturalWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.15)
        if naturalWidth > 0 {
            context.scaleBy(x: rect.width / CGFloat(naturalWidth), y: 1)
        }
        context.textPosition = .zero
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter SearchablePDFBuilderTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): build searchable PDFs with invisible OCR text layer" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 8: FilingDecider (spec §9)

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Decisions/FilingDecider.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/FilingDeciderTests.swift`

**Interfaces:**
- Consumes: `PurposeFit` (Task 2).
- Produces:
  - `struct DecisionInput: Sendable, Equatable`, with fields `threshold`, `splitConfidence`, `splitOnChunkBoundary`, `placementConfidence`, `placementFromPurposeMapping`, `createsTopLevelFolder`, `hasPurpose`, `purposeFit`, `goesToLedger`, `amountPresent`, `duplicateOf`, and `ledgerValid`. Its public init gives defaults for everything except `threshold`, `splitConfidence`, and `placementConfidence`.
  - `enum ReviewReason: Codable, Sendable, Equatable`, with cases:
    - `uncertainSplit(confidence: Double)`
    - `splitOnChunkBoundary`
    - `uncertainPlacement(confidence: Double)`
    - `newTopLevelFolder`
    - `purposeMismatch(reason: String)`
    - `missingAmount`
    - `possibleDuplicate(of: String)`
    - `ledgerNeedsAttention`
  - `enum FilingDecision: Sendable, Equatable { case autoFile; case needsReview([ReviewReason]) }`
  - `enum FilingDecider`, with `static let thresholdRange: ClosedRange<Double> = 0.5...1.0` and `static func decide(_ input: DecisionInput) -> FilingDecision`.
- Spec rule 7 (a failed or refused request) is handled upstream in Milestone 2 and is not part of this input.

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/FilingDeciderTests.swift`:
```swift
import Testing
@testable import ScanCore

struct FilingDeciderTests {
    let confident = DecisionInput(threshold: 0.75, splitConfidence: 0.9, placementConfidence: 0.9)

    @Test func autoFilesWhenEveryRulePasses() {
        #expect(FilingDecider.decide(confident) == .autoFile)
    }

    @Test func autoFilesAtExactlyTheThreshold() {
        #expect(FilingDecider.decide(DecisionInput(threshold: 0.75, splitConfidence: 0.75, placementConfidence: 0.75)) == .autoFile)
    }

    @Test func flagsUncertainSplit() {
        var input = confident
        input.splitConfidence = 0.6
        #expect(FilingDecider.decide(input) == .needsReview([.uncertainSplit(confidence: 0.6)]))
    }

    @Test func flagsSplitOnChunkBoundary() {
        var input = confident
        input.splitOnChunkBoundary = true
        #expect(FilingDecider.decide(input) == .needsReview([.splitOnChunkBoundary]))
    }

    @Test func flagsUncertainPlacementUnlessFromPurposeMapping() {
        var input = confident
        input.placementConfidence = 0.42
        #expect(FilingDecider.decide(input) == .needsReview([.uncertainPlacement(confidence: 0.42)]))
        input.placementFromPurposeMapping = true
        #expect(FilingDecider.decide(input) == .autoFile)
    }

    @Test func flagsNewTopLevelFolder() {
        var input = confident
        input.createsTopLevelFolder = true
        #expect(FilingDecider.decide(input) == .needsReview([.newTopLevelFolder]))
    }

    @Test func flagsPurposeMismatchOrMissingPurposeCheck() {
        var input = confident
        input.hasPurpose = true
        input.purposeFit = PurposeFit(fits: false, reason: "Personal pharmacy receipt")
        #expect(FilingDecider.decide(input) == .needsReview([.purposeMismatch(reason: "Personal pharmacy receipt")]))
        input.purposeFit = nil
        #expect(FilingDecider.decide(input) == .needsReview([.purposeMismatch(reason: "Purpose was not checked")]))
        input.purposeFit = PurposeFit(fits: true, reason: "Business receipt")
        #expect(FilingDecider.decide(input) == .autoFile)
    }

    @Test func requiresAmountAndValidLedgerWhenFilingToLedger() {
        var input = confident
        input.goesToLedger = true
        input.amountPresent = false
        input.ledgerValid = false
        #expect(FilingDecider.decide(input) == .needsReview([.missingAmount, .ledgerNeedsAttention]))
        input.amountPresent = true
        input.ledgerValid = true
        #expect(FilingDecider.decide(input) == .autoFile)
    }

    @Test func flagsPossibleDuplicate() {
        var input = confident
        input.duplicateOf = "2026-08-28 Dominion Energy - Electric Bill"
        #expect(FilingDecider.decide(input) == .needsReview([.possibleDuplicate(of: "2026-08-28 Dominion Energy - Electric Bill")]))
    }

    @Test func clampsThresholdIntoAllowedRange() {
        let lenient = DecisionInput(threshold: 0.2, splitConfidence: 0.55, placementConfidence: 0.55)
        #expect(FilingDecider.decide(lenient) == .autoFile)
        let tooLenient = DecisionInput(threshold: 0.2, splitConfidence: 0.45, placementConfidence: 0.9)
        #expect(FilingDecider.decide(tooLenient) == .needsReview([.uncertainSplit(confidence: 0.45)]))
    }

    @Test func listsEveryFailedRuleInRuleOrder() {
        var input = DecisionInput(threshold: 0.75, splitConfidence: 0.5, placementConfidence: 0.5)
        input.createsTopLevelFolder = true
        input.duplicateOf = "x"
        #expect(FilingDecider.decide(input) == .needsReview([
            .uncertainSplit(confidence: 0.5), .uncertainPlacement(confidence: 0.5), .newTopLevelFolder, .possibleDuplicate(of: "x"),
        ]))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter FilingDeciderTests`
Expected: build FAILS with `cannot find 'DecisionInput' in scope`.

- [ ] **Step 3: Implement**

`packages/ScanCore/Sources/ScanCore/Decisions/FilingDecider.swift`:
```swift
import Foundation

public struct DecisionInput: Sendable, Equatable {
    public var threshold: Double
    public var splitConfidence: Double
    public var splitOnChunkBoundary: Bool
    public var placementConfidence: Double
    public var placementFromPurposeMapping: Bool
    public var createsTopLevelFolder: Bool
    public var hasPurpose: Bool
    public var purposeFit: PurposeFit?
    public var goesToLedger: Bool
    public var amountPresent: Bool
    public var duplicateOf: String?
    public var ledgerValid: Bool

    public init(threshold: Double, splitConfidence: Double, splitOnChunkBoundary: Bool = false,
                placementConfidence: Double, placementFromPurposeMapping: Bool = false,
                createsTopLevelFolder: Bool = false, hasPurpose: Bool = false, purposeFit: PurposeFit? = nil,
                goesToLedger: Bool = false, amountPresent: Bool = false, duplicateOf: String? = nil,
                ledgerValid: Bool = true) {
        self.threshold = threshold
        self.splitConfidence = splitConfidence
        self.splitOnChunkBoundary = splitOnChunkBoundary
        self.placementConfidence = placementConfidence
        self.placementFromPurposeMapping = placementFromPurposeMapping
        self.createsTopLevelFolder = createsTopLevelFolder
        self.hasPurpose = hasPurpose
        self.purposeFit = purposeFit
        self.goesToLedger = goesToLedger
        self.amountPresent = amountPresent
        self.duplicateOf = duplicateOf
        self.ledgerValid = ledgerValid
    }
}

public enum ReviewReason: Codable, Sendable, Equatable {
    case uncertainSplit(confidence: Double)
    case splitOnChunkBoundary
    case uncertainPlacement(confidence: Double)
    case newTopLevelFolder
    case purposeMismatch(reason: String)
    case missingAmount
    case possibleDuplicate(of: String)
    case ledgerNeedsAttention
}

public enum FilingDecision: Sendable, Equatable {
    case autoFile
    case needsReview([ReviewReason])
}

/// Spec §9: a document auto-files only when every rule passes; otherwise all failed rules are reported.
public enum FilingDecider {
    public static let thresholdRange: ClosedRange<Double> = 0.5...1.0

    public static func decide(_ input: DecisionInput) -> FilingDecision {
        let threshold = min(max(input.threshold, thresholdRange.lowerBound), thresholdRange.upperBound)
        var reasons: [ReviewReason] = []
        if input.splitConfidence < threshold {
            reasons.append(.uncertainSplit(confidence: input.splitConfidence))
        }
        if input.splitOnChunkBoundary {
            reasons.append(.splitOnChunkBoundary)
        }
        if !input.placementFromPurposeMapping, input.placementConfidence < threshold {
            reasons.append(.uncertainPlacement(confidence: input.placementConfidence))
        }
        if input.createsTopLevelFolder {
            reasons.append(.newTopLevelFolder)
        }
        if input.hasPurpose, input.purposeFit?.fits != true {
            reasons.append(.purposeMismatch(reason: input.purposeFit?.reason ?? "Purpose was not checked"))
        }
        if input.goesToLedger, !input.amountPresent {
            reasons.append(.missingAmount)
        }
        if let duplicate = input.duplicateOf {
            reasons.append(.possibleDuplicate(of: duplicate))
        }
        if input.goesToLedger, !input.ledgerValid {
            reasons.append(.ledgerNeedsAttention)
        }
        return reasons.isEmpty ? .autoFile : .needsReview(reasons)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter FilingDeciderTests`
Expected: all 11 tests pass.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): add filing decision rules" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 9: FileSystem and VaultPathGuard

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Filing/FileSystem.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Filing/VaultPathGuard.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/LocalFileSystemTests.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/VaultPathGuardTests.swift`
- Test helper: `packages/ScanCore/Tests/ScanCoreTests/TemporaryDirectory.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol FileSystem: Sendable`, with:
    - `fileExists(at:) -> Bool`
    - `isDirectory(at:) -> Bool`
    - `contentsOfDirectory(at:) throws -> [URL]`, which skips hidden files
    - `createDirectory(at:) throws`, which creates intermediate directories
    - `readData(at:) throws -> Data`
    - `writeAtomically(_:to:) throws`
    - `moveItem(at:to:) throws`
  - `struct LocalFileSystem: FileSystem`, with `init()`.
  - `enum PathGuardError: Error, Equatable, Sendable { case absolutePath(String); case escapesRoot(String) }`
  - `struct VaultPathGuard: Sendable`, with:
    - `let root: URL`
    - `init(root: URL)`
    - `func resolve(_ relativePath: String) throws -> URL`
    - `func contains(_ url: URL) -> Bool`
  - Test helper `struct TemporaryDirectory`, with `let url: URL`, `init() throws`, and `func remove()`. Tasks 10–12 reuse it.

- [ ] **Step 1: Write the test helper and failing tests**

`packages/ScanCore/Tests/ScanCoreTests/TemporaryDirectory.swift`:
```swift
import Foundation

/// A unique temp directory for integration tests. Call `remove()` in a `defer`.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "ScanCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
```

`packages/ScanCore/Tests/ScanCoreTests/LocalFileSystemTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct LocalFileSystemTests {
    let fileSystem = LocalFileSystem()

    @Test func writesReadsAndListsFiles() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let folder = temp.url.appending(path: "a/b")
        try fileSystem.createDirectory(at: folder)
        #expect(fileSystem.isDirectory(at: folder))

        let file = folder.appending(path: "note.md")
        try fileSystem.writeAtomically(Data("hello".utf8), to: file)
        try fileSystem.writeAtomically(Data("hidden".utf8), to: folder.appending(path: ".secret"))
        #expect(fileSystem.fileExists(at: file))
        #expect(!fileSystem.isDirectory(at: file))
        #expect(try fileSystem.readData(at: file) == Data("hello".utf8))
        #expect(try fileSystem.contentsOfDirectory(at: folder).map(\.lastPathComponent) == ["note.md"])
    }

    @Test func movesItems() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let source = temp.url.appending(path: "batch")
        try fileSystem.createDirectory(at: source)
        let destination = temp.url.appending(path: "_done/batch")
        try fileSystem.createDirectory(at: destination.deletingLastPathComponent())
        try fileSystem.moveItem(at: source, to: destination)
        #expect(!fileSystem.fileExists(at: source))
        #expect(fileSystem.isDirectory(at: destination))
    }
}
```

`packages/ScanCore/Tests/ScanCoreTests/VaultPathGuardTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct VaultPathGuardTests {
    @Test func resolvesExistingAndNotYetCreatedPathsInsideVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try FileManager.default.createDirectory(at: temp.url.appending(path: "Personal/Finances"), withIntermediateDirectories: true)
        let guardian = VaultPathGuard(root: temp.url)

        let existing = try guardian.resolve("Personal/Finances")
        #expect(existing.path(percentEncoded: false).hasSuffix("/Personal/Finances"))
        let planned = try guardian.resolve("Personal/Finances/Taxes/2026")
        #expect(guardian.contains(planned))
        #expect(try guardian.resolve("") == guardian.root)
    }

    @Test(arguments: ["../outside", "Personal/../../outside", "Personal/Finances/../../../x"])
    func rejectsTraversal(_ path: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let guardian = VaultPathGuard(root: temp.url.appending(path: "Vault"))
        #expect(throws: PathGuardError.escapesRoot(path)) { try guardian.resolve(path) }
    }

    @Test(arguments: ["/etc/passwd", "~/Documents"])
    func rejectsAbsolutePaths(_ path: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let guardian = VaultPathGuard(root: temp.url)
        #expect(throws: PathGuardError.absolutePath(path)) { try guardian.resolve(path) }
    }

    @Test func rejectsSymlinksThatEscapeTheVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        let outside = temp.url.appending(path: "Outside")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "escape"), withDestinationURL: outside)
        let guardian = VaultPathGuard(root: vault)

        #expect(throws: PathGuardError.escapesRoot("escape")) { try guardian.resolve("escape") }
        #expect(throws: PathGuardError.escapesRoot("escape/new/deeper")) { try guardian.resolve("escape/new/deeper") }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter "LocalFileSystemTests|VaultPathGuardTests"`
Expected: build FAILS with `cannot find 'LocalFileSystem' in scope`.

- [ ] **Step 3: Implement FileSystem**

`packages/ScanCore/Sources/ScanCore/Filing/FileSystem.swift`:
```swift
import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    /// Lists direct children, skipping hidden files.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// Creates the directory and any missing parents.
    func createDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    /// Writes to a temporary file on the same volume, then renames it into place.
    func writeAtomically(_ data: Data, to url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
```

- [ ] **Step 4: Implement VaultPathGuard**

`packages/ScanCore/Sources/ScanCore/Filing/VaultPathGuard.swift`:
```swift
import Foundation

public enum PathGuardError: Error, Equatable, Sendable {
    case absolutePath(String)
    case escapesRoot(String)
}

/// Keeps every vault path inside the vault root, following symlinks (spec §8.3, §14).
public struct VaultPathGuard: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = Self.canonical(root)
    }

    public func resolve(_ relativePath: String) throws -> URL {
        if relativePath.hasPrefix("/") || relativePath.hasPrefix("~") {
            throw PathGuardError.absolutePath(relativePath)
        }
        let candidate = Self.canonical(root.appending(path: relativePath))
        guard contains(candidate) else { throw PathGuardError.escapesRoot(relativePath) }
        return candidate
    }

    public func contains(_ url: URL) -> Bool {
        let rootPath = Self.normalizedPath(root)
        let candidatePath = Self.normalizedPath(Self.canonical(url))
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    /// Resolves symlinks in the longest existing ancestor, then re-appends the not-yet-existing tail.
    static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.pathComponents.count > 1 {
            tail.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in tail {
            resolved.append(path: component)
        }
        return resolved.standardizedFileURL
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
```
`resolvingSymlinksInPath()` strips a leading `/private` from paths that exist, such as temp directories. Every comparison goes through `canonical`, so this stays consistent. `resolve("")` must return a URL equal to `root`. If the equality check in `resolvesExistingAndNotYetCreatedPathsInsideVault` fails only because of a trailing slash, compare `normalizedPath` values in the test instead of changing the containment logic.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter "LocalFileSystemTests|VaultPathGuardTests"`
Expected: all tests pass, including the 3 traversal cases, the 2 absolute-path cases, and the symlink escape.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): add file system abstraction and vault path guard" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 10: Filer (filing order, duplicates, ledgers)

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Filing/FrontMatterReader.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Filing/Filer.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/FrontMatterReaderTests.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/FilerTests.swift`

**Interfaces:**
- Consumes:
  - `CalendarDay`, `DocumentAnalysis`, `ExpenseCategory` (Task 2)
  - `FilenameBuilder` (Task 3)
  - `NoteContent`, `NoteWriter` (Task 5)
  - `LedgerDocument`, `LedgerRow`, `LedgerError` (Task 6)
  - `FileSystem`, `LocalFileSystem`, `VaultPathGuard`, `PathGuardError` (Task 9)
  - `TemporaryDirectory` test helper (Task 9)
- Produces:
  - `enum FrontMatterReader { static func properties(of markdown: String) -> [String: String] }` (internal)
  - `struct LedgerFiling: Sendable, Equatable { noteName, title, purpose: String; taxYear: Int?; from: String; amount: Decimal; currency: String; category: ExpenseCategory }`
  - `struct FilingRequest: Sendable, Equatable { destinationFolder: String; newSubfolder: String?; pdfData: Data; note: NoteContent; ledger: LedgerFiling? }`. `note.baseName` is ignored; the Filer computes it.
  - `struct FilingResult: Sendable, Equatable { baseName: String; folderURL, pdfURL, noteURL: URL; createdFolder: Bool; ledgerURL: URL? }`
  - `enum FilingError: Error, Equatable, Sendable { case invalidSubfolder(String); case folderMissing(String); case ledgerUpdateFailed(LedgerError, result: FilingResult) }`
  - `struct Filer: Sendable`, with:
    - `init(vaultRoot: URL, fileSystem: any FileSystem = LocalFileSystem())`
    - `let vault: VaultPathGuard`
    - `func destinationURL(folder: String, newSubfolder: String?) throws -> URL`
    - `func findDuplicate(in folderURL: URL, docDate: CalendarDay, from: String?, title: String) throws -> String?`
    - `func ledgerIsValid(in folderURL: URL, noteName: String) -> Bool`
    - `func file(_ request: FilingRequest) throws -> FilingResult`
    - `func updateLedger(_ ledger: LedgerFiling, documentNoteName: String, docDate: CalendarDay, in folderURL: URL) throws -> URL`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/FrontMatterReaderTests.swift`:
```swift
import Testing
@testable import ScanCore

struct FrontMatterReaderTests {
    @Test func readsTopLevelPropertiesAndUnquotesStrings() {
        let markdown = """
        ---
        title: "He said \\"hi\\""
        doc_date: 2026-08-28
        from: "Dominion Energy"
        tags: ["scanned"]
        ---
        # Body
        title: not front matter
        """
        let properties = FrontMatterReader.properties(of: markdown)
        #expect(properties["title"] == "He said \"hi\"")
        #expect(properties["doc_date"] == "2026-08-28")
        #expect(properties["from"] == "Dominion Energy")
        #expect(properties["tags"] == "[\"scanned\"]")
        #expect(properties.count == 4)
    }

    @Test func returnsEmptyWithoutFrontMatter() {
        #expect(FrontMatterReader.properties(of: "# Just a note\ntitle: x").isEmpty)
    }
}
```

`packages/ScanCore/Tests/ScanCoreTests/FilerTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct FilerTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    func makeVault() throws -> TemporaryDirectory {
        let temp = try TemporaryDirectory()
        for folder in ["Personal/Finances", "Personal/Properties/Primary Residence"] {
            try FileManager.default.createDirectory(at: temp.url.appending(path: folder), withIntermediateDirectories: true)
        }
        return temp
    }

    func request(title: String = "Electric Bill", from: String? = "Dominion Energy", folder: String = "Personal/Finances",
                 newSubfolder: String? = nil, ledger: LedgerFiling? = nil) -> FilingRequest {
        let analysis = DocumentAnalysis(pages: [1], splitConfidence: 0.9, docType: .bill, title: title, from: from,
                                        docDate: CalendarDay("2026-08-28"), summary: "Summary.")
        let note = NoteContent(baseName: "", analysis: analysis, docDate: CalendarDay("2026-08-28")!, docDateEstimated: false,
                               scannedAt: Date(timeIntervalSince1970: 1_789_353_723), timeZone: newYork,
                               filingConfidence: 0.9, pageTexts: ["text"])
        return FilingRequest(destinationFolder: folder, newSubfolder: newSubfolder, pdfData: Data("%PDF-fake".utf8),
                             note: note, ledger: ledger)
    }

    func receiptLedger(amount: String) -> LedgerFiling {
        LedgerFiling(noteName: "2026 Business Receipts", title: "2026 Business Receipts", purpose: "2026 taxes, business receipts",
                     taxYear: 2026, from: "Dominion Energy", amount: Decimal(string: amount)!, currency: "USD", category: .utilities)
    }

    @Test func filesPDFAndNoteIntoExistingFolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)

        let result = try filer.file(request())

        #expect(result.baseName == "2026-08-28 Dominion Energy - Electric Bill")
        #expect(!result.createdFolder)
        #expect(result.pdfURL.lastPathComponent == "2026-08-28 Dominion Energy - Electric Bill.pdf")
        #expect(try Data(contentsOf: result.pdfURL) == Data("%PDF-fake".utf8))
        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(note.contains("source: \"[[2026-08-28 Dominion Energy - Electric Bill.pdf]]\""))
        #expect(result.ledgerURL == nil)
    }

    @Test func createsNewSubfolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let result = try Filer(vaultRoot: vault.url)
            .file(request(folder: "Personal/Properties/Primary Residence", newSubfolder: "Utilities"))
        #expect(result.createdFolder)
        #expect(result.folderURL.path(percentEncoded: false).hasSuffix("/Primary Residence/Utilities"))
        #expect(FileManager.default.fileExists(atPath: result.noteURL.path(percentEncoded: false)))
    }

    @Test func appendsCounterOnNameCollision() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let existing = vault.url.appending(path: "Personal/Finances/2026-08-28 Dominion Energy - Electric Bill.pdf")
        try Data("old".utf8).write(to: existing)
        let result = try Filer(vaultRoot: vault.url).file(request())
        #expect(result.baseName == "2026-08-28 Dominion Energy - Electric Bill (2)")
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
    }

    @Test(arguments: ["a/b", "..", "", ".hidden"])
    func rejectsInvalidSubfolders(_ subfolder: String) throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: FilingError.invalidSubfolder(subfolder)) {
            try Filer(vaultRoot: vault.url).file(request(newSubfolder: subfolder))
        }
    }

    @Test func rejectsMissingDestinationFolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: FilingError.folderMissing("Personal/Nope")) {
            try Filer(vaultRoot: vault.url).file(request(folder: "Personal/Nope"))
        }
    }

    @Test func rejectsDestinationOutsideVault() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: PathGuardError.escapesRoot("../elsewhere")) {
            try Filer(vaultRoot: vault.url).file(request(folder: "../elsewhere"))
        }
    }

    @Test func findsDuplicateByDateSenderAndTitleIgnoringLedgers() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let result = try filer.file(request(ledger: receiptLedger(amount: "142.18")))
        let folder = result.folderURL
        let day = CalendarDay("2026-08-28")!

        #expect(try filer.findDuplicate(in: folder, docDate: day, from: "Dominion Energy", title: "Electric Bill") == result.baseName)
        #expect(try filer.findDuplicate(in: folder, docDate: day, from: "Dominion Energy", title: "Gas Bill") == nil)
        #expect(try filer.findDuplicate(in: folder, docDate: day, from: nil, title: "Electric Bill") == nil)
        #expect(try filer.findDuplicate(in: vault.url.appending(path: "Missing"), docDate: day, from: nil, title: "x") == nil)
    }

    @Test func createsThenUpdatesPurposeLedger() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)

        let first = try filer.file(request(title: "Electric Bill", ledger: receiptLedger(amount: "142.18")))
        let second = try filer.file(request(title: "Water Bill", ledger: receiptLedger(amount: "40.00")))

        let ledgerURL = try #require(second.ledgerURL)
        #expect(ledgerURL.lastPathComponent == "2026 Business Receipts.md")
        let ledger = try LedgerDocument.parse(try String(contentsOf: ledgerURL, encoding: .utf8))
        #expect(ledger.rows.map(\.documentNoteName).sorted() == [first.baseName, second.baseName].sorted())
        #expect(ledger.total == Decimal(string: "182.18"))
        #expect(try String(contentsOf: first.noteURL, encoding: .utf8).contains("ledger: \"[[2026 Business Receipts]]\""))
        #expect(filer.ledgerIsValid(in: first.folderURL, noteName: "2026 Business Receipts"))
    }

    @Test func reportsLedgerFailureAfterWritingDocument() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let folder = vault.url.appending(path: "Personal/Finances")
        try Data("# Receipts without markers\n".utf8).write(to: folder.appending(path: "2026 Business Receipts.md"))
        let filer = Filer(vaultRoot: vault.url)
        #expect(!filer.ledgerIsValid(in: folder, noteName: "2026 Business Receipts"))

        do {
            _ = try filer.file(request(ledger: receiptLedger(amount: "10.00")))
            Issue.record("Expected ledgerUpdateFailed")
        } catch let FilingError.ledgerUpdateFailed(ledgerError, result) {
            #expect(ledgerError == .markersMissing)
            #expect(FileManager.default.fileExists(atPath: result.pdfURL.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: result.noteURL.path(percentEncoded: false)))
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter "FrontMatterReaderTests|FilerTests"`
Expected: build FAILS with `cannot find 'Filer' in scope`.

- [ ] **Step 3: Implement FrontMatterReader**

`packages/ScanCore/Sources/ScanCore/Filing/FrontMatterReader.swift`:
```swift
import Foundation

/// Reads flat `key: value` properties from a note's YAML front matter. Double-quoted values are unquoted.
enum FrontMatterReader {
    static func properties(of markdown: String) -> [String: String] {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var properties: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            properties[key] = value
        }
        return properties
    }
}
```

- [ ] **Step 4: Implement Filer**

`packages/ScanCore/Sources/ScanCore/Filing/Filer.swift`:
```swift
import Foundation

public struct LedgerFiling: Sendable, Equatable {
    public var noteName: String
    public var title: String
    public var purpose: String
    public var taxYear: Int?
    public var from: String
    public var amount: Decimal
    public var currency: String
    public var category: ExpenseCategory

    public init(noteName: String, title: String, purpose: String, taxYear: Int?, from: String, amount: Decimal,
                currency: String, category: ExpenseCategory) {
        self.noteName = noteName
        self.title = title
        self.purpose = purpose
        self.taxYear = taxYear
        self.from = from
        self.amount = amount
        self.currency = currency
        self.category = category
    }
}

public struct FilingRequest: Sendable, Equatable {
    public var destinationFolder: String
    public var newSubfolder: String?
    public var pdfData: Data
    /// `note.baseName` is ignored; the Filer computes the final base name.
    public var note: NoteContent
    public var ledger: LedgerFiling?

    public init(destinationFolder: String, newSubfolder: String?, pdfData: Data, note: NoteContent, ledger: LedgerFiling?) {
        self.destinationFolder = destinationFolder
        self.newSubfolder = newSubfolder
        self.pdfData = pdfData
        self.note = note
        self.ledger = ledger
    }
}

public struct FilingResult: Sendable, Equatable {
    public var baseName: String
    public var folderURL: URL
    public var pdfURL: URL
    public var noteURL: URL
    public var createdFolder: Bool
    public var ledgerURL: URL?
}

public enum FilingError: Error, Equatable, Sendable {
    case invalidSubfolder(String)
    case folderMissing(String)
    case ledgerUpdateFailed(LedgerError, result: FilingResult)
}

/// Writes a document into the vault in spec §10.5 order: folder → PDF → note → ledger.
public struct Filer: Sendable {
    public let vault: VaultPathGuard
    private let fileSystem: any FileSystem

    public init(vaultRoot: URL, fileSystem: any FileSystem = LocalFileSystem()) {
        vault = VaultPathGuard(root: vaultRoot)
        self.fileSystem = fileSystem
    }

    public func destinationURL(folder: String, newSubfolder: String?) throws -> URL {
        guard let subfolder = newSubfolder else { return try vault.resolve(folder) }
        guard !subfolder.isEmpty, !subfolder.contains("/"), !subfolder.hasPrefix(".") else {
            throw FilingError.invalidSubfolder(subfolder)
        }
        return try vault.resolve(folder.isEmpty ? subfolder : "\(folder)/\(subfolder)")
    }

    public func file(_ request: FilingRequest) throws -> FilingResult {
        let parent = try vault.resolve(request.destinationFolder)
        let folderURL = try destinationURL(folder: request.destinationFolder, newSubfolder: request.newSubfolder)
        guard fileSystem.isDirectory(at: parent) else { throw FilingError.folderMissing(request.destinationFolder) }
        let createdFolder = !fileSystem.isDirectory(at: folderURL)
        if createdFolder {
            try fileSystem.createDirectory(at: folderURL)
        }

        let existingNames = Set(try fileSystem.contentsOfDirectory(at: folderURL).map(\.lastPathComponent))
        let analysis = request.note.analysis
        let baseName = FilenameBuilder.uniqueBaseName(
            FilenameBuilder.baseName(date: request.note.docDate, from: analysis.from, title: analysis.title),
            existingFileNames: existingNames
        )
        var note = request.note
        note.baseName = baseName
        note.ledgerNoteName = request.ledger.map { FilenameBuilder.sanitize($0.noteName) }

        let pdfURL = folderURL.appending(path: "\(baseName).pdf")
        let noteURL = folderURL.appending(path: "\(baseName).md")
        try fileSystem.writeAtomically(request.pdfData, to: pdfURL)
        try fileSystem.writeAtomically(Data(NoteWriter.render(note).utf8), to: noteURL)

        var result = FilingResult(baseName: baseName, folderURL: folderURL, pdfURL: pdfURL, noteURL: noteURL,
                                  createdFolder: createdFolder, ledgerURL: nil)
        if let ledger = request.ledger {
            do {
                result.ledgerURL = try updateLedger(ledger, documentNoteName: baseName, docDate: note.docDate, in: folderURL)
            } catch let error as LedgerError {
                throw FilingError.ledgerUpdateFailed(error, result: result)
            }
        }
        return result
    }

    public func updateLedger(_ ledger: LedgerFiling, documentNoteName: String, docDate: CalendarDay, in folderURL: URL) throws -> URL {
        let url = folderURL.appending(path: "\(FilenameBuilder.sanitize(ledger.noteName)).md")
        var document = if fileSystem.fileExists(at: url) {
            try LedgerDocument.parse(String(decoding: try fileSystem.readData(at: url), as: UTF8.self))
        } else {
            LedgerDocument.new(title: ledger.title, purpose: ledger.purpose, taxYear: ledger.taxYear)
        }
        try document.upsert(LedgerRow(date: docDate, from: ledger.from, amount: ledger.amount, currency: ledger.currency,
                                      category: ledger.category, documentNoteName: documentNoteName))
        try fileSystem.writeAtomically(Data(document.render().utf8), to: url)
        return url
    }

    public func ledgerIsValid(in folderURL: URL, noteName: String) -> Bool {
        let url = folderURL.appending(path: "\(FilenameBuilder.sanitize(noteName)).md")
        guard fileSystem.fileExists(at: url) else { return true }
        guard let data = try? fileSystem.readData(at: url) else { return false }
        return (try? LedgerDocument.parse(String(decoding: data, as: UTF8.self))) != nil
    }

    public func findDuplicate(in folderURL: URL, docDate: CalendarDay, from: String?, title: String) throws -> String? {
        guard fileSystem.isDirectory(at: folderURL) else { return nil }
        for url in try fileSystem.contentsOfDirectory(at: folderURL) where url.pathExtension == "md" {
            let properties = FrontMatterReader.properties(of: String(decoding: try fileSystem.readData(at: url), as: UTF8.self))
            guard properties["type"] != "ledger" else { continue }
            if properties["doc_date"] == docDate.description, properties["title"] == title, properties["from"] == from {
                return url.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }
}
```
Invalid subfolders throw before any folder check, which is why `rejectsInvalidSubfolders` passes even though the parent exists. `if`-expressions assigned to `var document` need Swift 5.9 or later, which Swift 6.3 has.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter "FrontMatterReaderTests|FilerTests"`
Expected: all tests pass. `rejectsInvalidSubfolders` reports 4 cases.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): file documents into the vault with duplicates and ledgers" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 11: Job event log and batch projection

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Jobs/JobEvent.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Jobs/EventStore.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Jobs/BatchProjection.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/BatchProjectionTests.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/InMemoryEventStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum JobEventKind: String, Codable, Sendable, CaseIterable`, with the exact cases from spec §12: `scanStarted, pageScanned, scanCompleted, scanInterrupted, batchAdopted, ocrCompleted, stackRead, placementDecided, needsReview, reviewResolved, folderCreated, pdfWritten, noteWritten, ledgerUpdated, rawArchived, stepFailed, retryRequested`.
  - `struct JobEvent: Codable, Sendable, Equatable, Identifiable { id: UUID; batchID: String; documentID: String?; at: Date; kind: JobEventKind; payload: [String: String] }`
  - `enum JobPayloadKey`, with constants:
    - `documentIDs`: on `stackRead`, comma-separated, in order
    - `ledger`: `"pending"` on `noteWritten` when a ledger update follows
    - `step`, `message`: on `stepFailed`
  - `protocol EventStore: Sendable { append(_:) async throws; events(forBatch:) async throws -> [JobEvent]; batchIDs() async throws -> [String] }`. `batchIDs()` returns the most recently started batch first.
  - `actor InMemoryEventStore: EventStore`
  - `enum BatchStep: String, Codable, Sendable { case scan, ocr, readStack, placeDocuments, archive, done }`
  - `enum DocumentStatus: Sendable, Equatable { case pending, needsReview, filed, failed }`
  - `enum BatchStatus: Sendable, Equatable { case scanning, interrupted, processing, needsReview, filed, failed(step: BatchStep, message: String) }`
  - `struct BatchSnapshot: Sendable, Equatable { batchID: String; status: BatchStatus; nextStep: BatchStep; documentIDs: [String]; documents: [String: DocumentStatus] }`
  - `enum BatchProjection { static func snapshot(batchID: String, events: [JobEvent]) -> BatchSnapshot }`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/BatchProjectionTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct BatchProjectionTests {
    let batch = "2026-09-13-224203"

    func events(_ specs: [(JobEventKind, String?, [String: String])]) -> [JobEvent] {
        specs.enumerated().map { index, spec in
            JobEvent(batchID: batch, documentID: spec.1, at: Date(timeIntervalSince1970: TimeInterval(index)), kind: spec.0, payload: spec.2)
        }
    }

    @Test func scanningUntilScanCompletes() {
        let snapshot = BatchProjection.snapshot(batchID: batch, events: events([(.scanStarted, nil, [:]), (.pageScanned, nil, [:])]))
        #expect(snapshot.status == .scanning)
        #expect(snapshot.nextStep == .scan)
    }

    @Test func interruptedScanCanContinue() {
        var log = events([(.scanStarted, nil, [:]), (.scanInterrupted, nil, [:])])
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .interrupted)
        log += [JobEvent(batchID: batch, at: Date(timeIntervalSince1970: 10), kind: .scanStarted)]
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .scanning)
    }

    @Test func happyPathFilesEveryDocumentThenArchives() {
        var log = events([
            (.scanStarted, nil, [:]),
            (.scanCompleted, nil, [:]),
            (.ocrCompleted, nil, [:]),
            (.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d2"]),
            (.noteWritten, "d1", [:]),
            (.noteWritten, "d2", [JobPayloadKey.ledger: "pending"]),
        ])
        var snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.status == .processing)
        #expect(snapshot.nextStep == .placeDocuments)
        #expect(snapshot.documentIDs == ["d1", "d2"])
        #expect(snapshot.documents == ["d1": .filed, "d2": .pending])

        log.append(JobEvent(batchID: batch, documentID: "d2", at: Date(timeIntervalSince1970: 100), kind: .ledgerUpdated))
        snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.status == .filed)
        #expect(snapshot.nextStep == .archive)

        log.append(JobEvent(batchID: batch, at: Date(timeIntervalSince1970: 101), kind: .rawArchived))
        #expect(BatchProjection.snapshot(batchID: batch, events: log).nextStep == .done)
    }

    @Test func needsReviewWhileAnyDocumentWaits() {
        var log = events([
            (.batchAdopted, nil, [:]),
            (.ocrCompleted, nil, [:]),
            (.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d2"]),
            (.noteWritten, "d1", [:]),
            (.needsReview, "d2", [:]),
        ])
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .needsReview)
        log.append(JobEvent(batchID: batch, documentID: "d2", at: Date(timeIntervalSince1970: 50), kind: .reviewResolved))
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .processing)
    }

    @Test func failureKeepsResumePointUntilRetry() {
        var log = events([
            (.scanStarted, nil, [:]),
            (.scanCompleted, nil, [:]),
            (.ocrCompleted, nil, [:]),
            (.stepFailed, nil, [JobPayloadKey.step: "readStack", JobPayloadKey.message: "Claude API unreachable after 3 tries"]),
        ])
        var snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.status == .failed(step: .readStack, message: "Claude API unreachable after 3 tries"))
        #expect(snapshot.nextStep == .readStack)

        log.append(JobEvent(batchID: batch, at: Date(timeIntervalSince1970: 60), kind: .retryRequested))
        snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.status == .processing)
        #expect(snapshot.nextStep == .readStack)
    }

    @Test func ignoresOtherBatchesEvents() {
        let log = events([(.scanStarted, nil, [:])]) + [JobEvent(batchID: "other", at: Date(), kind: .scanInterrupted)]
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .scanning)
    }
}
```

`packages/ScanCore/Tests/ScanCoreTests/InMemoryEventStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct InMemoryEventStoreTests {
    @Test func returnsBatchEventsInAppendOrderAndNewestBatchFirst() async throws {
        let store = InMemoryEventStore()
        let first = JobEvent(batchID: "a", at: Date(timeIntervalSince1970: 1), kind: .scanStarted)
        let second = JobEvent(batchID: "b", at: Date(timeIntervalSince1970: 2), kind: .scanStarted)
        let third = JobEvent(batchID: "a", at: Date(timeIntervalSince1970: 3), kind: .scanCompleted)
        for event in [first, second, third] {
            try await store.append(event)
        }
        #expect(try await store.events(forBatch: "a") == [first, third])
        #expect(try await store.batchIDs() == ["b", "a"])
    }

    @Test func eventsRoundTripThroughJSON() throws {
        let event = JobEvent(batchID: "a", documentID: "d1", at: Date(timeIntervalSince1970: 5), kind: .needsReview,
                             payload: ["reason": "uncertainPlacement"])
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(JobEvent.self, from: data) == event)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter "BatchProjectionTests|InMemoryEventStoreTests"`
Expected: build FAILS with `cannot find 'JobEvent' in scope`.

- [ ] **Step 3: Implement events and store**

`packages/ScanCore/Sources/ScanCore/Jobs/JobEvent.swift`:
```swift
import Foundation

public enum JobEventKind: String, Codable, Sendable, CaseIterable {
    case scanStarted, pageScanned, scanCompleted, scanInterrupted, batchAdopted, ocrCompleted, stackRead
    case placementDecided, needsReview, reviewResolved, folderCreated, pdfWritten, noteWritten, ledgerUpdated
    case rawArchived, stepFailed, retryRequested
}

public enum JobPayloadKey {
    /// On `stackRead`: comma-separated document IDs in page order.
    public static let documentIDs = "documentIDs"
    /// On `noteWritten`: `"pending"` when a ledger update must follow before the document counts as filed.
    public static let ledger = "ledger"
    /// On `stepFailed`: the `BatchStep` raw value that failed.
    public static let step = "step"
    /// On `stepFailed`: human-readable reason shown in History.
    public static let message = "message"
}

/// One append-only entry in a batch's history (spec §12).
public struct JobEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var batchID: String
    public var documentID: String?
    public var at: Date
    public var kind: JobEventKind
    public var payload: [String: String]

    public init(id: UUID = UUID(), batchID: String, documentID: String? = nil, at: Date, kind: JobEventKind,
                payload: [String: String] = [:]) {
        self.id = id
        self.batchID = batchID
        self.documentID = documentID
        self.at = at
        self.kind = kind
        self.payload = payload
    }
}
```

`packages/ScanCore/Sources/ScanCore/Jobs/EventStore.swift`:
```swift
import Foundation

public protocol EventStore: Sendable {
    func append(_ event: JobEvent) async throws
    /// Events for one batch in append order.
    func events(forBatch batchID: String) async throws -> [JobEvent]
    /// Batch IDs, most recently started first.
    func batchIDs() async throws -> [String]
}

public actor InMemoryEventStore: EventStore {
    private var storage: [JobEvent] = []

    public init() {}

    public func append(_ event: JobEvent) {
        storage.append(event)
    }

    public func events(forBatch batchID: String) -> [JobEvent] {
        storage.filter { $0.batchID == batchID }
    }

    public func batchIDs() -> [String] {
        var firstSeen: [String: Date] = [:]
        for event in storage where firstSeen[event.batchID] == nil {
            firstSeen[event.batchID] = event.at
        }
        return firstSeen.sorted { $0.value > $1.value }.map(\.key)
    }
}
```

- [ ] **Step 4: Implement the projection**

`packages/ScanCore/Sources/ScanCore/Jobs/BatchProjection.swift`:
```swift
import Foundation

public enum BatchStep: String, Codable, Sendable {
    case scan, ocr, readStack, placeDocuments, archive, done
}

public enum DocumentStatus: Sendable, Equatable {
    case pending, needsReview, filed, failed
}

public enum BatchStatus: Sendable, Equatable {
    case scanning
    case interrupted
    case processing
    case needsReview
    case filed
    case failed(step: BatchStep, message: String)
}

public struct BatchSnapshot: Sendable, Equatable {
    public var batchID: String
    public var status: BatchStatus
    public var nextStep: BatchStep
    public var documentIDs: [String]
    public var documents: [String: DocumentStatus]
}

/// Derives batch and document status from the event log (spec §12). Nothing is stored separately.
public enum BatchProjection {
    public static func snapshot(batchID: String, events: [JobEvent]) -> BatchSnapshot {
        var nextStep: BatchStep = .scan
        var documentIDs: [String] = []
        var documents: [String: DocumentStatus] = [:]
        var interrupted = false
        var failure: (step: BatchStep, message: String)?

        for event in events where event.batchID == batchID {
            switch event.kind {
            case .scanStarted:
                interrupted = false
                nextStep = .scan
            case .scanInterrupted:
                interrupted = true
            case .scanCompleted, .batchAdopted:
                interrupted = false
                nextStep = .ocr
            case .ocrCompleted:
                nextStep = .readStack
            case .stackRead:
                documentIDs = (event.payload[JobPayloadKey.documentIDs] ?? "").split(separator: ",").map(String.init)
                documents = Dictionary(uniqueKeysWithValues: documentIDs.map { ($0, DocumentStatus.pending) })
                nextStep = .placeDocuments
            case .needsReview:
                if let id = event.documentID { documents[id] = .needsReview }
            case .reviewResolved:
                if let id = event.documentID { documents[id] = .pending }
            case .noteWritten:
                if let id = event.documentID, event.payload[JobPayloadKey.ledger] != "pending" { documents[id] = .filed }
            case .ledgerUpdated:
                if let id = event.documentID { documents[id] = .filed }
            case .rawArchived:
                nextStep = .done
            case .stepFailed:
                let step = BatchStep(rawValue: event.payload[JobPayloadKey.step] ?? "") ?? nextStep
                failure = (step, event.payload[JobPayloadKey.message] ?? "Unknown error")
                if let id = event.documentID { documents[id] = .failed }
            case .retryRequested:
                failure = nil
                for (id, status) in documents where status == .failed {
                    documents[id] = .pending
                }
            case .pageScanned, .placementDecided, .folderCreated, .pdfWritten:
                break
            }
        }

        let allFiled = !documentIDs.isEmpty && documentIDs.allSatisfy { documents[$0] == .filed }
        if nextStep == .placeDocuments, allFiled {
            nextStep = .archive
        }

        let status: BatchStatus
        if let failure {
            status = .failed(step: failure.step, message: failure.message)
        } else if interrupted {
            status = .interrupted
        } else if nextStep == .scan {
            status = .scanning
        } else if documents.values.contains(.needsReview) {
            status = .needsReview
        } else if allFiled {
            status = .filed
        } else {
            status = .processing
        }
        return BatchSnapshot(batchID: batchID, status: status, nextStep: nextStep, documentIDs: documentIDs, documents: documents)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter "BatchProjectionTests|InMemoryEventStoreTests"`
Expected: all 8 tests pass.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add packages/ScanCore
git commit -m "feat(scancore): add append-only job events and batch status projection" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

### Task 12: Purposes and settings

**Files:**
- Create: `packages/ScanCore/Sources/ScanCore/Purposes/Purposes.swift`
- Create: `packages/ScanCore/Sources/ScanCore/Settings/AppSettings.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/PurposesTests.swift`
- Test: `packages/ScanCore/Tests/ScanCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `FilingDecider.thresholdRange` (Task 8).
- Produces:
  - `enum PurposeKey { static func normalize(_ purpose: String) -> String }`
  - `struct PurposeMapping: Codable, Sendable, Equatable { purpose: String; folder: String; ledgerNoteName: String?; createdAt: Date; var key: String }`
  - `protocol PurposeStore: Sendable`, with:
    - `mapping(for:) async throws -> PurposeMapping?`
    - `saveIfAbsent(_:) async throws -> PurposeMapping`
    - `recordUse(_:) async throws`
    - `recentPurposes() async throws -> [String]`
  - `actor InMemoryPurposeStore: PurposeStore`, with `static let recentLimit = 8`.
  - `enum ClaudeModel: String` (`claude-sonnet-5`, `claude-opus-5`, `claude-haiku-4-5`), with `var maxImageLongEdge: Int`.
  - `enum ScanSource: String { feeder, flatbed }`
  - `enum ColorMode: String { color, grayscale, blackAndWhite = "black-and-white" }`
  - `struct AppSettings: Codable, Sendable, Equatable { stagingPath: String?; vaultPath: String?; model; autoFileThreshold; defaultScannerName: String?; source; dpi; colorMode; duplex; static let default; var effectiveThreshold: Double }`
  - `protocol KeyValueStore: Sendable { data(forKey:) -> Data?; set(_:forKey:) }`
  - `final class InMemoryKeyValueStore: KeyValueStore`
  - `struct UserDefaultsStore: KeyValueStore`
  - `struct SettingsRepository: Sendable { static let storageKey = "AppSettings.v1"; init(store:); load() -> AppSettings; save(_:) throws }`

- [ ] **Step 1: Write the failing tests**

`packages/ScanCore/Tests/ScanCoreTests/PurposesTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct PurposesTests {
    @Test func normalizesCaseAndWhitespace() {
        #expect(PurposeKey.normalize("  2026 Taxes,\n  Business   Receipts ") == "2026 taxes, business receipts")
    }

    @Test func firstFilingWinsAndLookupIgnoresFormatting() async throws {
        let store = InMemoryPurposeStore()
        let first = PurposeMapping(purpose: "2026 taxes, business receipts", folder: "Personal/Finances/Taxes/2026/Business Receipts",
                                   ledgerNoteName: "2026 Business Receipts", createdAt: Date(timeIntervalSince1970: 1))
        let second = PurposeMapping(purpose: "2026 Taxes, Business Receipts", folder: "Somewhere/Else",
                                    ledgerNoteName: nil, createdAt: Date(timeIntervalSince1970: 2))
        #expect(try await store.saveIfAbsent(first) == first)
        #expect(try await store.saveIfAbsent(second) == first)
        #expect(try await store.mapping(for: "2026  TAXES, business receipts") == first)
        #expect(try await store.mapping(for: "Ashburn rental") == nil)
    }

    @Test func keepsEightMostRecentDistinctPurposes() async throws {
        let store = InMemoryPurposeStore()
        for index in 1...9 {
            try await store.recordUse("Purpose \(index)")
        }
        try await store.recordUse("purpose 3")
        try await store.recordUse("   ")
        let recents = try await store.recentPurposes()
        #expect(recents.count == InMemoryPurposeStore.recentLimit)
        #expect(recents.first == "purpose 3")
        #expect(recents.filter { PurposeKey.normalize($0) == "purpose 3" }.count == 1)
        #expect(!recents.contains("Purpose 1"))
        #expect(!recents.contains("Purpose 2"))
    }
}
```

`packages/ScanCore/Tests/ScanCoreTests/AppSettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import ScanCore

struct AppSettingsTests {
    @Test func defaultsMatchSpec() {
        let settings = AppSettings.default
        #expect(settings.model == .sonnet5)
        #expect(settings.model.rawValue == "claude-sonnet-5")
        #expect(settings.autoFileThreshold == 0.75)
        #expect(settings.source == .feeder)
        #expect(settings.dpi == 300)
        #expect(settings.colorMode == .color)
        #expect(settings.duplex)
        #expect(settings.stagingPath == nil)
        #expect(settings.vaultPath == nil)
    }

    @Test func modelImageLimits() {
        #expect(ClaudeModel.sonnet5.maxImageLongEdge == 2576)
        #expect(ClaudeModel.opus5.maxImageLongEdge == 2576)
        #expect(ClaudeModel.haiku45.maxImageLongEdge == 1568)
    }

    @Test func clampsEffectiveThreshold() {
        var settings = AppSettings.default
        settings.autoFileThreshold = 0.2
        #expect(settings.effectiveThreshold == 0.5)
        settings.autoFileThreshold = 1.4
        #expect(settings.effectiveThreshold == 1.0)
    }

    @Test func repositoryRoundTripsAndFallsBackToDefaults() throws {
        let store = InMemoryKeyValueStore()
        let repository = SettingsRepository(store: store)
        #expect(repository.load() == .default)

        var settings = AppSettings.default
        settings.vaultPath = "/Users/me/Vault"
        settings.model = .opus5
        try repository.save(settings)
        #expect(repository.load() == settings)

        store.set(Data("not json".utf8), forKey: SettingsRepository.storageKey)
        #expect(repository.load() == .default)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        store.set(Data("x".utf8), forKey: "k")
        #expect(store.data(forKey: "k") == Data("x".utf8))
        store.set(nil, forKey: "k")
        #expect(store.data(forKey: "k") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path packages/ScanCore --filter "PurposesTests|AppSettingsTests"`
Expected: build FAILS with `cannot find 'PurposeKey' in scope`.

- [ ] **Step 3: Implement purposes**

`packages/ScanCore/Sources/ScanCore/Purposes/Purposes.swift`:
```swift
import Foundation

public enum PurposeKey {
    /// Lowercased, trimmed, whitespace collapsed (spec §11).
    public static func normalize(_ purpose: String) -> String {
        purpose.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public struct PurposeMapping: Codable, Sendable, Equatable {
    public var purpose: String
    public var folder: String
    public var ledgerNoteName: String?
    public var createdAt: Date

    public var key: String { PurposeKey.normalize(purpose) }

    public init(purpose: String, folder: String, ledgerNoteName: String?, createdAt: Date) {
        self.purpose = purpose
        self.folder = folder
        self.ledgerNoteName = ledgerNoteName
        self.createdAt = createdAt
    }
}

public protocol PurposeStore: Sendable {
    func mapping(for purpose: String) async throws -> PurposeMapping?
    /// Stores the mapping only when none exists for its key; returns whichever mapping is stored.
    func saveIfAbsent(_ mapping: PurposeMapping) async throws -> PurposeMapping
    func recordUse(_ purpose: String) async throws
    /// Most recent first, distinct by key.
    func recentPurposes() async throws -> [String]
}

public actor InMemoryPurposeStore: PurposeStore {
    public static let recentLimit = 8

    private var mappings: [String: PurposeMapping] = [:]
    private var recents: [String] = []

    public init() {}

    public func mapping(for purpose: String) -> PurposeMapping? {
        mappings[PurposeKey.normalize(purpose)]
    }

    public func saveIfAbsent(_ mapping: PurposeMapping) -> PurposeMapping {
        if let existing = mappings[mapping.key] { return existing }
        mappings[mapping.key] = mapping
        return mapping
    }

    public func recordUse(_ purpose: String) {
        let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = PurposeKey.normalize(trimmed)
        recents.removeAll { PurposeKey.normalize($0) == key }
        recents.insert(trimmed, at: 0)
        if recents.count > Self.recentLimit {
            recents.removeLast(recents.count - Self.recentLimit)
        }
    }

    public func recentPurposes() -> [String] {
        recents
    }
}
```

- [ ] **Step 4: Implement settings**

`packages/ScanCore/Sources/ScanCore/Settings/AppSettings.swift`:
```swift
import Foundation
import Synchronization

public enum ClaudeModel: String, Codable, Sendable, CaseIterable {
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"
    case haiku45 = "claude-haiku-4-5"

    /// Longest image edge in pixels the model accepts (spec §8.1).
    public var maxImageLongEdge: Int {
        self == .haiku45 ? 1568 : 2576
    }
}

public enum ScanSource: String, Codable, Sendable, CaseIterable {
    case feeder, flatbed
}

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case color, grayscale
    case blackAndWhite = "black-and-white"
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var stagingPath: String?
    public var vaultPath: String?
    public var model: ClaudeModel
    public var autoFileThreshold: Double
    public var defaultScannerName: String?
    public var source: ScanSource
    public var dpi: Int
    public var colorMode: ColorMode
    public var duplex: Bool

    public init(stagingPath: String? = nil, vaultPath: String? = nil, model: ClaudeModel = .sonnet5,
                autoFileThreshold: Double = 0.75, defaultScannerName: String? = nil, source: ScanSource = .feeder,
                dpi: Int = 300, colorMode: ColorMode = .color, duplex: Bool = true) {
        self.stagingPath = stagingPath
        self.vaultPath = vaultPath
        self.model = model
        self.autoFileThreshold = autoFileThreshold
        self.defaultScannerName = defaultScannerName
        self.source = source
        self.dpi = dpi
        self.colorMode = colorMode
        self.duplex = duplex
    }

    public static let `default` = AppSettings()

    public var effectiveThreshold: Double {
        min(max(autoFileThreshold, FilingDecider.thresholdRange.lowerBound), FilingDecider.thresholdRange.upperBound)
    }
}

public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private let storage = Mutex<[String: Data]>([:])

    public init() {}

    public func data(forKey key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        storage.withLock { $0[key] = data }
    }
}

public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

public struct SettingsRepository: Sendable {
    public static let storageKey = "AppSettings.v1"

    private let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public func load() -> AppSettings {
        guard let data = store.data(forKey: Self.storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        store.set(try JSONEncoder().encode(settings), forKey: Self.storageKey)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path packages/ScanCore --filter "PurposesTests|AppSettingsTests"`
Expected: all 8 tests pass.

- [ ] **Step 6: Run the full milestone check**

Run: `make check`
Expected: SwiftLint finds 0 violations, and every ScanCore test passes. That means every suite from Tasks 1–12 is green.

- [ ] **Step 7: Commit**

```bash
git add packages/ScanCore
git commit -m "feat(scancore): add purpose memory and app settings" \
  -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHz61EB8Mx4vcbWNBXgKpj"
```

---

## Deferred to later milestones

- **Milestone 2 (analysis pipeline):**
  - Vision OCR adapter
  - Claude transport, and the "read stack" and "file document" requests with vault tools
  - validating Claude's placement answers (spec §8.3)
  - staging watcher and `batch.json`
  - the pipeline orchestrator, which emits `JobEvent`s, retries, and resumes
  - `make test-live`
- **Milestone 3 (app):**
  - ImageCaptureCore scanning
  - XcodeGen `project.yml` and the SwiftUI app target (History, purpose sheet, batch detail, review, settings)
  - SwiftData-backed `EventStore` and `PurposeStore`
  - Keychain secret store
  - `make start|stop|restart|seed`
  - `docs/guide/` HTML docs
