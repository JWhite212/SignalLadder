// Sources/SignalLadder/InspectorModel.swift
import Foundation
import Combine
import NotificationCore

/// Bridges the pure ring buffer to SwiftUI.
///
/// Exists so `CaptureRingBuffer` never has to conform to `ObservableObject`:
/// the buffer holds notification content, and keeping it free of UI frameworks
/// keeps "content never leaves memory" auditable in one module. PurityTests
/// enforces that.
@MainActor
final class InspectorModel: ObservableObject {
    @Published private(set) var entries: [InspectorEntry] = []
    @Published private(set) var emptyStateMessage: String?

    private var healthSummary = "Checking…"

    /// Starts at `.unknown`, and the type carrying it is the four-case enum
    /// rather than a Bool. Defaulting to anything reassuring would have the
    /// window claim capture was verified before a single self-test had run.
    private var health: CaptureHealth = .unknown

    func refresh(from buffer: CaptureRingBuffer) {
        entries = buffer.entries
        recomputeEmptyState()
    }

    func setHealth(summary: String, health: CaptureHealth) {
        healthSummary = summary
        self.health = health
        recomputeEmptyState()
    }

    private func recomputeEmptyState() {
        emptyStateMessage = InspectorEmptyState.message(isEmpty: entries.isEmpty,
                                                        health: health,
                                                        healthSummary: healthSummary)
    }
}
