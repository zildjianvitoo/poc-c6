# Roadmap Peningkatan Akurasi — PoC C6

Dokumen ini menjelaskan posisi akurasi di Phase 1 dan arah pengembangan berikutnya untuk meningkatkan akurasi. Ada **dua jenis akurasi** yang berbeda dan perlu ditingkatkan secara terpisah:

| | Apa | Kenapa penting |
|---|---|---|
| **A. Akurasi guide (offline)** | Seberapa tepat target note (MIDI) yang diekstrak dari lagu referensi | Kalau guide salah, user dinilai "salah" walau nyanyinya benar |
| **B. Akurasi live pitch (realtime)** | Seberapa tepat pitch suara user terdeteksi saat merekam | Menentukan warna trail hijau/merah dan skor SUDAH/BELUM |

Akurasi A adalah masalah terbesar di Phase 1. Akurasi B relatif lebih mudah karena input-nya suara user sendiri (monofonik, lewat mic, tanpa musik karena pakai earphone).

---

## Phase 1 — Kondisi sekarang (native, tanpa model ML)

**Cara kerja:**
- Guide: lagu full-mix → band-pass filter 80–1100 Hz → YIN/autocorrelation tiap 40 ms → nada stabil ≥ 120 ms dijadikan `TargetMIDINote`.
- Live: mic → noise gate −40 dB → YIN tiap 50 ms → bandingkan dengan target, toleransi ±50 cents.

**Keterbatasan yang diketahui:**
- Band-pass tidak memisahkan vokal dari instrumen lain di rentang yang sama (gitar, piano, synth, string). YIN sering "menangkap" instrumen, bukan vokal.
- Sering terjadi **octave error** (nada terdeteksi 1 oktaf terlalu tinggi/rendah).
- Bagian lagu yang musiknya ramai (reff/chorus) biasanya paling tidak akurat.
- Lagu yang tuning-nya tidak tepat A = 440 Hz akan membuat semua note bergeser sedikit.

**Mitigasi di Phase 1:**
- Disclaimer "Mode Eksperimental" di UI (layar proses ekstraksi + badge di layar rekam).
- Demo track bawaan dengan guide yang sudah diverifikasi, supaya alur PoC bisa didemokan dengan akurat.

---

## Phase 1.5 — Quick wins tanpa model ML

Perbaikan yang masih native (`Accelerate`/`AVFoundation`) dan murah dikerjakan:

1. **Mid/side extraction** — vokal utama hampir selalu di tengah stereo. Ambil komponen *mid* `(L+R)/2` dan kurangi kontribusi *side* untuk menonjolkan vokal sebelum deteksi pitch.
2. **Confidence threshold YIN** — buang frame dengan nilai aperiodicity tinggi (tidak yakin) daripada memaksa jadi note.
3. **Smoothing & koreksi oktaf** — median filter pada kurva pitch; kalau satu frame loncat tepat ±12 semitone lalu kembali, anggap octave error dan koreksi.
4. **Hysteresis untuk note** — note baru dibuat hanya kalau pitch berubah > ±0.5 semitone dan bertahan cukup lama, supaya vibrato tidak dipecah jadi banyak note.
5. **Estimasi tuning global** — hitung rata-rata deviasi cents seluruh lagu dari grid A440, lalu geser referensi grid sesuai offset itu.
6. **Estimasi key & snap ke skala** — deteksi kunci lagu (chroma), lalu note yang di luar skala dipertimbangkan ulang.
7. **Untuk live pitch:** toleransi timing (±100 ms) dan abaikan attack di awal tiap note saat menghitung skor.

---

## Phase 2 — Source separation + model pitch berbasis ML

Ini lompatan akurasi terbesar, dan **sekaligus menyediakan instrumental** untuk final video.

**Alur yang diusulkan:**

```
Lagu full-mix
   │
   ▼
Model separasi stem (CoreML) ──► instrumental.wav ──► dipakai di final video (setelah transpose)
   │
   ▼
vocal.wav
   │
   ▼
Model pitch vokal monofonik ──► kurva F0 ──► note segmentation ──► [TargetMIDINote]
```

**Kandidat teknologi** (semua perlu di-spike: lisensi, kemudahan konversi ke CoreML, ukuran model, kecepatan di iPhone):

| Kebutuhan | Kandidat | Catatan |
|---|---|---|
| Separasi vokal/instrumental | Demucs (htdemucs), Spleeter (2 stem), Open-Unmix | Demucs umumnya kualitas terbaik tapi paling berat; Spleeter lebih ringan |
| Pitch vokal dari vocal stem | CREPE, RMVPE, PESTO | Model F0 monofonik — lebih cocok untuk melodi vokal daripada transkripsi polifonik |
| Transkripsi note polifonik | Spotify BasicPitch | **Sudah dipakai di PoC** (PRD v3), dijalankan di vocal stem + reduksi monofonik. Kalau dijalankan di full-mix akan menghasilkan note semua instrumen, jadi jangan dipakai tanpa pemisahan stem. Kalau hasilnya kurang, bandingkan dengan model F0 monofonik di atas |
| Live pitch user (opsional) | AudioKit `PitchTap`, atau CREPE versi kecil | YIN native biasanya sudah cukup untuk suara user lewat mic; upgrade hanya kalau hasil testing menunjukkan perlu |

**Hal yang harus diukur saat spike on-device:**
- Waktu proses separasi untuk klip 60 detik di iPhone target (target: < 30 detik)
- Penggunaan memori puncak (jangan sampai app di-kill sistem)
- Ukuran model yang ditambahkan ke app
- Kualitas instrumental hasil separasi (sisa vokal terdengar atau tidak)

**Fallback kalau on-device tidak memungkinkan:** proses di server sendiri (perlu pertimbangan biaya, privasi, dan hak cipta lagu yang di-upload).

---

## Phase 3 — Kontrol dari user & alternatif input

1. **Edit guide manual** — user bisa geser/hapus/tambah note di piano roll sebelum merekam.
2. **Import MIDI** — kalau user sudah punya file MIDI melodi, lewati ekstraksi.
3. **Import stem terpisah** — user yang punya file instrumental/acapella sendiri bisa upload langsung.
4. **Kalibrasi latency earphone** — tes tap-along singkat untuk mengukur latency Bluetooth, supaya skor dan sinkronisasi vokal–instrumental lebih tepat.
5. **Skor adaptif** — threshold 75% dan toleransi ±50 cents disesuaikan dengan tingkat kesulitan segmen (mis. segmen dengan banyak melisma diberi toleransi lebih).

---

## Cara mengukur kemajuan akurasi

Supaya perbaikan bisa dibuktikan dengan angka, bukan perasaan:

1. **Siapkan test set** — 10–20 klip lagu (beragam genre & jenis suara) dengan melodi vokal yang sudah dianotasi benar (ground truth). Bisa anotasi sendiri, atau dataset publik untuk riset melodi — cek lisensinya dulu.
2. **Metrik akurasi guide** (standar riset melody extraction):
   - *Raw Pitch Accuracy* — persentase frame bervokal yang pitch-nya benar (±50 cents)
   - *Raw Chroma Accuracy* — sama, tapi mengabaikan kesalahan oktaf
   - *Voicing recall / false alarm* — seberapa tepat mendeteksi kapan ada vokal
3. **Metrik live** — rekam beberapa penyanyi menyanyikan nada yang diketahui, bandingkan hasil deteksi.
4. **Metrik pengalaman user** — rata-rata jumlah retry per segmen, dan persentase kasus "saya merasa sudah benar tapi dinilai BELUM" dari user testing.

Jalankan test set ini setiap kali ada perubahan algoritma, dan catat hasilnya per versi.

| Versi | Raw Pitch Accuracy (target) |
|---|---|
| Phase 1 (full-mix, native) | baseline — diukur dulu |
| Phase 1.5 (quick wins) | naik dari baseline |
| Phase 2 (stem + model pitch) | target ≥ 80% |

> Angka target Phase 2 adalah usulan awal, perlu dikalibrasi setelah baseline Phase 1 diukur.
