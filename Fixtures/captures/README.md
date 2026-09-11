# Capture fixtures

Recorded AX shapes used to test `NotificationFieldExtractor`.

## Redaction is mandatory

These files are committed to git and this project may be open-sourced.
Fixtures capture **structural shape only**. Before committing any recorded
string, replace every piece of human content with a synthetic placeholder:

- Real person names -> `Alex Example`, `Sam Placeholder`
- Real message bodies -> `Placeholder body text`
- Real channel or team names -> `General`, `Example Channel`
- App names are **kept verbatim** — they are not personal data and the
  parser's behaviour depends on them (e.g. names containing commas).

## Format

One file per observed shape, named `<os-version>-<app>-<variant>.txt`,
containing only the `AXAttributedDescription` string, with a leading
comment line recording where it came from.

    # macOS 26.7, Microsoft Teams, @-mention in a channel
    Microsoft Teams, Alex Example\nPlaceholder body text
