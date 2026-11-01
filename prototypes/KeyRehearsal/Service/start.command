#!/bin/zsh
set -e
cd "${0:A:h}"
export PATH="$PWD/.venv/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if [[ ! -x .venv/bin/python ]]; then
  echo 'Setup diperlukan. Jalankan ./setup.command sekali, lalu ulangi ./start.command.'
  exit 1
fi
if ! command -v ffmpeg >/dev/null; then
  echo 'FFmpeg belum tersedia. Ikuti README-PRE.md.'
  exit 1
fi
exec .venv/bin/python -m uvicorn server:app --host 0.0.0.0 --port 8765 --workers 1
