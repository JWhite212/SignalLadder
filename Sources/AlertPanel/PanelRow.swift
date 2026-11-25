// Sources/AlertPanel/PanelRow.swift
import Foundation

/// One row of the escalation panel, as the panel is given it (M7 plan, Stage 3).
///
/// Until 1.2 a row was an identifier and one line of text. A row is now a
/// block in its tier's colour with the tier's number beside the words, so the
/// panel needs the tier as a number and the words in their parts. It is still
/// given words already written, by `EscalationPanelText` in the app, and a
/// number: this target depends on nothing, so it cannot name a notification
/// or a summary, and cannot show what arrived even by mistake (M4 plan,
/// Ruling 17).
public struct PanelRow: Equatable {
    /// What stands at the row's leading edge and decides how it is drawn.
    public enum Mark: Equatable {
        /// An escalation at this tier: its number, large, on the tier's colour.
        case tier(Int)
        /// One whose alert did not reach the user as the ladder meant. Drawn
        /// with a line round it and no colour, so it is never taken for a tier.
        case fault
    }

    /// A piece of the line under the name.
    public enum Part: Equatable {
        case words(String)
        /// A time or a count, drawn in fixed-width figures.
        case figure(String)
    }

    public let id: UUID
    /// The rule's name.
    public let name: String
    /// The line under the name: when it began, how many matches, the repeats.
    public let detail: [Part]
    /// The whole row as one line, which is what VoiceOver is told.
    public let spoken: String
    public let mark: Mark

    public init(id: UUID, name: String, detail: [Part], spoken: String, mark: Mark) {
        self.id = id
        self.name = name
        self.detail = detail
        self.spoken = spoken
        self.mark = mark
    }

    /// The detail as one run of text.
    var detailText: String {
        detail.map { part -> String in
            switch part {
            case .words(let text), .figure(let text): return text
            }
        }.joined()
    }
}
