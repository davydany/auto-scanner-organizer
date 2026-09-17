import CoreGraphics
import ScanCore
import Vision

/// On-device text recognition with Vision's `RecognizeTextRequest` (spec §7, Milestone 2 probe A).
/// Boxes are normalized with a bottom-left origin, which matches `RecognizedLine`.
public struct VisionTextRecognizer: TextRecognizer {
    public init() {}

    public func recognize(_ page: PageImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: page.image)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: String(candidate.string), confidence: candidate.confidence,
                                  boundingBox: observation.boundingBox.cgRect)
        }
    }
}
