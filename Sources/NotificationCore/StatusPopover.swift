// Sources/NotificationCore/StatusPopover.swift
import Foundation

/// What the status item's popover shows (M7 plan, Stage 5).
///
/// Since 1.2 a click on the status item opens a popover, and the menu stays on
/// a right-click. The two are made from the same facts and the same text
/// types, so that they cannot disagree: every line here is a line the menu
/// shows, given to this as the menu's text types wrote it, and this decides
/// only where it stands and how it is marked. It writes the few words the menu
/// has no need of, which are the tiles' names and the headings.
///
/// It is a value made once, as the popover opens, and not changed while it is
/// open, so no row moves under the pointer (M5 plan, Ruling 22). Each control
/// carries what it acts on as it was shown: Acknowledge is for the escalations
/// listed here, and Dismiss carries the summary its line was made from.
///
/// A waiting block is the escalation panel's row, so it too names the rule and
/// the ladder's state and never what arrived (M4 plan, Ruling 17).
public enum StatusPopover {
    // MARK: - What it is made from

    /// The facts, each as the menu's build reads it.
    public struct Facts {
        /// The escalations the coordinator lists.
        public var listed: [EscalationSummary]
        public var shortcutFailure: CapturePipeline.ShortcutFailure?
        /// `HealthTitle.text`.
        public var healthTitle: String
        public var cause: HealthCause?
        /// `SetupPlan.nudgeLine`.
        public var setupNudge: String?
        public var onCall: Bool
        /// Under the On Call item while it is on: since when, and the hold against sleep.
        public var onCallLines: [String]
        /// `OnCallCheck.menuLines`, each as its `menuTitle`.
        public var onCallFindings: [String]
        public var snooze: SnoozeMenu
        /// `StatusMenuText.capturedLine`.
        public var capturedLine: String
        /// The rules' status, its detail, the warnings, the alert lines and the
        /// count of matches, in the menu's order.
        public var ruleSummary: String
        public var ruleDetail: [String]
        public var ruleLines: [String]
        /// `LaunchAtLoginText.menuLine`, when the menu shows it.
        public var launchAtLoginLine: String?

        public init(listed: [EscalationSummary], shortcutFailure: CapturePipeline.ShortcutFailure?,
                    healthTitle: String, cause: HealthCause?, setupNudge: String?,
                    onCall: Bool, onCallLines: [String], onCallFindings: [String],
                    snooze: SnoozeMenu, capturedLine: String,
                    ruleSummary: String, ruleDetail: [String], ruleLines: [String],
                    launchAtLoginLine: String?) {
            self.listed = listed
            self.shortcutFailure = shortcutFailure
            self.healthTitle = healthTitle
            self.cause = cause
            self.setupNudge = setupNudge
            self.onCall = onCall
            self.onCallLines = onCallLines
            self.onCallFindings = onCallFindings
            self.snooze = snooze
            self.capturedLine = capturedLine
            self.ruleSummary = ruleSummary
            self.ruleDetail = ruleDetail
            self.ruleLines = ruleLines
            self.launchAtLoginLine = launchAtLoginLine
        }
    }

    // MARK: - What it shows

    /// What a control does. The app carries each out as the menu's item does.
    public enum Action: Equatable, Sendable {
        /// Acknowledges the escalations this popover listed, and no other.
        case acknowledgeListed
        case openPane(HealthCause.Pane)
        case showSetupGuide
        case toggleOnCall
        case showOnCallCheck
        case startSnooze(SnoozeDuration)
        case endSnooze
        case dismissHeld(HeldSummary)
        case showInspector
        case editRules
        case openRulesFile
        case reloadRules
        case showSettings
        case quit
    }

    /// One escalation that waits: the panel's row, and the count that is drawn large.
    public struct Waiting: Equatable, Sendable {
        public let row: EscalationPanelText.Row
        /// The tier's colour, nil for a fault, which has none.
        public let tone: TierTone?
        /// "03/20", drawn large at the block's edge. nil before the first repeat
        /// and for a fault, whose line says it in words.
        public let figure: String?
    }

    /// A line of words.
    public struct Line: Equatable, Sendable {
        public enum Mark: Equatable, Sendable {
            case plain
            /// Beneath the line above it, as the menu indents it.
            case indented
            /// Something that will not reach the user as it should. Drawn with a
            /// line round it and no colour, as every fault is.
            case fault
        }

        public let text: String
        public let mark: Mark
        /// What choosing it does, nil for words that do nothing.
        public let action: Action?

        public init(_ text: String, mark: Mark = .plain, action: Action? = nil) {
            self.text = text
            self.mark = mark
            self.action = action
        }
    }

    /// Lines under one heading.
    public struct Section: Equatable, Sendable {
        public let heading: String
        public let lines: [Line]
    }

    /// One of the three large buttons.
    public struct Tile: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case inspector, rules, snooze
        }

        public let kind: Kind
        public let title: String
        /// "⌘I", in fixed-width type. nil for Snooze, which has no key.
        public let key: String?
        /// nil for Snooze, which opens its choices in place.
        public let action: Action?
    }

    /// A command beneath the tiles.
    public struct Command: Equatable, Sendable {
        public let title: String
        /// "⌘R", nil when it has no key.
        public let key: String?
        /// A tick, as the menu's On Call item has. nil for a command that has no state.
        public let isOn: Bool?
        public let action: Action
    }

    public struct Content: Equatable, Sendable {
        /// The escalations that wait, at most `waitingLimit` of them.
        public let waiting: [Waiting]
        /// How many more are listed than are drawn, said under the blocks. nil when none.
        public let moreWaiting: String?
        /// "Acknowledge" or "Acknowledge All (3)", nil when nothing is listed.
        public let acknowledgeTitle: String?
        /// The menu's lines about what is escalating, a failed Shortcut first.
        public let escalationLines: [Line]
        public let sections: [Section]
        public let tiles: [Tile]
        /// What the Snooze tile opens: the menu's Snooze submenu.
        public let snoozeChoices: [Line]
        public let commands: [Command]

        /// What a key pressed with Command does while the popover is open, by
        /// the character without its modifier: "i", "e", "r", "," and "q".
        public func action(forCommandKey character: String) -> Action? {
            let wanted = StatusPopoverText.commandMark + character.uppercased()
            if let tile = tiles.first(where: { $0.key == wanted }) { return tile.action }
            return commands.first(where: { $0.key == wanted })?.action
        }
    }

    /// How many waiting blocks are drawn. The menu counts them all in its line,
    /// and Acknowledge acts on all that are listed.
    public static let waitingLimit = 3

    /// - Parameter time: how a moment is shown, as the menu shows its own.
    public static func content(_ facts: Facts, time: (Date) -> String) -> Content {
        let waiting = facts.listed.prefix(waitingLimit).map { summary -> Waiting in
            let row = EscalationPanelText.row(for: summary, time: time)
            switch row.mark {
            case .fault:
                return Waiting(row: row, tone: nil, figure: nil)
            case .tier(let tier):
                let figure = summary.repeatCount > 0
                    ? EscalationPanelText.repeatFigure(summary.repeatCount, of: summary.repeatCap) : nil
                return Waiting(row: row, tone: TierTone(tier: tier), figure: figure)
            }
        }
        let more = facts.listed.count - waiting.count
        let escalationLines = AlertMenuText.escalationLines(listed: facts.listed, shortcutFailure: facts.shortcutFailure,
                                                            time: time).map(marked)

        var capture = [marked(facts.healthTitle)]
        if let cause = facts.cause {
            capture.append(Line(cause.advice, mark: .fault, action: cause.pane.map(Action.openPane)))
        }
        if let nudge = facts.setupNudge {
            capture.append(Line(nudge, action: .showSetupGuide))
        }
        capture.append(Line(facts.capturedLine))
        var sections = [Section(heading: StatusPopoverText.captureHeading, lines: capture)]

        var onCall: [Line] = []
        if facts.onCall {
            onCall += facts.onCallLines.map(marked) + facts.onCallFindings.map(marked)
        }
        var snoozeChoices: [Line] = []
        for item in facts.snooze.items {
            switch item {
            case .snooze(_, let submenu):
                snoozeChoices = submenu.map { choice in
                    switch choice {
                    case .line(let text): return marked(text)
                    case .start(let duration, let title): return Line(title, action: .startSnooze(duration))
                    case .end(let title): return Line(title, action: .endSnooze)
                    }
                }
            case .line(let text):
                onCall.append(marked(text))
            case .dismiss(let title, let shown):
                onCall.append(Line(title, action: .dismissHeld(shown)))
            }
        }
        if let line = facts.launchAtLoginLine {
            onCall.append(marked(line))
        }
        if !onCall.isEmpty {
            sections.append(Section(heading: StatusPopoverText.onCallHeading, lines: onCall))
        }

        let rules = [marked(facts.ruleSummary)] + facts.ruleDetail.map { Line($0, mark: .indented) }
            + facts.ruleLines.map(marked)
        sections.append(Section(heading: StatusPopoverText.rulesHeading, lines: rules))

        let tiles = [
            Tile(kind: .inspector, title: StatusPopoverText.inspectorTile, key: StatusPopoverText.key("I"),
                 action: .showInspector),
            Tile(kind: .rules, title: StatusPopoverText.rulesTile, key: StatusPopoverText.key("E"), action: .editRules),
            Tile(kind: .snooze, title: SnoozeText.menuTitle, key: nil, action: nil),
        ]
        var commands = [Command(title: OnCallText.menuTitle, key: nil, isOn: facts.onCall, action: .toggleOnCall)]
        if facts.onCall {
            commands.append(Command(title: OnCallText.checkItemTitle, key: nil, isOn: nil, action: .showOnCallCheck))
        }
        commands += [
            Command(title: SetupText.rulesFileMenuTitle, key: nil, isOn: nil, action: .openRulesFile),
            Command(title: StatusMenuText.reloadRulesTitle, key: StatusPopoverText.key("R"), isOn: nil, action: .reloadRules),
            Command(title: SettingsText.menuTitle, key: StatusPopoverText.key(","), isOn: nil, action: .showSettings),
            Command(title: StatusPopoverText.quitTitle, key: StatusPopoverText.key("Q"), isOn: nil, action: .quit),
        ]

        return Content(waiting: waiting,
                       moreWaiting: more > 0 ? StatusPopoverText.more(more) : nil,
                       acknowledgeTitle: facts.listed.isEmpty ? nil : AlertMenuText.acknowledgeTitle(listed: facts.listed.count),
                       escalationLines: escalationLines,
                       sections: sections, tiles: tiles, snoozeChoices: snoozeChoices, commands: commands)
    }

    /// A line the menu marks with its warning sign is a fault here, and keeps
    /// the sign in its words, so the two read alike.
    private static func marked(_ text: String) -> Line {
        Line(text, mark: text.hasPrefix(OnCallText.urgentMark) ? .fault : .plain)
    }
}

/// The words the popover has and the menu has not.
public enum StatusPopoverText {
    public static let captureHeading = "Capture"
    public static let onCallHeading = "On call and snooze"
    public static let rulesHeading = "Rules"
    public static let inspectorTile = "Inspector"
    public static let rulesTile = "Rules"
    public static let quitTitle = "Quit SignalLadder"
    /// What VoiceOver calls the popover's window.
    public static let windowTitle = "SignalLadder"
    public static let commandMark = "⌘"

    static func key(_ character: String) -> String { commandMark + character }

    /// "and 2 more", under the waiting blocks when more are listed than are drawn.
    static func more(_ count: Int) -> String { "and \(count) more" }
}

/// What a press of the status item opens (M7 plan, Stage 5).
///
/// A click opens the popover. A right-click, and a click with Option or Control
/// held, open the menu, as the owner decided. A press that is no mouse click is
/// one made for the user by the Accessibility API, by VoiceOver or by the live
/// check: it opens the menu, which VoiceOver reads fully and the check has
/// always read.
public enum StatusItemPress: Equatable, Sendable {
    case leftClick(option: Bool, control: Bool)
    case rightClick
    /// No mouse event: the Accessibility API's press.
    case other

    public enum Opens: Equatable, Sendable {
        case popover, menu
    }

    public var opens: Opens {
        switch self {
        case .leftClick(let option, let control): return option || control ? .menu : .popover
        case .rightClick, .other: return .menu
        }
    }
}
