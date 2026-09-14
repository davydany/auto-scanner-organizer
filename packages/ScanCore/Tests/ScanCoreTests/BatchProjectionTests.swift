import Foundation
import Testing
@testable import ScanCore

struct BatchProjectionTests {
    let batch = "2026-09-13-224203"

    struct EventSpec {
        let kind: JobEventKind
        let documentID: String?
        let payload: [String: String]

        init(_ kind: JobEventKind, _ documentID: String? = nil, _ payload: [String: String] = [:]) {
            self.kind = kind
            self.documentID = documentID
            self.payload = payload
        }
    }

    func events(_ specs: [EventSpec]) -> [JobEvent] {
        specs.enumerated().map { index, spec in
            JobEvent(batchID: batch, documentID: spec.documentID, at: Date(timeIntervalSince1970: TimeInterval(index)), kind: spec.kind, payload: spec.payload)
        }
    }

    @Test func scanningUntilScanCompletes() {
        let snapshot = BatchProjection.snapshot(batchID: batch, events: events([EventSpec(.scanStarted), EventSpec(.pageScanned)]))
        #expect(snapshot.status == .scanning)
        #expect(snapshot.nextStep == .scan)
    }

    @Test func interruptedScanCanContinue() {
        var log = events([EventSpec(.scanStarted), EventSpec(.scanInterrupted)])
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .interrupted)
        log += [JobEvent(batchID: batch, at: Date(timeIntervalSince1970: 10), kind: .scanStarted)]
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .scanning)
    }

    @Test func happyPathFilesEveryDocumentThenArchives() {
        var log = events([
            EventSpec(.scanStarted),
            EventSpec(.scanCompleted),
            EventSpec(.ocrCompleted),
            EventSpec(.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d2"]),
            EventSpec(.noteWritten, "d1"),
            EventSpec(.noteWritten, "d2", [JobPayloadKey.ledger: "pending"]),
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
            EventSpec(.batchAdopted),
            EventSpec(.ocrCompleted),
            EventSpec(.stackRead, nil, [JobPayloadKey.documentIDs: "d1,d2"]),
            EventSpec(.noteWritten, "d1"),
            EventSpec(.needsReview, "d2"),
        ])
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .needsReview)
        log.append(JobEvent(batchID: batch, documentID: "d2", at: Date(timeIntervalSince1970: 50), kind: .reviewResolved))
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .processing)
    }

    @Test func failureKeepsResumePointUntilRetry() {
        var log = events([
            EventSpec(.scanStarted),
            EventSpec(.scanCompleted),
            EventSpec(.ocrCompleted),
            EventSpec(.stepFailed, nil, [JobPayloadKey.step: "readStack", JobPayloadKey.message: "Claude API unreachable after 3 tries"]),
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
        let log = events([EventSpec(.scanStarted)]) + [JobEvent(batchID: "other", at: Date(), kind: .scanInterrupted)]
        #expect(BatchProjection.snapshot(batchID: batch, events: log).status == .scanning)
    }
}
