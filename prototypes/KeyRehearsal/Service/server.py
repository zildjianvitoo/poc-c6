"""Local single-user PoC service. Run one worker, only on a trusted LAN."""
import asyncio
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import socket
import threading
import uuid

from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import FileResponse
from pipeline import run

ROOT = Path(os.environ.get('COVER_DATA', './jobs')).resolve()
ROOT.mkdir(parents=True, exist_ok=True)
TOKEN = os.environ.get('COVER_TOKEN') or secrets.token_urlsafe(24)
print(f'\nAlamat iPhone: http://{socket.gethostname().split(".")[0]}.local:8765\nToken koneksi: {TOKEN}\n', flush=True)
app = FastAPI(title='Cover Pre PoC')
executor = ThreadPoolExecutor(max_workers=1)
lock = threading.Lock()
active = False
jobs = {}
MAX_BYTES = 100 * 1024 * 1024


def authorize(request: Request):
    if not secrets.compare_digest(request.headers.get('authorization', ''), 'Bearer ' + TOKEN):
        raise HTTPException(401, 'Token tidak cocok')


def process(job_id, start, end):
    global active
    folder = ROOT / job_id
    def progress(message):
        with lock:
            jobs[job_id] = dict(id=job_id, status='processing', message=message)
    try:
        result = run(folder, start, end, progress)
        result_path = folder / 'result.json'
        result_path.write_text(json.dumps(result))
        record = dict(id=job_id, status='complete', message='Panduan siap', result=result)
    except Exception as exc:
        # Full traceback stays on the developer's Mac; user receives a useful failure.
        import traceback
        traceback.print_exc()
        record = dict(id=job_id, status='failed', message=f'Analisis gagal ({type(exc).__name__}). Periksa terminal Mac, model, dan FFmpeg; lalu coba lagi.')
    with lock:
        jobs[job_id] = record
        active = False


@app.get('/health', dependencies=[Depends(authorize)])
def health():
    return {'status': 'ok', 'ffmpeg': shutil.which('ffmpeg') is not None}


@app.post('/jobs', dependencies=[Depends(authorize)], status_code=202)
async def create(request: Request, start: float, end: float):
    global active
    if not all(map(math.isfinite, [start, end])) or start < 0 or not 1 <= end-start <= 60 or end > 1800:
        raise HTTPException(422, 'Pilih potongan 1–60 detik dalam audio maksimal 30 menit')
    with lock:
        if active:
            raise HTTPException(409, 'Mac sedang memproses lagu lain. Tunggu lalu coba lagi.')
        active = True
    job_id = str(uuid.uuid4())
    folder = ROOT / job_id
    try:
        folder.mkdir()
        size = 0
        with (folder / 'source').open('wb') as output:
            async for chunk in request.stream():
                size += len(chunk)
                if size > MAX_BYTES:
                    raise HTTPException(413, 'Ukuran maksimal 100 MB')
                output.write(chunk)
        if size == 0:
            raise HTTPException(400, 'Audio kosong')
        record = dict(id=job_id, status='queued', message='Menunggu analisis…')
        with lock:
            jobs[job_id] = record
        executor.submit(process, job_id, start, end)
        return record
    except BaseException:
        with lock:
            active = False
        shutil.rmtree(folder, ignore_errors=True)
        raise


def get_job(job_id):
    try:
        if str(uuid.UUID(job_id)) != job_id:
            raise ValueError()
    except ValueError:
        raise HTTPException(404, 'Pekerjaan tidak ditemukan')
    with lock:
        record = jobs.get(job_id)
    if record:
        return record
    saved = ROOT / job_id / 'result.json'
    if saved.exists():
        return dict(id=job_id, status='complete', message='Panduan siap', result=json.loads(saved.read_text()))
    raise HTTPException(404, 'Pekerjaan tidak ditemukan atau service restart. Coba analisis ulang.')


@app.get('/jobs/{job_id}', dependencies=[Depends(authorize)])
def status(job_id: str):
    return get_job(job_id)


@app.get('/jobs/{job_id}/{track}', dependencies=[Depends(authorize)])
def audio(job_id: str, track: str):
    if track not in ('vocals', 'backing') or get_job(job_id)['status'] != 'complete':
        raise HTTPException(404, 'Track belum tersedia')
    return FileResponse(ROOT / job_id / f'{track}.wav', media_type='audio/wav')
