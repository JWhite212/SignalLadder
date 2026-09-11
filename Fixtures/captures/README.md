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

    # macOS 26.7, Microsoft Teams, channel message
    Microsoft Teams, Alex Example, Placeholder body text

Note the format is comma-joined with no newline, and a banner's text children
carry the same fields already separated — see the M1 findings note. No corpus
has been recorded yet; this directory is scaffolding for a later milestone.
