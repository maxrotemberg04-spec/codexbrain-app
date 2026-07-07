# CodexBrain

![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white) ![Zero dependencies](https://img.shields.io/badge/dependencies-0-2ea44f) ![License: MIT](https://img.shields.io/badge/license-MIT-blue)

**A native macOS command center + deterministic brain for your markdown folders.**

Point it at any folders of markdown notes and you get: a founder dashboard (tasks, calendar, briefing, projects), an interactive knowledge graph, instant cited retrieval for AI agents, and full-text search — with zero lock-in. Your notes stay plain `.md` files on disk; Obsidian and every other tool keep working alongside it.

## Why it exists

Most second-brain tools treat your vault as a generic pile of files. CodexBrain is opinionated: it knows your `HOME.md` is the hub, your inbox needs triage, and your agents need retrieval that doesn't burn tokens. It was built on the principles from the "deterministic code before the model" school of agent memory:

1. **One small index of everything** — `BRAIN-INDEX.md`, one line per note, rebuilt on every launch/save/capture so it can never drift from disk.
2. **Deterministic retrieval** — `codexbrain ask "question"` strips your question to keywords, scores every note *from the index without opening files*, opens exactly one file, extracts the best section, follows at most one `[[wikilink]]` pointer, and prints the answer **with its source**. ~10 ms, zero model calls.
3. **Files are the only state** — agents and humans edit the same markdown; the app watches and follows.

## The app

- **⌘K Ask-your-brain** — a floating glass command bar over everything: notes rank as you type, verbs act (`add …` → today list, `capture …` → inbox, `cal` → jump), and a real question returns the answer from your own vault with the source cited, in milliseconds, zero AI calls.
- **Dashboard** — north star + today list parsed live from your `HOME.md` (checkboxes write back to the file), a 7-day planner built from your own week tasks (tag a day with `- [ ] Wed: thing` or leave it in the Anytime lane), an agent-written daily briefing (with a computed fallback digest), projects switchboard, subscriptions tracker, pinned folders.
- **Calendar** — an Apple-Calendar-style month view over a plain `CALENDAR.md` (`- [ ] 2026-07-12 @teal The thing`): click a day, add color-coded items, check them off. Repo-synced, agent-writable.
- **Graph** — your vault as a force-directed constellation: notes are nodes, wikilinks are edges, colors are folders. Drag to arrange, hover to focus a neighborhood, click to open.
- **Browse & search** — ranked full-text search, themed reading pane (Obsidian callouts, highlights, tags, wiki-link navigation), edit with ⌘S.
- **Capture** — ⌘N in the app, or the ✦ menu bar item from anywhere on your Mac; both write to your inbox and update the index instantly.
- **Self-updating** — the toolbar Update button pulls the repo and rebuilds, and a quiet background pull (~5 min, only when the working tree is clean) picks up pushes from teammates, other machines, or agents acting on your messages.

## Install

Requires macOS 14+ and Xcode command line tools (Swift 5.9+). No other dependencies — the whole app is one Swift package.

```bash
git clone https://github.com/maxrotemberg04-spec/codexbrain-app.git
cd codexbrain-app
./install.sh --open
```

Then click **Add Folder** and pick your markdown folders. Optional: create a `HOME.md` at a folder root with `## NORTH STAR`, `## ✅ TODAY`, and `## 🗓 THIS WEEK` sections to light up the dashboard.

The CLI gets linked as `codexbrain`:

```bash
codexbrain ask "what is my north star"   # best section + source path, no AI
codexbrain remember "some fact"          # append to inbox + reindex
codexbrain reindex                       # rebuild BRAIN-INDEX.md
codexbrain selfcheck                     # 28 built-in assertions
```

## Agents

Agents never need the GUI — they read `BRAIN-INDEX.md` (or run `codexbrain ask`), write markdown, and the app follows within seconds (stat-only change detection every 12 s plus rescan on focus). One optional file contract lights up the Briefing panel:

- `reports/daily-brief.md` — a `# title` plus `- bullets`; the Briefing card renders the newest one and falls back to a computed digest when stale.

## Design notes

Native SwiftUI, zero dependencies, ~2k lines. Dark-first with one amber accent, hairline strokes, a serif reserved for the north-star line. Retrieval is word-boundary scored (title, headings, description, folder, content) with a recency nudge. The graph runs a plain O(n²) force simulation in a Canvas — smooth well past a thousand notes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — zero dependencies, `selfcheck` is the gate, files are the only state.

## License

MIT © Max Rotemberg
