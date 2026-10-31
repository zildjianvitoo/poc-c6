# AGENTS.md — rules for AI coding agents

iOS PoC "C6": song cover recording with auto-rewind and auto-comping.
Stack: iOS 18, iPhone only, portrait, Swift 5 language mode, SwiftUI, Clean Architecture + MVVM (`@Observable` ViewModels).

## Read first
1. `docs/prd.md` — the spec.
2. `docs/COLLABORATION.md` — folder ownership, contract-change process, conventions.
3. `docs/backlog/<name>.md` — the task list of the person you are helping. **Only work on the task IDs they give you.**
4. Everything in `poc-c6/Domain/` — the shared data contracts. Use these types; never create parallel versions (e.g. no new `Segment` when `SongSegment` exists).

Ignore `docs/archive/` (outdated PRD) and `docs/review-*.md` (discussion notes; decisions are already in the PRD).

## Do not modify without explicit permission from the user
- `poc-c6/Domain/Entities/`, `poc-c6/Domain/Repositories/`, `poc-c6/Domain/Contracts/` — shared contracts. If you believe a contract must change, STOP and explain the proposal instead of editing. Never change a contract to make a build error go away.
- `poc-c6.xcodeproj/` — build settings are owned by one person.
- `scripts/` and `.githooks/`.
- Folders owned by other team members (see `docs/COLLABORATION.md` §2).

## Code rules
- Every non-UI type (capture, DSP, playback, analysis, composition, use cases, repositories) is declared `nonisolated`. The project defaults to MainActor isolation; realtime audio/video callbacks must never call MainActor code.
- ViewModels: `@Observable`, MainActor (default). Views call ViewModels, ViewModels call Use Cases, never AVFoundation/CoreML directly.
- No magic numbers: thresholds and durations come from `PoCConfiguration`.
- Never use `Timer`, `Date()` or a stopwatch for video cut points. Use the capture session clock and file time (`docs/prd.md` §7.1).
- Time units: `TimeInterval` seconds on the song timeline, `CMTime` for the capture clock and video file time.
- Segment indices are zero-based; UI shows `index + 1`.
- `poc-c6/Domain/` may import only `Foundation` and `CoreMedia`.
- One primary type per file, file name = type name, same file header style as existing files.
- UI text in English.

## Where files go
- Swift code: inside `poc-c6/` (synchronized folder, picked up by Xcode automatically).
- Docs, scripts, other non-code files: outside `poc-c6/`. A `.md`/`.json`/`.txt` inside `poc-c6/` gets bundled into the app.
- Never commit copyrighted songs, recorded videos, or `xcuserdata/`.

## Before you finish
- The app builds: `xcodebuild -project poc-c6.xcodeproj -scheme poc-c6 -destination 'generic/platform=iOS Simulator' build`
- If anything in `poc-c6/Domain/` was touched: `./scripts/check-contracts.sh` passes.
- If anything in `poc-c6/Data/Composition/` was touched: `./scripts/check-comping.sh` passes.
- At handoff points, call the contract checks (`validate()` / `Contract.assertValid`), see `docs/COLLABORATION.md` §4.

## Branches
- **Never commit or push to `main`.** Each person works on their own branch: `ikzaz`, `takin`, `zildjian`. Before making changes, check the current branch (`git branch --show-current`); if it is `main`, stop and ask the user to switch.
- Contract changes go on a short `contract/<topic>` branch instead (see `docs/COLLABORATION.md` §3).
- Never force-push. Bring in `main` with `git merge origin/main`, not rebase.

## Commits
Every commit message follows **Conventional Commits**: `<type>(<optional scope>): <description>`, e.g. `feat(capture): write raw video with AVAssetWriter`. Allowed types and scopes: `docs/COLLABORATION.md` §6. The `commit-msg` hook in `.githooks/` rejects anything else.
