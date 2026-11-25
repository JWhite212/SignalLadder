// Sources/SignalLadder/PanelRowMapping.swift
import AlertPanel
import Foundation
import NotificationCore

/// Carries a row from the core, which wrote its words, to the panel, which
/// draws them (M7 plan, Stage 3).
///
/// The two targets cannot name each other's types: the core may not import
/// AppKit, and the panel depends on nothing so that it cannot show what
/// arrived (M4 plan, Ruling 17). So each has its own row, alike case for
/// case, and the app copies one into the other here and decides nothing.
extension PanelRow {
    init(id: UUID, _ said: EscalationPanelText.Row) {
        let mark: PanelRow.Mark
        switch said.mark {
        case .tier(let tier): mark = .tier(tier)
        case .fault: mark = .fault
        }
        let detail = said.detail.map { part -> PanelRow.Part in
            switch part {
            case .words(let text): return .words(text)
            case .figure(let text): return .figure(text)
            }
        }
        self.init(id: id, name: said.name, detail: detail, spoken: said.line, mark: mark)
    }
}
