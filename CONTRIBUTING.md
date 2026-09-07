# Contributing

PRs are welcome. Issues too — a bug you hit on a real lock screen is worth more than a perfect patch.

## Before you write code

1. Open an issue if the change is more than a small fix, so we agree on the shape first.
2. Fork the repo and branch off `main`.

## Dev setup

Clone the repo and build. Details, packaging, SkyLight notes, and test checklists live in [Development](docs/development.md).

```bash
make build
make settings    # optional: open Settings against the build
```

Lock with **Control-Command-Q** to judge Lock Screen placement. `--debug --force-clock` only puts the clock on the desktop for styling — it is not the real Lock Screen.

## What a good PR looks like

- One idea per PR.
- `make build` stays green.
- Match the style already in `LockClock/`. Keep the surface small; this is an AppKit menu-bar agent, not a framework dump.
- If you touch lock-screen layout, say how you checked it (real lock, screenshot, or `make calibrate` if relevant).
- Do not add App Sandbox, Accessibility, or Screen Recording requirements unless we explicitly agree to that trade-off.

## Opening the PR

Push your branch and open a pull request against `main`. Say what you changed and how you tried it (locked screen, Settings only, or both).

I will review when I can — that's a weekend project, so please don't hate me if it takes a while.  
Thank you for taking the time. :)
