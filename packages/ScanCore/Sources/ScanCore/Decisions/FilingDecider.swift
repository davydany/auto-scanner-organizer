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
        let threshold = input.threshold.isFinite
            ? min(max(input.threshold, thresholdRange.lowerBound), thresholdRange.upperBound)
            : thresholdRange.upperBound

        var reasons: [ReviewReason] = []

        let splitFails = !input.splitConfidence.isFinite || input.splitConfidence < threshold
        if splitFails {
            reasons.append(.uncertainSplit(confidence: input.splitConfidence))
        }

        if input.splitOnChunkBoundary {
            reasons.append(.splitOnChunkBoundary)
        }

        if !input.placementFromPurposeMapping {
            let placementFails = !input.placementConfidence.isFinite || input.placementConfidence < threshold
            if placementFails {
                reasons.append(.uncertainPlacement(confidence: input.placementConfidence))
            }
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
