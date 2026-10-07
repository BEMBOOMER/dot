# DOT — agent instructions

You are one of several coding agents (Codex, Copilot, Antigravity, Gemini, Freebuff) building DOT together.
Claude is the reviewer/orchestrator: it assigns tasks, then runs analyze/tests/builds and reviews your diff.

Read first: `docs/CONCEPT.md` (product spec, Dutch) and `docs/ARCHITECTURE.md` (contract: stack, folder ownership, protocol, sync rules).

Rules
- Flutter/Dart, targets android + macos only. App id `com.bemooks.dot`.
- Only edit the folders your task assigns you. If you must touch another folder, keep it minimal and list it in your final report.
- `lib/core` is the shared API. Don't change public signatures in it unless your task says so.
- UI copy in Dutch, code/comments in English. No em-dashes (—) in UI copy.
- Paths contain spaces and `&`: always quote paths in shell commands.
- Flutter binary: `/opt/homebrew/bin/flutter`. Java: `/opt/homebrew/opt/openjdk@17`.
- Before finishing: run `flutter analyze` (zero errors) and `flutter test` for what you touched. Do NOT commit; the reviewer commits.
- End with a short report: files changed, what works, what is untested or stubbed.
