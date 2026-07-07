# Contributing to CodexBrain

Thanks for looking under the hood. This project values small, verified changes over big clever ones.

## Dev setup

```bash
git clone https://github.com/maxrotemberg04-spec/codexbrain-app.git
cd codexbrain-app
swift build                     # debug build
.build/debug/CodexBrain selfcheck   # 27 assertions must pass
./install.sh --open             # release build + app bundle + CLI link
```

Requires macOS 14+ and Xcode command line tools. There are **zero dependencies** — please keep it that way; a new package needs a very good reason.

## Where things live

```
Sources/CodexBrain/
  Entry.swift        CLI dispatch or app launch
  Brain/             pure logic, UI-free, covered by selfcheck
    Models.swift     Note, HomeBoard (task parsing), config
    Scanner.swift    folder walk -> notes (+ change detection)
    Index.swift      BRAIN-INDEX.md writer
    Retrieval.swift  deterministic ask: keywords -> score -> one file -> one section
    Panels.swift     subscriptions / brief file parsing
    CLI.swift        ask/remember/reindex/selfcheck
  App/               SwiftUI layer (dashboard, graph, browse, menu bar)
```

## Ground rules

1. **`selfcheck` is the gate.** New parsing or retrieval logic gets an assertion in `SelfCheck.run()`. UI changes don't need tests, but must not break existing ones.
2. **Files are the only state.** No databases, no caches that can drift. If a feature needs state, it's a markdown or JSON file a human can read and an agent can write.
3. **Deterministic before intelligent.** Retrieval, indexing, and parsing stay plain code. AI belongs *outside* the binary (agents writing files the app renders).
4. **Match the style.** One accent color, hairline strokes, no new fonts, comments only for the WHY.

## Pull requests

- Keep the diff focused; unrelated cleanups go in their own PR.
- Say what you verified: `swift build` clean + `selfcheck` output in the PR description.
- Screenshots for anything visual.
