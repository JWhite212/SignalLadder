# Writing rules by hand

Until the rule editor arrives (M3c), rules live in a JSON file you edit yourself. In M3a a rule's only effect is to mark matching notifications in the Inspector — nothing makes a sound yet — so you can prove a rule against real traffic before it is ever trusted to wake you.

## Where the file is

```
~/Library/Application Support/com.jamiewhite.signalladder/rules.json
```

Use **Edit Rules File…** (⌘E) in the menu. If the file does not exist it is created with one example rule, switched off, and opened in your default JSON editor. SignalLadder never writes to this file again — not to tidy it, not to replace it if it breaks. It is yours.

After saving, choose **Reload Rules** (⌘R).

## The shape

```json
{
  "version": 1,
  "rules": [
    {
      "name": "Prod and incident channels",
      "enabled": true,
      "condition": {
        "or": [
          { "field": "title", "op": "matches", "value": "#prod-*" },
          { "field": "title", "op": "matches", "value": "#incident-*" }
        ]
      }
    }
  ]
}
```

| Key         | Required | Meaning                                                               |
| ----------- | -------- | --------------------------------------------------------------------- |
| `version`   | yes      | Always `1` for now                                                    |
| `name`      | yes      | Shown in the Inspector and menu when the rule matches                 |
| `enabled`   | no       | Defaults to **true** — a rule you wrote runs unless you say otherwise |
| `id`        | no       | Generated if absent                                                   |
| `condition` | yes      | See below                                                             |

**Order is priority.** The first enabled rule that matches wins, and a notification only ever matches one rule. Put narrow rules above broad ones.

## Conditions

A condition is exactly one of these:

```json
{ "field": "title", "op": "contains", "value": "deploy" }
{ "and": [ condition, condition, ... ] }
{ "or":  [ condition, condition, ... ] }
{ "not": condition }
```

### Fields

Open the Inspector to see what each field actually holds for a given app — that is what it is for.

| Field      | Holds                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------- |
| `app`      | The app's display name, e.g. `Microsoft Teams`. Recovered heuristically from the banner            |
| `title`    | The banner's first line                                                                            |
| `subtitle` | The second line when there is one; empty otherwise                                                 |
| `body`     | The message text                                                                                   |
| `raw`      | Everything the banner said, unparsed — use it when you are not sure which field something lands in |
| `subrole`  | The banner's accessibility type, e.g. `AXNotificationCenterBanner` or `AXNotificationCenterAlert`  |

### Operators

All comparisons ignore case and accents: `microsoft teams` matches `Microsoft Teams`, `equipe` matches `Équipe`.

| `op`        | Matches when the field…                                                                | Example                                                                         |
| ----------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `equals`    | is exactly the value                                                                   | `{"field": "app", "op": "equals", "value": "Weather"}`                          |
| `notEquals` | is anything but the value                                                              | `{"field": "subrole", "op": "notEquals", "value": "AXNotificationCenterAlert"}` |
| `contains`  | contains the value anywhere                                                            | `{"field": "body", "op": "contains", "value": "rollback"}`                      |
| `matches`   | matches the whole field as a pattern: `*` is any run of characters, `?` is exactly one | `{"field": "title", "op": "matches", "value": "#prod-*"}`                       |

`matches` covers the **whole** field: `#prod-*` means "starts with `#prod-`", and `*deploy*` means "contains `deploy`". There is no way to match a literal `*` or `?`.

`equals` with an empty value is allowed and useful: `{"field": "subtitle", "op": "equals", "value": ""}` means "has no subtitle".

## When something is wrong

A broken rule never silences the others. The menu shows a warning, the status icon changes, and each problem is listed by position and name:

```
⚠︎ Rules: 2 active — 1 could not be used
    Rule 3 ("Typo"): Cannot initialize Operator from invalid String value startsWith at rules[2].condition.op
```

| Message                                                          | Means                                                                                               |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `not valid JSON: …`                                              | A syntax error — the detail includes the line and column. **No rules are active** until it is fixed |
| `missing "op" at rules[0].condition.and[1]`                      | That condition has no `op` key                                                                      |
| `a condition needs exactly one of "and", "or", "not" or "field"` | An object mixes two kinds of condition, or is neither                                               |
| `an "and" group is empty, so it would match everything`          | Rejected: a half-written rule would fire on every notification                                      |
| `an "or" group is empty, so it could never match`                | Rejected: the rule could never fire                                                                 |
| `"body contains" has an empty value`                             | Rejected: an empty `contains` or `matches` never does what was meant                                |
| `it has no name`                                                 | Rejected: nothing could say which rule matched                                                      |
| `Rules file needs a newer SignalLadder (format 2)`               | The file was written by a newer build. Nothing is loaded rather than misread                        |

## Testing a rule before you trust it

1. Let some real notifications arrive, or open the Inspector (⌘I) to see what is already there.
2. Write or edit a rule and save.
3. **Reload Rules** (⌘R).

Every notification already in the Inspector is re-checked against the new rules. The menu shows **Current rules match _n_ of the last _m_**, and each row whose verdict changed shows a blue line: _Current rules would match …_ or _Current rules would match nothing_.

That blue line is a preview. The line above it still says what actually happened when the notification arrived — a preview never rewrites the record. Once SignalLadder can make sounds, that difference will matter: _Matched …_ will mean an alert played.
