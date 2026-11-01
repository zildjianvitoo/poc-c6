# Laporan Tes iPhone (Fase 2) — 1 November 2026

Branch: `integration` · Dites oleh: Zildjian · Mode: **speaker** (belum ada earphone) · Lagu: demo sintetis 16 s.

## Hasil

| Bagian checklist | Hasil | Catatan |
|---|---|---|
| 1. Izin + vocal range test | ✅ | Range tersimpan, demo ditranspose sesuai range |
| 2.1 Blokir tanpa earphone (toggle mati) | ✅ | |
| 3. Sesi rekam (kamera, piano roll, loop, TRY AGAIN) | ✅ | Setelah perbaikan di bawah |
| 4. Video hasil (portrait, mirror, sinkron, Save/Share) | ✅ | Sinkron setelah kalibrasi tes klik |
| 5. Export sebagian | ✅ | |
| 6. Interupsi: Home, telepon, Siri | ✅ | |
| 8. Tes sinkron (tes klik) | ✅ | Speaker; nilai kalibrasi disimpan lewat Apply |

## Bug yang ditemukan di iPhone & sudah diperbaiki

| Gejala | Penyebab | Perbaikan (commit) |
|---|---|---|
| Video hasil miring & tergencet | Kamera mengirim frame landscape walau diminta portrait; writer dikunci 1080×1920 | Ukuran writer dari frame pertama + transform 90° untuk frame landscape (`d0e4454`) |
| Preview kamera landscape | Rotasi diset sebelum koneksi preview ada / di dalam blok konfigurasi | Rotasi setelah setup + `AVCaptureDevice.RotationCoordinator` (`c5ee502`, `960d45f`) |
| Suara tidak terdeteksi di detik awal | Prediksi CoreML pertama lambat → buffer dibuang | Pemanasan CREPE + hitung mundur sebelum attempt pertama (`960d45f`) |
| Kresek-kresek saat End Session | CPU penuh (encode video + CREPE di CPU + piano roll 60 fps) | CREPE di Neural Engine, piano roll dijeda saat dialog (`29cf984`) |
| Deteksi bolong-bolong | Buffer audio dibuang saat CREPE sibuk → jendela analisis reset | Analisis kontinu, converter dipakai ulang, baris debug "Mic …" (`de55f37`) |
| Vokal mendahului musik (konstan, > 0.25 s) | Perkiraan latency output/mic meleset di mode speaker | Tes klik otomatis + Apply ke Latency calibration (`9b48c3e`) |

## Belum dites (butuh earphone / AirPods)

- 2.2 colok earphone → rekam, 6.1 cabut earphone saat merekam.
- Sesi lengkap dengan earphone kabel (kondisi demo sebenarnya) + tes klik untuk earphone.
- Bagian 7 AirPods: banner, mic tetap mic iPhone, tes klik untuk Bluetooth.

## Catatan

- Di mode speaker, nilai **Latency calibration** hasil tes klik khusus untuk speaker. Ulangi tes klik saat pindah ke earphone/AirPods.
- Kalau range user rendah (transpose turun satu oktaf), speaker tetap memutar melodi di oktaf asli; mic bisa menangkap speaker. Ini batasan mode speaker, tidak terjadi dengan earphone.
