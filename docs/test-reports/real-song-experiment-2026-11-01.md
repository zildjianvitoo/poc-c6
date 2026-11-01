# Eksperimen Lagu Asli — 1 November 2026

Lagu: *A Whole New World* (lyric video, MP3 74 s stereo 44.1 kHz) — **hanya lokal di `local-songs/`, tidak di-commit**. Dijalankan di Mac dengan kode app yang sama (center-channel, CREPE, SimplifyGuide, SliceSegments). Harness: scratchpad sesi, tidak masuk repo.

## 1. Kenapa vokal asli masuk semua ke "Background"
- Stereo lagu ini sempit: korelasi L/R ≈ 0.8, side (L−R) ≈ **10 dB di bawah** mid.
- Center-channel membuang mid; yang tersisa (side) berisi reverb/double vokal, lalu dinaikkan ±10 dB agar volumenya setara → vokal tetap jelas.
- **Kesimpulan:** center-channel tidak cocok untuk lagu ini. Butuh pemisahan berbasis ML (spike CoreML, IK-14).

## 2. Kenapa bocoran speaker pun tidak lolos
Uji "penyanyi asli menyanyi ke guide-nya sendiri" (pitch track dari mix, seperti mic mendengar speaker), 60 s pertama, 11 segmen vokal, lulus = skor ≥ 75%:

| Aturan penilaian | Toleransi | Penyanyi asli | Nyanyi meleset 2 semitone | Monoton | Diam |
|---|---|---|---|---|---|
| Diam = miss (lama) | ±50¢ | 27% | 0% | 9% | 0% |
| Diam = miss (lama) | ±150¢ | 82% | 0% | 9% | 0% |
| Hanya frame bersuara, syarat bersuara ≥ 60% (baru) | ±50¢ | 55% | 0% | 9% | 0% |
| **Hanya frame bersuara, syarat bersuara ≥ 60% (baru)** | **±80¢** | **100%** | **0%** | **9%** | **0%** |

Penyebab: di dalam frasa hanya ±74% frame yang bersuara (napas, konsonan, jeda antar kata). Dengan "diam = miss", penyanyi asli pun sulit mencapai 75%.

## 3. Usulan "satu balok per frasa"
Balok satu nada per frasa (dipisah jeda ≥ 0.4–0.8 s) membuat penyanyi asli hanya lolos **6–30%** balok — satu frasa berisi banyak nada, jadi satu nada rata tidak cocok. Tidak dipakai; guide per-not yang disederhanakan (SimplifyGuide) lebih baik.

## Keputusan / perubahan
- `EvaluateSegmentUseCase`: skor = hit / frame bersuara jika bersuara ≥ 60%; selain itu diam dihitung miss (PRD §5.6 diperbarui).
- Usulan: default `hitToleranceCents` 50 → 80 (perlu persetujuan karena `PoCConfiguration` adalah kontrak). Sementara bisa diatur lewat Debug Settings.
- Berikutnya: spike pemisahan vokal CoreML (IK-14).
