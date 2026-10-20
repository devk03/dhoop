import Foundation

/// Delivery evidence is separate from readiness; an old receipt never means today's data was sent.
struct LifeSyncStatus {
    enum Phase: Equatable { case off, checking, queued, failed, processing, idle, receipt }
    let phase: Phase
    let detail: String?
    let pendingDay: String?
    let receiptDay: String?
    let receivedAt: Date?
    let outcome: String?
    let protein: Bool

    init(checkpoint: SleepWebhookCheckpoint, protein: Bool, checking: Bool, storageUnavailable: Bool) {
        self.protein = protein
        let delivery = checkpoint.delivery
        pendingDay = protein ? delivery.proteinPending?.event.day : delivery.pending?.event.wakeDate
        receiptDay = protein ? delivery.lastAcceptedProtein?.day : delivery.lastAcceptedEvent?.wakeDate
        receivedAt = protein ? delivery.proteinAcceptedAt : delivery.lastAcceptedAt
        outcome = protein ? delivery.proteinOutcome : delivery.lastOutcome
        let enabled = protein ? checkpoint.proteinEnabled == true : checkpoint.enabled
        let failures = protein ? checkpoint.proteinFailures ?? 0 : checkpoint.failures
        let message = protein ? checkpoint.proteinMessage : checkpoint.message
        if storageUnavailable { phase = .failed; detail = "Delivery state could not be read or saved. Export is paused." }
        else if !enabled { phase = .off; detail = nil }
        else if checking { phase = .checking; detail = nil }
        else if failures > 0 { phase = .failed; detail = message }
        else if pendingDay != nil { phase = .queued; detail = nil }
        else if !protein && message == "Waiting for sleep processing" { phase = .processing; detail = nil }
        else if receiptDay != nil && receivedAt != nil { phase = .receipt; detail = nil }
        else { phase = .idle; detail = nil }
    }
}
