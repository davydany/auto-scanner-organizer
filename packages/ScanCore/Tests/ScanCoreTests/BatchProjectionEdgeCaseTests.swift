import Foundation
import Testing
@testable import ScanCore

struct BatchProjectionEdgeCaseTests {
    let batch = "2026-09-14-010203"

    func event(_ kind: JobEventKind, _ documentID: String? = nil, _ payload: [String: String] = [:], at seconds: TimeInterval) -> JobEvent {
        JobEvent(batchID: batch, documentID: documentID, at: Date(timeIntervalSince1970: seconds), kind: kind, payload: payload)
    }

    @Test func ignoresDocumentEventsForUnknownDocumentIDs() {
        let log = [
            event(.batchAdopted, at: 1),
            event(.ocrCompleted, at: 2),
            event(.stackRead, nil, [JobPayloadKey.documentIDs: "d1"], at: 3),
            event(.needsReview, "ghost", at: 4),
            event(.noteWritten, "ghost", at: 5),
        ]
        let snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.documents == ["d1": .pending])
        #expect(snapshot.status == .processing)
    }

    @Test func secondStackReadKeepsStatusesOfDocumentsThatRemain() {
        let log = [
            event(.batchAdopted, at: 1),
            event(.ocrCompleted, at: 2),
            event(.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d2"], at: 3),
            event(.noteWritten, "d1", at: 4),
            event(.needsReview, "d2", at: 5),
            event(.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d3"], at: 6),
        ]
        let snapshot = BatchProjection.snapshot(batchID: batch, events: log)
        #expect(snapshot.documentIDs == ["d1", "d3"])
        #expect(snapshot.documents == ["d1": .filed, "d3": .pending])
        #expect(snapshot.status == .processing)
    }
}
