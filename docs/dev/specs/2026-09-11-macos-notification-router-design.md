# macOS Notification Router — Design

**Date:** 2026-09-11
**Status:** Approved design, revised after critic review, pending implementation plan
**Working name:** SignalLadder

---

## 1. Purpose

A native macOS menu-bar utility that reads other applications' notifications, matches them against user-defined rules, and raises a custom alert.

The driving problem is **on-call alert fatigue**, not sound personalisation. The user is on-call and misses critical alerts because Microsoft Teams group channels ping constantly; habituation means the one alert that matters is lost among hundreds that do not. A secondary, lighter case is giving a high-volume app such as Weather its own quiet, distinctive tone.

Every feature is judged against one question: **does this help the user not miss the critical one?**

### 1.1 The replacement model

This app does **not** add sound on top of existing notification sounds. Doing so would make alert fatigue strictly worse.

Instead the user mutes the source app's own notification sound in System Settings, and this app becomes that app's **only** voice — silent by default, sounding only when a rule earns it.

Muting is therefore the mechanism, not a side-feature, and the app is actively worse than nothing until the source app is muted. Onboarding (§8) carries that weight.

---

## 2. Fixed constraints

Decided at kickoff; not revisited without an explicit decision.

| Constraint    | Value                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------- |
| Language / UI | Swift + SwiftUI                                                                               |
| Minimum OS    | macOS 14 Sonoma; must work on macOS 15 Sequoia and macOS 26 Tahoe                             |
| Sandbox       | **Off.** Required for Accessibility API access                                                |
| Distribution  | Signed + notarized direct download. **Not** Mac App Store                                     |
| Runtime       | Hardened Runtime enabled                                                                      |
| Footprint     | Small binary, near-zero idle CPU, event-driven (never polling)                                |
| Privacy       | All processing local. Notification content never logged, persisted, or transmitted (see §2.1) |
| Audience      | Personal tool for a single developer; built clean enough to open-source later                 |

The Mac App Store is excluded because its sandbox blocks the Accessibility API. This is not a preference; it is a technical impossibility.

### 2.1 Precise scope of the privacy rule

"Never persisted" means: no captured notification content is written to disk by the running application, at any point, in any form — including logs, crash reports, caches, and analytics.

Two deliberate, bounded exceptions exist, both developer-only and both requiring explicit action:

1. **Test fixtures (§10.1).** Developer-authored, redacted, and never produced automatically by the shipping app.
2. **Tier 4 Shortcut input (§5.16).** A temporary file whose lifetime is bounded and whose deletion is guaranteed, created only when the user has configured a Shortcut action.

Both are named here so the constraint stays honest rather than aspirational.

---

## 3. Hard limits

Verified during research. The design must not promise around these.

| Limit                                                                                                                                                                                                                                                                          | Consequence                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No API exists** for third-party notification interception. An Apple DTS engineer has stated on record that notification activity is not accessible to the rest of the system.                                                                                                | The capture layer rests on Accessibility observation of UI, a non-contractual mechanism.                                                              |
| **Custom icons on another app's banner are not achievable.** The only known technique moves the system banner off-screen and draws an imitation `NSPanel` over it, depending on private internals and requiring repeated re-snapping as NotificationCenterUI resets positions. | **Dropped.** Custom visuals come from the app's own alert panel (§5.14).                                                                              |
| **The original notification's sound cannot be suppressed programmatically.**                                                                                                                                                                                                   | Onboarding must guide manual per-app muting. Trust-based; unverifiable.                                                                               |
| **The system-wide AX element cannot observe notifications** (`kAXErrorNotificationUnsupported`).                                                                                                                                                                               | Observers are per-PID against `com.apple.notificationcenterui`, recreated whenever that process restarts.                                             |
| **AX exposes no structured bundle identifier.**                                                                                                                                                                                                                                | Rule matching uses a display-name string recovered heuristically (§5.3). See §8.2 for the separate, bounded bundle-ID lookup used only in onboarding. |
| **AX only sees notifications currently drawn on screen.**                                                                                                                                                                                                                      | A notification delivered without a visible banner — e.g. silently into Notification Centre during a Focus — may never be captured.                    |
| **AX notification delivery is not contract-guaranteed.** Callbacks carry no payload; working element/notification combinations require empirical trial and error.                                                                                                              | Content is read by walking the AX tree. Behaviour must be re-verified per macOS release.                                                              |

### 3.1 The blindness risk

On macOS 15.4/15.4.1, notification AX elements were reported entirely invisible to all AX clients — including Apple's own Accessibility Inspector — regardless of granted permissions. They reappeared when VoiceOver or Full Keyboard Access was enabled, implying macOS lazily instantiates the notification AX tree only while an assistive-technology client is active.

For an on-call tool, silently seeing nothing is the worst possible failure. This cannot be eliminated architecturally, so it is treated as a **health problem**: the app actively proves it can still see, and fails loudly when it cannot (§9).

---

## 4. Architecture overview

One linear pipeline. Every stage after capture is pure Swift with no framework dependency.

```
AXBannerWatcher                 ← the only code Apple can break
      ↓ RawCapture
NotificationFieldExtractor      ← pure function
      ↓ CapturedNotification
ContextSnapshotProvider
      ↓ NotificationEvent
SnoozeGate
      ↓
RuleEngine                      ← pure function
      ↓ Rule?
EscalationCoordinator (actor)
      ↓
AlertActionRunner → AudioEngine / SpeechEngine / AlertPanel / ShortcutRunner

CaptureRingBuffer ← annotated with the match result after RuleEngine returns
      ↓
InspectorView                   (in-memory only)
```

Note the ring buffer is populated **after** `RuleEngine` returns, not in parallel with it, because each Inspector row must display which rule matched (§7.2).

**First organising principle:** all OS fragility is confined to one class and, within it, one function. Everything downstream is deterministic and testable against fixtures with no Accessibility permission and no live banners.

**Second organising principle:** the Rule AST is simultaneously the engine's input, the text language's parse target, and the SwiftUI builder's view model. There is no second representation, so the editors cannot drift.

---

## 5. Modules

### 5.1 Core data types

```swift
struct RawCapture {
    let timestamp: Date
    let rawText: String          // untouched AXAttributedDescription
    let subrole: String
}

struct CapturedNotification {
    let timestamp: Date
    let appNameGuess: String     // what Field.app matches against
    let title: String
    let subtitle: String         // real field; empty when absent
    let body: String
    let rawText: String          // preserved; what Field.raw matches against
    let subrole: String          // what Field.subrole matches against
}

struct ContextSnapshot {
    let date: Date               // time of day + weekday
    let onCall: Bool
    let screenLocked: Bool
    let recentCountForApp: Int
}

struct NotificationEvent {
    let captured: CapturedNotification
    let context: ContextSnapshot
}
```

`appNameGuess` is the single app-identity value used everywhere: rule matching (`Field.app`), frequency tracking, per-app snooze, and the onboarding mute checklist. The name retains "guess" deliberately — it is heuristic, and code reading it should not forget that.

### 5.2 AXBannerWatcher

Owns the only `AXObserver`. Resolves `com.apple.notificationcenterui` via `NSWorkspace.shared.runningApplications`, calls `AXUIElementCreateApplication(pid)`, and registers `kAXWindowCreatedNotification`, `kAXWindowMovedNotification`, and `kAXUIElementDestroyedNotification`.

Observes `NSWorkspace` launch/terminate notifications for that bundle ID and re-attaches with exponential backoff when the process recycles. A successful re-attach must be followed by a canary round-trip before health returns to verified (§9).

```swift
protocol NotificationCaptureSource {
    var captures: AsyncStream<RawCapture> { get }
}
```

A `FixtureCaptureSource` conforming to the same protocol replays recorded captures, making the entire downstream pipeline testable in CI without AX.

### 5.3 BannerTreeLocator

Finds the real banner element from the callback element and reads its `AXAttributedDescription`.

**Subrole-driven, never index-path-driven.** Bounded breadth-first search allow-listing `AXNotificationCenterBanner`, `AXNotificationCenterBannerStack`, `AXNotificationCenterAlert`, `AlertStack`. Bounds: max depth 12, max visited nodes 256, `AXUIElementSetMessagingTimeout` of 0.2s.

This absorbs macOS 26's overlay wrapper: the same search finds the same subrole several levels deeper with no code change. An OS version check may be a starting-depth _hint_ only, never a branch correctness depends on. The tree also changes shape on mouse hover, so the search must tolerate multiple shapes.

### 5.4 NotificationFieldExtractor

```swift
func extract(_ raw: RawCapture) -> CapturedNotification
```

**Revised 2026-09-11 after live capture on macOS 26.7. The original design assumed `"AppName, Title\nBody"`, parsed by splitting on the first comma then the first newline. That format does not exist.** Observed reality:

```
AXGroup subrole=AXNotificationCenterAlert
        desc="Microsoft Teams, This is a test notification, Message preview."
├── AXStaticText value="This is a test notification"
└── AXStaticText value="Message preview."
```

The description is comma-joined across up to four fields with **no newline anywhere**, so the original newline split would never have fired and `body` would have been permanently empty. But the banner's `AXStaticText` children expose the fields already separated, which is strictly better than parsing the concatenation.

**Primary path — read the children:**

| Text children | Mapping |
|---|---|
| 3 | title, subtitle, body |
| 2 | title, body (subtitle empty) |
| 1 | title only |
| 0 | fall back to comma-splitting the description |

`appNameGuess` always comes from the text **before the first comma** in the description. It has no child element of its own, so the description is its only source.

**Fallback path — comma-split the description** when the banner has no text children:

| Description shape | Result |
|---|---|
| Two or more comma-separated segments | First segment is `appNameGuess`; the rest map by count as above |
| No comma | `appNameGuess` empty; whole string becomes `title` |
| Empty | All fields empty; the event is still emitted so the Inspector shows the anomaly |

The fallback is **lossy in a way the original design underestimated**: with commas as the only delimiter and no newline to fall back on, a sender name, title or body containing a comma is indistinguishable from a field boundary. That is why the child path is primary, and why `rawText` is preserved on every event as a matchable escape hatch.

### 5.5 ContextSnapshotProvider

Builds `ContextSnapshot` at capture time. Snapshotting at capture (rather than evaluation) keeps `RuleEngine` a pure function and makes rules testable at any simulated context.

**`focusActive` was removed on 2026-09-11 after the M2 spike** (see §11). `INFocusStatusCenter` authorises successfully on a Developer ID app but does not report local Focus state, and the only working alternative — the `~/Library/DoNotDisturb/DB` files — requires **Full Disk Access**, a permission this app otherwise does not need and which materially changes how invasive it feels on first run.

The intent behind the condition is served by the **on-call toggle** and **time windows**, which cover the same cases without any additional permission: "don't wake me outside working hours" and "everything matters while I'm on rota" were the reasons Focus was wanted.

### 5.6 NotificationFrequencyTracker

Timestamps of captures keyed by `appNameGuess`. **Time-bounded, not count-bounded**: entries older than the largest supported frequency window (24 hours) are evicted, so a large-window rule cannot silently undercount through buffer wrap.

`frequencyAtLeast` always scopes to **the triggering event's own app**. It cannot reference a different app; that would need a second parameter and has no stated use case.

In-memory; not persisted.

### 5.7 Rule model

```swift
struct Rule: Codable, Identifiable {
    let id: UUID
    var name: String
    var condition: RuleCondition
    var escalation: EscalationLadder
    var isEnabled: Bool
}

indirect enum RuleCondition: Codable, Equatable {
    case and([RuleCondition])
    case or([RuleCondition])
    case not(RuleCondition)
    case field(Field, Operator, String)
    case timeWindow(start: Time, end: Time, weekdays: Set<Weekday>)
    case onCall(Bool)
    case screenLocked(Bool)
    case frequencyAtLeast(count: Int, windowSeconds: Int)
}

enum Field: String, Codable { case app, title, subtitle, body, raw, subrole }
enum Operator: String, Codable { case equals, notEquals, contains, matches, regex }
```

### 5.8 Alert actions

A rule's response at any tier is an `AlertAction`, not necessarily a sound. This is what makes "speak it instead", "run a Shortcut instead of playing a sound", and "no sound at all" expressible.

```swift
enum AlertAction: Codable, Equatable {
    case sound(SoundRef, gainDB: Double)
    case speak(SpeechAction)
    case shortcut(name: String)
    case silent
}

struct SpeechAction: Codable, Equatable {
    var voiceIdentifier: String       // AVSpeechSynthesisVoice.identifier
    var template: String              // tokens: {app} {title} {body}
    var rate: Float                   // 0...1,   default 0.5
    var pitchMultiplier: Float        // 0.5...2, default 1.0
    var gainDB: Double                // applied in the audio graph, not the utterance
}

struct EscalationLadder: Codable {
    var tier1: AlertAction            // immediate; may be .silent
    var tier2: PersistentAlert?       // after tier2DelaySeconds
    var tier3: RepeatAction?          // every intervalSeconds, capped (§5.12)
    var tier4: AlertAction?           // after tier4DelaySeconds; typically .shortcut
}

struct PersistentAlert: Codable { var delaySeconds: Int }
struct RepeatAction: Codable {
    var action: AlertAction
    var intervalSeconds: Int
    var maxRepeats: Int?              // nil = uncapped (§5.12)
    var maxDurationSeconds: Int?      // nil = uncapped
}
struct ShortcutAction: Codable { var name: String }
typealias EscalationID = UUID
```

`tier1` is non-optional but may be `.silent`, so a shortcut-only or panel-only rule is expressible without a special case.

### 5.9 SpeechEngine

Uses `AVSpeechSynthesizer`. Three verified constraints shape the design:

- **Siri voices are unavailable.** If a Siri voice is selected the system silently substitutes a fallback of the same language. The voice picker must therefore show only voices returned by `AVSpeechSynthesisVoice.speechVoices()` and must **not** imply Siri voices are selectable.
- **No API triggers a voice download.** The picker shows installed voices only, with a link directing the user to System Settings › Accessibility › Spoken Content to add more.
- **`AVSpeechUtterance.volume` caps at 1.0.** Speech cannot be boosted through the utterance.

To apply per-rule gain, speech is rendered rather than spoken directly: `AVSpeechSynthesizer.write(_:toBufferCallback:)` yields `AVAudioPCMBuffer`s which are scheduled on the same `AVAudioPlayerNode` graph as file playback (§5.11). Speech therefore gets identical gain, limiting, and output-device handling to sounds.

The spoken string comes from `template` with `{app}`, `{title}`, `{body}` substituted. Default: `"{app}: {title}"` — bodies are frequently long, and a 40-second recitation of a Teams thread is not an alert.

### 5.10 RuleEngine

```swift
func firstMatch(for event: NotificationEvent, in rules: [Rule]) -> Rule?
```

Deterministic given its inputs. No AX, no I/O, no wall-clock reads except the regex budget below.

**Array order is priority order; the first enabled match wins.** A notification triggers exactly one rule, so "which rule fired?" always has one answer, and layered sounds are impossible by construction. Rule order is drag-reorderable, so the list _is_ the visible precedence model.

### 5.11 Matching semantics

- **`matches` is glob, not regex.** `*` and `?`, via a linear two-pointer matcher with no backtracking. Worst case O(n·m); cannot blow up.
- **All comparison is case- and diacritic-insensitive** by default, using `localizedStandardContains` semantics.
- **`regex` is opt-in and explicitly bounded.** `NSRegularExpression` has **no native timeout** — a pathological pattern can hang the ICU engine indefinitely. The claimed mitigation must therefore be built, in three parts:
  1. **Lint at save time.** Patterns containing nested quantifiers (`(a+)+`, `(a*)*` and similar) are rejected in the editor with an explanation.
  2. **Cap subject length** at 4 KB; longer input is truncated before matching.
  3. **Hard wall-clock budget.** The match runs via `enumerateMatches(options: .reportProgress)` with a deadline (default 50 ms). On expiry the rule evaluates to **non-matching** and a warning is attached to that Inspector row, so a pathological rule degrades visibly instead of stalling the pipeline.

Examples mapping the original requirements:

| Requirement                       | Expression                                                              |
| --------------------------------- | ----------------------------------------------------------------------- |
| `#prod-* OR #incident-*`          | `title matches "#prod-*" or title matches "#incident-*"`                |
| `#alerts AND deploy`              | `title contains "#alerts" and body contains "deploy"`                   |
| Tagged in All Hands while on-call | `app == "Microsoft Teams" and raw contains "@Jamie" and onCall == true` |

### 5.12 Repeat capping

The user's stated requirement is "repeat until I acknowledge it". An uncapped repeat is also a genuine hazard — an alert that screams through a meeting with no ceiling is how a tool gets uninstalled.

Resolution: `maxRepeats` and `maxDurationSeconds` are both **optional and user-configurable**, defaulting to a cap (see §14) but settable to `nil` for true unlimited repeat. When a cap is reached the sound stops but **the persistent panel remains visible, silently** — the user stops being tortured; the evidence survives.

This is a deviation from the literal requirement and is recorded here rather than buried, because the default matters.

### 5.13 Expression language

Hand-rolled recursive descent, approximately one file.

```
expr       := or
or         := and ("or" and)*
and        := unary ("and" unary)*
unary      := "not" unary | "(" expr ")" | predicate
predicate  := field op string | context
field      := "app" | "title" | "subtitle" | "body" | "raw" | "subrole"
op         := "==" | "!=" | "contains" | "matches" | "regex"
context    := "onCall" "==" bool
            | "locked" "==" bool
            | "time" "between" time "and" time [ "on" weekdays ]
            | "frequency" "(" int ")" ">=" int
time       := HH ":" MM                       -- 24-hour, zero-padded
weekdays   := day ("," day)*
day        := "mon"|"tue"|"wed"|"thu"|"fri"|"sat"|"sun"
bool       := "true" | "false"
string     := '"' <any char except unescaped quote> '"'
```

Token-to-`Operator` mapping is exact and total:

| Token      | `Operator`                 |
| ---------- | -------------------------- |
| `==`       | `.equals`                  |
| `!=`       | `.notEquals`               |
| `contains` | `.contains`                |
| `matches`  | `.matches` (glob)          |
| `regex`    | `.regex` (advanced; §5.11) |

`regex` is a spelled-out keyword rather than a symbol, so the advanced operator is visible in text as well as in the UI.

**Round-tripping is guaranteed by construction**, not by testing: parser and printer share one grammar table, so every AST has exactly one canonical rendering that re-parses to itself. Verified by a property test over generated ASTs: `parse(print(ast)) == ast`.

Parse errors carry a source position and a caret.

### 5.14 RuleBuilderView

A recursive `ConditionRowView` switching over `RuleCondition` and binding controls **directly to the enum's associated values**. There is no builder view-model. Toggling to text calls the printer; toggling back calls the parser. Drift is structurally impossible.

### 5.15 EscalationCoordinator

```swift
actor EscalationCoordinator {
    func begin(rule: Rule, event: NotificationEvent) -> EscalationID
    func acknowledge(_ id: EscalationID)
    func acknowledgeAll()
}
```

An `actor` because timers fire from multiple queues and acknowledgement races them.

**Concurrent escalations.** Multiple escalations may be live simultaneously — near-simultaneous alerts from different rules are exactly the on-call case. Semantics:

- Each live escalation has its own ladder and its own timers.
- The alert panel (§5.17) shows them **stacked**, newest at top, each individually acknowledgeable.
- The status-item **Acknowledge** item and the global hotkey call `acknowledgeAll()` — during an incident the user wants one gesture to stop everything.
- Audio from concurrent escalations is **serialised**, not mixed: a new tier-1 sound interrupts an in-progress repeat tone rather than overlapping it. Two alarms at once is noise, not information.

**Sleep converts, never resumes.** On wake, any escalation older than the staleness threshold (§14) is cancelled and replaced with a single "missed while asleep" panel entry. Firing Tier 4 into a long-dead incident is worse than useless.

**App Nap assertion.** `ProcessInfo.beginActivity` with a user-initiated assertion is held **only while an escalation is live**, so idle battery cost stays nil. Unverified — see §11.

### 5.16 AudioEngine and ShortcutRunner

**Audio graph:**

```
AVAudioPlayerNode → AVAudioUnitEQ(globalGain) → AVAudioUnitPeakLimiter → mainMixer
```

`AVAudioUnitEQ.globalGain` spans −96 dB to +24 dB (verified), so the +6 dB "200%" requirement has substantial headroom.

**Boost alone will clip.** Peak amplitude is analysed once at import and stored with the sound; applied gain is computed against measured headroom; a look-ahead peak limiter terminates the graph as a safety net. Note the limiter has an attack envelope and is **not** an instantaneous clipper — a sharp transient can momentarily exceed 0 dBFS, so §10 includes an empirical no-audible-clipping check rather than assuming the guarantee.

**The gain control is labelled in dB**, with amplitude percentage shown secondarily. "200%" is +6.02 dB of _amplitude_; perceived loudness doubling is nearer +10 dB, and a control promising the latter while delivering the former is a UI that lies.

**Output devices.** A single `AVAudioEngine` targets one physical device at a time, and switching requires a stop/start with an audible glitch. The app therefore maintains **one engine instance per currently-targeted output device**, created lazily and torn down when idle. Concurrent escalations targeting different devices each play on their own engine.

**ShortcutRunner** executes `/usr/bin/shortcuts run "<name>" --input-path <file>` via `Process`. The CLI was found more reliable than ScriptingBridge and — importantly — needs none of ScriptingBridge's entitlements, so the app requires no Apple Events entitlement at all.

Input handling, which touches the privacy rule:

- Fields are serialised as JSON to a file in a per-run directory under `NSTemporaryDirectory()`, created with `0700` permissions.
- The file is deleted in a `defer` immediately after `Process` termination, and the per-run directory is removed at app exit and swept on launch.
- Tier 4 counts as **delivered at successful launch**, not at completion — a shortcut that pushes to a phone may legitimately run for a long time. A non-zero exit or unknown-shortcut error surfaces as a warning on the Inspector row and a status-item badge; it does not retry.

### 5.17 AlertPanel

A borderless, **non-activating** `NSPanel` the app draws itself, with `.canJoinAllSpaces` and `.fullScreenAuxiliary` so it follows the user across Spaces and appears over full-screen apps. Non-activating is essential — it must never steal keyboard focus mid-keystroke.

**Placement: the screen containing the mouse pointer** at the moment the panel is shown, falling back to `NSScreen.main`. Chosen because it is unambiguous and cheap to compute; "the focused display" has no single canonical meaning on macOS.

Live escalations stack in one panel, newest at top, each individually acknowledgeable.

This is deliberately **not** a system notification — the app sits downstream of the notification pipeline, so depending on one for its own alerts would be circular. The health alarm (§9) is the sole exception, and for a specific reason stated there.

### 5.18 SnoozeController

```swift
struct SnoozeState: Codable {
    var globalMutedUntil: Date?
    var perAppMutedUntil: [String: Date]   // keyed by appNameGuess
}
```

Precedence: **an event is suppressed if either the global snooze or its app's snooze is active.** They compose; neither overrides the other.

Snooze short-circuits matching **before** the rule engine runs. Snoozed events still appear in the Inspector (so the user can see what was deliberately ignored) but never escalate.

On activation, a **transient on-screen confirmation panel** appears — reusing the `AlertPanel` chrome — showing what was muted and for how long, auto-dismissing after a few seconds. The status item then carries a live countdown. State persists across restart so a crash cannot leave the user silently muted.

Snooze is **global or per-app, not per-rule** — per-rule state becomes unreasonable to hold in mind and makes "why didn't it fire?" much harder to answer.

---

## 6. Data and persistence

| Data                                   | Storage                                                   | Lifetime                  |
| -------------------------------------- | --------------------------------------------------------- | ------------------------- |
| Rules                                  | `Application Support/rules.json`, versioned, atomic write | Persistent                |
| Settings, snooze state, mute checklist | `UserDefaults`                                            | Persistent                |
| Sound library                          | `Application Support/Sounds/`                             | Persistent                |
| **Notification content**               | **In-memory ring buffer (~50 entries)**                   | **Dies with the process** |
| Frequency timestamps                   | In-memory, 24h eviction                                   | Dies with the process     |
| Tier 4 Shortcut input                  | Temp file, `0700`, deleted in `defer` (§5.16)             | Milliseconds              |

No database. At personal-tool scale it is a liability, not an asset.

---

## 7. User interface

Menu-bar only (`LSUIElement`). No dock icon, no main window.

### 7.1 Status item

States are **not** mutually exclusive — the app can be blind _while_ escalating _while_ snoozed. Explicit precedence, highest first:

1. **Blind / degraded** — warning glyph. Outranks everything; a broken pipeline is the most important fact on screen.
2. **Escalation live** — pulsing glyph, **Acknowledge** at top of menu.
3. **Snoozed** — muted glyph with countdown in title.
4. **Healthy** — normal glyph.

Lower-precedence states remain visible as menu text even when a higher one owns the glyph.

The menu holds the **on-call toggle** at top (it is a rule condition and must be one click away), snooze durations, health status, and window access.

Implementation leans toward `NSStatusItem` over `MenuBarExtra`, because a dynamically-updating title and swappable icon are required. See §11.

### 7.2 Inspector

Every captured notification, newest first, in memory only. Each row shows:

1. Parsed fields — `app`, `title`, `subtitle`, `body`
2. The **raw** string, expandable — so a misparse is visible rather than mysterious
3. The **subrole** — shown because it is a matchable field, and users cannot write rules against fields they have never seen
4. The **context snapshot** at capture time — otherwise "why didn't my on-call rule fire?" is unanswerable
5. **Whether it matched and which rule** — including matching nothing, the most common confusion
6. Any **warning** attached during evaluation (regex budget expiry, Shortcut launch failure)

### 7.3 The authoring loop

The workflow the design exists to serve, targeted at under one minute:

1. A notification arrives and appears in the Inspector
2. **Make a rule from this** seeds a condition from its real fields
3. The builder **dry-runs the rule against the ring buffer**: _"would have matched 3 of the last 50"_, listing which
4. The user widens or narrows based on observed false positives
5. Action and ladder are chosen; the rule is enabled

Step 3 is essential. Writing a rule blind and waiting for the next incident to discover it was wrong is the failure mode that causes tools like this to be abandoned.

### 7.4 Rule editor

Left: rule list, drag-reorderable (order is priority), per-rule enable toggle.
Right: condition tree with a **Builder / Text** toggle over the same AST; the escalation ladder as four individually-optional tiers, each choosing an `AlertAction` (sound / speech + voice / shortcut / silent); the live dry-run.

### 7.5 Settings

Sound library (import, and **preview at the rule's actual gain** — preview must sound like the real thing), speech voice picker with a System Settings link for downloading more, output device, launch-at-login via `SMAppService`, on-call defaults, snooze defaults, canary interval, tier timing defaults, and the persistent per-app mute checklist.

### 7.6 Explicitly absent

No dashboard, charts, or statistics. The need is for the right notification to be audible, not for analytics. The Inspector already holds the data.

---

## 8. Onboarding

The app's most likely point of failure, and not a UI-polish problem: the replacement model depends on the user muting the source app, and **no API can verify they did**.

### 8.1 Sequence

1. **Accessibility permission.** `AXIsProcessTrustedWithOptions` with the prompt option, plus an `x-apple.systempreferences` deep link. The prompt is asynchronous and does not change the returned value, so trust is re-polled for several seconds to detect the grant without requiring a restart. This step explains _why_ a notification app needs "control your computer" — an unexplained request of that severity gets denied.

2. **Notification permission.** `UNUserNotificationCenter.requestAuthorization`. Load-bearing: both the canary and the primary health alarm depend on the app's own banners being delivered. The step explains that this is how the app proves it is still working. If denied, the app enters a permanently-visible `.degraded` state (§9.4) rather than proceeding silently.

3. **Prove capture works.** The canary must round-trip before the wizard proceeds. A macOS 15.4-style failure is then discovered during setup, with the Full Keyboard Access workaround presented, rather than by missing a page.

4. **Mute walkthrough, one app at a time** (§8.2).

5. **First rule**, seeded from a real captured notification rather than a blank editor.

### 8.2 The mute walkthrough and bundle-ID lookup

Deep-linking to a specific app's pane requires `x-apple.systempreferences:com.apple.preference.notifications?id=<bundleID>` — a **bundle ID**, which §3 states AX does not provide.

The resolution, and its limits, stated precisely:

- The app resolves a bundle ID by matching `appNameGuess` against `localizedName` across `NSWorkspace.shared.runningApplications`, then across `/Applications` via `NSMetadataQuery` if not running.
- On a unique match, deep-link directly to that app's notification settings.
- On no match or an ambiguous match, fall back to opening the general Notifications pane with the app's **name displayed on screen** for the user to find manually.

This is a **bounded, best-effort, user-supervised lookup used once during onboarding** — categorically different from the per-notification bundle-ID resolution excluded in §13, which would have to be correct automatically, on every event, with no human to catch errors. The distinction is why one is in scope and the other is not.

Mute confirmation is a manual checkbox, trust-based by necessity. Two things keep that honest: the checklist is **persistent and visible in Settings** rather than a dismissible modal, and the Inspector's "matched" column gives an empirical check — if two sounds are heard, the row proves ours fired, so the other is the app's.

---

## 9. Health and failure modes

### 9.1 The canary

`CaptureHealthMonitor` posts the app's own `UNUserNotificationCenter` notification carrying a unique marker, and asserts the **production pipeline** captures and parses it back within a timeout.

Absence of notifications proves nothing — it may simply be quiet. A failed round-trip proves something. The canary runs on launch, periodically, at a tightened cadence while on-call is active, and after every observer re-attach.

### 9.2 Disambiguating canary failure

A canary failure has two distinct classes of cause, and conflating them is a design error:

| Class                | Meaning                                                                                                                                                                  | Detection                                                                                                                                                  |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Delivery failure** | The banner was never displayed, so AX had nothing to see. Causes: notification permission revoked, alert style set to None, a Focus or DND suppressing it.               | Checked **directly and first**, via `UNUserNotificationCenter.notificationSettings()` — authorization status, alert style, and Focus-suppression settings. |
| **Capture failure**  | The banner displayed but the pipeline did not see it. Causes: Accessibility permission revoked, observer detached after a process restart, the macOS 15.4 lazy-tree bug. | Inferred only **after** delivery has been confirmed healthy.                                                                                               |

Without this split, revoking notification permission would report a false capture failure — _and_ silence the alarm meant to report it. The two are checked independently so one cannot mask the other.

### 9.3 Loud degradation through three independent channels

On failure, health is surfaced through channels chosen so that **no single root cause can silence all of them**:

1. **Status-item glyph** — pure AppKit. Depends on neither AX nor `UNUserNotificationCenter`. Always available.
2. **Audible alert via `NSSound`** — the system default alert sound, played directly, bypassing both the notification system and the app's own audio graph.
3. **System `UNUserNotificationCenter` banner** — richer and clickable, but **only used when §9.2 has confirmed delivery is healthy**, since it is useless precisely when delivery is the problem.

Channel 3 was the original single alarm; channels 1 and 2 exist because a critic identified that it shared a hidden dependency with the canary it was meant to police.

The message names likely causes in the order established by §9.2.

This is **detect-and-nudge, not repair**. The underlying 15.4 bug is Apple's and no client-side fix exists.

### 9.4 Known limitations

- The canary proves that _this app's own_ notification round-trips the pipeline. A third-party banner with subtly different subrole nesting could still fail to parse while health reads verified. The canary narrows the blind spot; it does not close it. No known mechanism closes it.
- If notification permission is denied outright, the canary cannot run at all. The app then holds a permanent, visible `.degraded` state via channels 1 and 2, and states plainly that capture cannot be verified — it does not claim health it cannot demonstrate.

---

## 10. Testing strategy

| Layer                        | Approach                                                                                                                    |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `NotificationFieldExtractor` | Redacted fixture corpus (§10.1), tagged by macOS version                                                                    |
| `RuleEngine`                 | Pure unit tests over synthetic events at arbitrary simulated contexts                                                       |
| Parser / printer             | Property test: `parse(print(ast)) == ast` over generated ASTs                                                               |
| Glob matcher                 | Unit tests including adversarial patterns                                                                                   |
| Regex bounding               | Tests asserting known-pathological patterns are rejected at save time and that the runtime budget trips rather than hangs   |
| Downstream pipeline          | `FixtureCaptureSource` replays captures — no AX, no permission, runs in CI                                                  |
| `EscalationCoordinator`      | Injected clock; tier timing, capping, concurrency, sleep-conversion, and acknowledge-cancels-all verified deterministically |
| Audio                        | Empirical check that boosted sounds with sharp attacks produce no audible clipping                                          |
| `AXBannerWatcher`            | Manual on-device verification per macOS release; not unit-testable by nature                                                |

### 10.1 Fixture redaction

Fixtures capture **structural shape**, never real message content. When a new AX format is observed, the developer records its shape and **replaces all human content with synthetic placeholders** before committing — `"Microsoft Teams, Alex Example\nPlaceholder body text"`, never a real colleague's name or message.

The shipping app never writes fixtures. This is a manual developer action with a documented redaction step, which is what keeps §2.1 true — particularly given the intent to open-source, where an unredacted corpus would publish the user's work messages permanently.

---

## 11. Unverified assumptions

Scheduled for a second research pass that was stopped before completion. Each must be confirmed during implementation.

| Assumption                                                                                  | Risk if wrong                                                                                                                                                                                                     | Fallback                                                                                                                                         | Verify by                                                                                  |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| ~~`INFocusStatusCenter` is usable without an Apple-granted entitlement~~ | **RESOLVED 2026-09-11 — condition dropped.** Authorisation succeeds with only a usage description, but `isFocused` does not track local Focus state even with system Focus sharing enabled. The working alternative needs Full Disk Access. See §13 | Superseded — the on-call toggle and time windows serve the same intent | Done |
| `ProcessInfo.beginActivity` prevents App Nap delaying Tier 3 re-alerts                      | A critical re-alert could be delayed exactly when it matters                                                                                                                                                      | Investigate `IOPMAssertion`; failing that, document prominently                                                                                  | M4                                                                                         |
| `NSStatusItem` preferable to `MenuBarExtra` for dynamic title and icon                      | Wasted effort; contained blast radius                                                                                                                                                                             | Switch; menu contents are SwiftUI either way                                                                                                     | M2                                                                                         |
| Global hotkey acknowledgement achievable without a separate Input Monitoring grant          | An extra TCC prompt, harming onboarding                                                                                                                                                                           | Drop the hotkey; panel and menu acknowledgement remain                                                                                           | M4                                                                                         |
| `com.apple.screenIsLocked` distributed notifications remain reliable on macOS 26            | `screenLocked` becomes unreliable                                                                                                                                                                                 | `CGSessionCopyCurrentDictionary` polling on a slow interval                                                                                      | M5                                                                                         |

---

## 12. Milestones

|        | Delivers                                                                                                                                                            | Rationale                                                                                                                                                     |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **M1** | `AXBannerWatcher` + `BannerTreeLocator` + `NotificationFieldExtractor`, printing app/title/body to a debug console                                                  | Proves the single riskiest unknown before anything else is built                                                                                              |
| **M2** | Inspector with ring buffer, Accessibility **and notification** permission onboarding, canary with §9.2 cause-splitting, ~~`INFocusStatusCenter` spike~~ (done — condition dropped) | Do not build atop a pipeline that cannot be proven alive                 |
| **M3** | Rule AST, `RuleEngine`, JSON store, visual builder, Tier 1 with sound **and speech** actions, **mute walkthrough**                                                  | First genuinely useful build. The mute step ships _with_ the first sound — shipping sound first would layer it over the source app's own ping and feel broken |
| **M4** | Full ladder: `AlertPanel` with stacking, repeat with capping, `ShortcutRunner`, concurrent-escalation semantics, acknowledge-all                                    |                                                                                                                                                               |
| **M5** | Text DSL with round-tripping; time/day, on-call, screen-lock, frequency conditions; regex operator with bounding                                             |                                                                                                                                                               |
| **M6** | Degraded-mode UX across all three alarm channels, re-attach hardening, snooze polish, fixture corpus formalised                                                     | Robustness is easiest to get right against a real working pipeline                                                                                            |

**M3 is the first build that solves the stated problem** — a loud, distinct alert for Teams @mentions and silence for everything else.

---

## 13. Out of scope

| Excluded                                            | Reason                                                                                                                                                                |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom icons on system banners                      | Not achievable without private internals (§3)                                                                                                                         |
| Mac App Store distribution                          | Sandbox blocks Accessibility (§2)                                                                                                                                     |
| usernoted SQLite DB in the live pipeline            | Rows written only after the banner leaves screen; TCC-protected on macOS 15+; path has moved between releases. Realtime-useless. May return as a manual audit feature |
| **Automatic per-notification bundle-ID resolution** | AX exposes no identifier and no reliable general solution exists. Distinct from the supervised one-off lookup in §8.2                                                 |
| Per-rule snooze                                     | State becomes unreasonable to hold in mind                                                                                                                            |
| Rule history / undo                                 | Single-user tool; the Inspector makes recreating a rule fast                                                                                                          |
| Statistics dashboard                                | Serves no stated need                                                                                                                                                 |
| Webhooks / scripting engine                         | Shortcuts (Tier 4) covers it better                                                                                                                                   |
| Siri voices for speech                              | Unavailable to `AVSpeechSynthesizer`; silently substituted (§5.9)                                                                                                     |
| Mixing concurrent alert audio                       | Serialised instead — two alarms at once is noise, not information (§5.15)                                                                                             |
| Licensing, activation, pricing                      | Personal tool                                                                                                                                                         |

---

## 14. Provisional defaults

Chosen now so M4 planning is not blocked mid-stream. All user-adjustable.

| Setting                     | Default            | Reasoning                                                                                        |
| --------------------------- | ------------------ | ------------------------------------------------------------------------------------------------ |
| Tier 2 delay                | 10 s               | Long enough that a glance at the banner suffices; short enough to catch you before you look away |
| Tier 3 interval             | 30 s               | Insistent without being frantic                                                                  |
| Tier 3 `maxRepeats`         | 20                 |                                                                                                  |
| Tier 3 `maxDurationSeconds` | 600 (10 min)       | Whichever cap trips first. Settable to `nil` for true unlimited (§5.12)                          |
| Tier 4 delay                | 120 s              | Two minutes unacknowledged is a fair signal you are not at the Mac                               |
| Sleep staleness threshold   | 300 s              | Above this, convert to "missed while asleep" rather than resume                                  |
| Canary interval, off-call   | 30 min             |                                                                                                  |
| Canary interval, on-call    | 5 min              |                                                                                                  |
| Regex match budget          | 50 ms              |                                                                                                  |
| Regex subject cap           | 4 KB               |                                                                                                  |
| Default speech template     | `"{app}: {title}"` | Bodies are frequently far too long to read aloud                                                 |

---

## 15. Remaining open question

**Default sound set and licensing.** Which alert sounds ship with the app, and under what licence? Relevant if open-sourced — bundled audio must be originally created or permissively licensed. Deferrable to M3; macOS system sounds can be referenced by name in the interim.
