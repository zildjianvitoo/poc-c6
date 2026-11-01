#!/bin/zsh
set -e
cd "${0:A:h}"
# All runtimes stay inside the project, including on macOS versions Homebrew cannot identify.
if [[ ! -x .setup-tools/bin/uv ]]; then
  python3 -m venv .setup-tools
  .setup-tools/bin/python -m pip install uv
fi
export UV_PYTHON_INSTALL_DIR="$PWD/.python"
.setup-tools/bin/uv venv --python 3.11 --allow-existing .venv
.setup-tools/bin/uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python configure_ffmpeg.py
.setup-tools/bin/uv pip check --python .venv/bin/python
.venv/bin/python -c 'import demucs, faster_whisper, soundfile, uvicorn; from basic_pitch.inference import predict; print("Paket analisis siap.")'
echo 'Setup selesai. Jalankan ./start.command dan salin alamat serta token ke aplikasi iPhone.'
