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
    private var isAlarming = false

    func refresh(from buffer: CaptureRingBuffer) {
        entries = buffer.entries
        recomputeEmptyState()
    }

    func setHealth(summary: String, isAlarming: Bool) {
        healthSummary = summary
        self.isAlarming = isAlarming
        recomputeEmptyState()
    }

    private func recomputeEmptyState() {
        emptyStateMessage = InspectorEmptyState.message(isEmpty: entries.isEmpty,
                                                        isAlarming: isAlarming,
                                                        healthSummary: healthSummary)
    }
}
