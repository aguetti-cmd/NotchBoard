# NotchBoard 2

A native macOS notch panel: Apple Music, today's agenda and reminders, weather,
and local Claude Code usage. Rebuilt from scratch on 2026-11-16. The v1 code is
not reused.

## Run it

```bash
./scripts/build-app.sh --install     # builds, signs ad hoc, copies to ~/Applications
open ~/Applications/NotchBoard.app
```

Hover the notch to open the panel. Move away and it closes. The pin button in
the panel header, or **Keep Open** in the menu bar icon, holds it open.

On a Mac without a notch (the mini), a black pill sits at the top centre of
the main display instead.

Tests (pure logic only):

```bash
swift test
```

## What it shows

| Card | Source | Notes |
|---|---|---|
| Music | Apple Music via AppleScript | Never launches Music. Polls every 5 s collapsed, 1 s open, plus Music's own change notification. Artwork in the collapsed wings while playing. |
| Agenda | EventKit | Remaining events today and tomorrow (3 shown), reminders due today or overdue (3 shown). Click the circle to complete a reminder. |
| Weather | Open-Meteo, no key | Defaults to Bangkok. Change the city in Settings. Refreshes every 30 min. |
| Claude today | `~/.claude/projects/**/*.jsonl` | Local only, nothing sent. Total tokens today (cache reads included), output tokens, sessions, 7-day bars. Responses are deduped by message and request id. Shows this Mac's usage only. No cost estimate. |

## Permissions

The first launch asks for Calendars and Reminders. The first Music refresh
asks to control Music (Automation). Settings has a row for each with a
shortcut to the right System Settings pane.

The build is signed ad hoc, so macOS may ask again after a rebuild. A stable
signing identity (Xcode, Settings, Accounts, free personal team) would stop
that. Not set up yet.

## Layout

```
Sources/NotchBoardCore/   pure logic, tested: usage parsing and scanning,
                          Open-Meteo decoding, Music script parsing, notch geometry
Sources/NotchBoard/
  App/                    entry point, AppDelegate (menu bar item), AppModel, Preferences
  Notch/                  NotchController (panel, placement, hover), root and expanded views
  Features/<Name>/        one service plus one card per feature
  Settings/               settings window
  Support/                AppleScript runner
Resources/Info.plist      bundle id local.notchboard, LSUIElement, usage strings
scripts/build-app.sh      release build into build/NotchBoard.app
```

## Debug aids

- `NotchBoard --pinned` starts open and pinned.
- `NotchBoard --snapshot out.png` renders the open panel offscreen after 6 s and quits.
  Calendar and Reminders show as denied when the binary is started from a shell.
- `NOTCHBOARD_DEBUG=1` logs screen, notch and panel geometry to stderr.

## Lessons carried from v1

- Show a clear, short state for every failure. Never surface raw AppleScript errors.
- Browser YouTube control needs JavaScript from Apple Events or Accessibility.
  Out of scope for v2.0 (Apple Music only).

## Not in 2.0

Spotify and browser media, clipboard history, global hotkey, location-based
weather, Claude plan quota (no local source for it).
