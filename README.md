# PoC C6 — Song Cover Recording & Auto-Comping

iOS 18 PoC (iPhone, portrait, SwiftUI). Sing a song segment by segment: the app rewinds a segment until your pitch passes, keeps one uninterrupted camera recording, then cuts the passed takes together with the instrumental into one cover video.

## Start here
| Doc | What it is |
|---|---|
| [docs/prd.md](docs/prd.md) | The spec |
| [docs/COLLABORATION.md](docs/COLLABORATION.md) | How we work: folders, contracts, git, conventions |
| [docs/backlog/](docs/backlog/) | Tasks per person |
| [AGENTS.md](AGENTS.md) | Rules for AI coding agents |

## Setup
```bash
git clone https://github.com/zildjianvitoo/poc-c6.git
cd poc-c6
git config core.hooksPath .githooks   # enforces Conventional Commits
git switch -c <your-name> origin/main # ikzaz, takin or zildjian
```
Open `poc-c6.xcodeproj`, run on a physical iPhone for camera and microphone.

## Checks (run on the Mac, no simulator needed)
```bash
./scripts/check-contracts.sh   # Domain contracts and handoff rules
./scripts/check-comping.sh     # comping: cut accuracy, sync, crossfades, partial export
```

## Team
| Person | Area | Branch |
|---|---|---|
| Ikzaz | Song preparation: import, stems, guide, segments, transposition, vocal range | `ikzaz` |
| Takin | Recording session: capture, playback, live pitch, piano roll, evaluation loop | `takin` |
| Zildjian Vito | Comping & export, app shell, integration | `zildjian` |
