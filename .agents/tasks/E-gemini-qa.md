# Task E (Gemini): docs + QA — you own README.md, CHANGELOG.md, docs/TESTING.md, test/integration_like/

Read AGENTS.md, docs/CONCEPT.md, docs/ARCHITECTURE.md and the current code.
1. README.md (Dutch, warm and compact, no em-dashes): wat DOT is, installeren (APK uit GitHub Releases, DMG + rechtsklik Open omdat de app niet genotariseerd is), eerste koppeling stap voor stap, privacy (alles lokaal, versleuteld), bekende beperkingen (zelfde wifi, gastnetwerken met client isolation werken niet, Android stopt achtergrondverbinding), ontwikkelen (flutter run -d macos, flutter run -d <android>), release maken.
2. CHANGELOG.md with a `## v0.1.0` section.
3. docs/TESTING.md: manual test plan mapping each acceptance criterion from CONCEPT.md to concrete steps (guest network, sleeping MacBook, restart, denied permissions, low storage, version mismatch).
4. Review lib/core and lib/sync for bugs against ARCHITECTURE.md sync rules; write extra failing-then-passing tests in test/integration_like/ only (don't edit lib/). List suspected bugs in your report with file:line.
`flutter test` green for your tests (mark known-bug tests with skip and a reason). Report.
