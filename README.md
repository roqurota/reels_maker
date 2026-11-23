# Reels Studio

Mac app (SwiftUI) for ordering band reels from Claude: pick a song, parts and a template per part, and the app queues the jobs and runs `claude -p` with the matching reels skill. DaVinci Resolve is opened automatically when a template needs it.

## Build

```bash
./build-app.sh
```

Builds `build/Reels Studio.app` (release, ad-hoc signed). Needs Xcode / Swift 5.10+, macOS 14+.

## How it works

- **Songs**: read from `Songs/<song>/Titles` (`<Part>.wav` + `<Part>_words.srt`); description, mood, colors, media folders and the Pexels switch live in `songs.json`.
- **Templates = skills**: every template points to a skill in `~/.claude/skills`. New templates from a reference create a skill; template edits and liked revisions are written into it. Backups go to `_studio/skills`.
- **Queue**: one job at a time; `Доработать` resumes the same Claude session.
- **Journal**: finished reels with published / not published status.

App data lives next to the reels, in `Reels Claude/_studio/` (`songs.json`, `templates/`, `jobs.json`, `reels.json`, `pexels/`, `skills/`). Reels go to `Reels Claude/<yyyy-MM-dd>/<song>/`.

Requires the Claude Code CLI signed in (`claude auth login`).

## Icon

`Resources/icon_source.png` is the artwork; `Resources/AppIcon.icns` is built from `Resources/icon_1024.png`.
