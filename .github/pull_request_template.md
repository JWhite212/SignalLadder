## What this changes

<!-- What does a user notice, or what does it fix? One or two sentences. -->

## Why

<!-- The problem it solves. Link the issue if there is one: Fixes #… -->

## How it was checked

<!-- Tests added or changed, and anything you checked by hand on a real Mac. -->

- [ ] `swift test` passes
- [ ] If this touches capture, health or audio: checked on a running build (`Scripts/verify-live.sh` where it applies), and said which macOS version
- [ ] If this changes the rules file: `docs/rules-format.md` is updated, and older files still load
- [ ] No notification text reaches a log, a file on disk, a fixture or a screenshot
