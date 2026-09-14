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

    @Test func failsSafeOnNonFiniteNumbers() {
        // NaN threshold should use upperBound (1.0)
        let nanThreshold = DecisionInput(threshold: .nan, splitConfidence: 0.9, placementConfidence: 0.9)
        #expect(
            FilingDecider.decide(nanThreshold) ==
                .needsReview([.uncertainSplit(confidence: 0.9), .uncertainPlacement(confidence: 0.9)])
        )
        // Infinite split confidence should fail
        let infiniteSplit = DecisionInput(threshold: 0.75, splitConfidence: .infinity, placementConfidence: 0.9)
        #expect(
            FilingDecider.decide(infiniteSplit) ==
                .needsReview([.uncertainSplit(confidence: .infinity)])
        )
        // NaN split confidence should fail
        let decision = FilingDecider.decide(
            DecisionInput(threshold: 0.75, splitConfidence: .nan, placementConfidence: 0.9)
        )
        if case .needsReview(let reasons) = decision, reasons.count == 1, case .uncertainSplit(let value) = reasons[0] {
            #expect(value.isNaN)
        } else {
            Issue.record("Expected a single uncertainSplit(NaN) review reason")
        }
    }
}
