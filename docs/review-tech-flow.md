# Review Tech Flow Board — PoC C6

Tanggal review: 31 Oktober 2026
Yang direview: board tech flow 4 baris (sticky notes), dibandingkan dengan `prd.md` v2.

| Baris | Alur di board | Pemilik |
|---|---|---|
| 1 | Impor audio referensi → Konversi audio jadi MIDI (Basic Pitch) → Buat guide nada dari MIDI | Ikzaz |
| 2 | Mulai rekam video & suara → Bernyanyi mengikuti panduan → Memantau nada & feedback live | Takin |
| 3 | Nada sudah tepat? BELUM: panduan koreksi → SUDAH: lanjut bagian berikutnya | Takin |
| 4 | End Record → Pilih bagian rekaman yang benar → Motong + nyambung video dan suara | Zildjian Vito |

> Diagram kecil "System Design Cover Recording App (Clean Architecture)" di pojok kiri atas tidak bisa terbaca di resolusi screenshot ini, jadi belum aku review. Kirim versi yang lebih besar kalau mau dicek juga.

---

## 1. Ringkasan

Board-nya **sudah menangkap alur inti dengan benar**: pisah stem → MIDI → segmen → rekam terus-menerus → nilai per segmen → rewind/lanjut → filter take LOLOS → potong & sambung. Pembagian per baris juga masuk akal karena tiap baris kira-kira satu layer fitur.

Yang masih miss terbagi tiga:
- **1 koreksi teknis penting:** "stopwatch internal" di baris 2.
- **Alur yang belum tergambar:** transposisi, trim, earphone/pre-roll, mix instrumental, trigger End Record, layar hasil.
- **Pekerjaan tanpa pemilik:** sudah aku usulkan pembagiannya di PRD §12.

---

## 2. Koreksi penting

### K1. "Start recording dan jalanin stopwatch internal" (baris 2)
Ini **bertentangan dengan guardrail PRD §7.1**. Stopwatch/`Timer`/`Date()` tidak sinkron dengan timestamp frame video, sehingga titik potong di baris 4 akan meleset (bisa puluhan sampai ratusan ms) dan vokal jadi tidak pas dengan beat instrumental.
**Ganti jadi:** "Start recording, semua waktu diambil dari clock capture session (timestamp frame), bukan stopwatch." Ini paling krusial karena hasil baris 4 (Zildjian) bergantung penuh pada akurasi waktu dari baris 2–3 (Takin).

### K2. Output baris 2 salah tempat
Sticky hijau di baris 2 ("satu file video mentah + log GAGAL/LOLOS") sama persis dengan baris 3. Padahal log GAGAL/LOLOS baru dibuat di baris 3 (Timestamp tagging).
**Output baris 2 seharusnya:** video mentah yang sedang terekam + aliran data pitch user yang sudah dibandingkan dengan target (`PitchEvaluation`).

### K3. Output baris 4 hasil copy-paste
Sticky hijau baris 4 juga berisi "satu file video mentah + log". Seharusnya: **`FinalCoverVideo.mp4`** (vokal user + instrumental), lalu ditampilkan di layar preview dengan Share & Save to Photos.

---

## 3. Alur yang belum tergambar di board

| # | Baris | Yang miss | Rujukan PRD |
|---|---|---|---|
| 1 | 1 | **Vocal range test** cuma catatan kecil, belum jadi langkah sendiri. Untuk PoC cukup disimpan di `UserDefaults`; "database" baru perlu di full app | §5.1 |
| 2 | 1 | **Transposisi tidak ada sama sekali**: hitung pergeseran nada dari vocal range, lalu render ulang audio earphone **dan** instrumental ke key user | §5.4 |
| 3 | 1 | **Trim 15–60 detik** setelah impor | §5.2 |
| 4 | 1 | **Disclaimer Phase 1** di layar proses | §5.2 |
| 5 | 1 | Basic Pitch menghasilkan note polifonik → perlu langkah **reduksi monofonik** (satu nada per waktu) sebelum jadi guide | §5.3 |
| 6 | 1 → 4 | **Instrumental hasil pemisahan tidak mengalir ke baris 4.** Perlu panah dari "pisahin instrumen dan vokal" ke "Motong + nyambung" | §12.2 |
| 7 | 2 | **Cek earphone** sebelum Record (blok kalau output speaker, peringatan kalau Bluetooth) | §7.2 |
| 8 | 2 | **Putar audio referensi di earphone** yang tersinkron dengan rekaman, termasuk pre-roll 2 detik. "Bernyanyi mengikuti panduan" belum punya kotak untuk playback | §5.6, §6.5.5 |
| 9 | 2 | Sticky "gimana caranya processing datanya cepet dan ga berat" sudah ada jawabannya di PRD: pitch diambil dari buffer audio capture (bukan mic kedua), YIN pakai `vDSP` (window 2048, hop 50 ms), jalan di queue sendiri (`nonisolated`), hasil dikirim ke UI via `AsyncStream`, piano roll pakai `Canvas` + `TimelineView` | §6.5.4, §7.4 |
| 10 | 3 | **Aturan nilai:** threshold 75%, user diam saat ada target nada dihitung salah, toleransi ±50 cents | §5.6 |
| 11 | 3 | **Detail BELUM:** highlight nada yang salah (merah) → countdown 3-2-1 → pre-roll → ulang segmen | §5.6 |
| 12 | 3 | **Detail SUDAH:** lagu lanjut tanpa berhenti ke segmen berikutnya | §5.6 |
| 13 | 3 | **Segmen tanpa vokal** (intro/interlude) lolos otomatis | §5.3 |
| 14 | 3 → 4 | **Trigger End Record belum jelas.** Ada tiga: segmen terakhir lulus, tombol End Session (dengan konfirmasi), atau interupsi (telepon, earphone dicabut, app ke background) | §5.7, §5.8 |
| 15 | 4 | **Export sebagian** kalau user berhenti di tengah: hanya segmen yang LOLOS, instrumental fade-out di akhir | §5.7 |
| 16 | 4 | "Ambil satu take **terbaik**" kurang tepat. Karena user baru lanjut setelah lulus, tiap segmen hanya punya **satu** take LOLOS. Cukup tulis "ambil take LOLOS" | §6.4 |
| 17 | 4 | **Auto-Trimming:** potongan tidak cukup disambung berurutan. Tiap potongan harus **ditempatkan di posisi aslinya di lagu**, dengan sisa 30 ms di kiri-kanan untuk crossfade. Kalau tidak, vokal makin lama makin lepas dari instrumental | §5.9 |
| 18 | 4 | **Kotak "Penyambungan & Penghalusan Suara" masih kosong.** Isinya: crossfade 30 ms pakai 2 track audio bergantian, mix vokal + instrumental (gain 1.0 / 0.8), video tetap portrait & mirror, export `.mp4` 1080×1920 H.264 + AAC | §5.9 |
| 19 | 4 | **Layar Export Preview** (player, Share, Save to Photos) tidak ada di board | §6.1 |

---

## 4. Pekerjaan tanpa pemilik → usulan pembagian

Sudah dimasukkan ke PRD §12.1 dengan tanda *(proposed)* supaya bisa didiskusikan tim.

| Pekerjaan | Usulan pemilik | Alasan |
|---|---|---|
| Siapkan lagu demo Track A (pisah stem di Mac) + spike CoreML Track B | Ikzaz | Satu domain dengan pemisahan stem di baris 1 |
| Pesan error impor (DRM, tidak ada vokal, dll.) | Ikzaz | Bagian dari alur impor |
| Cek earphone, deteksi interupsi, tombol End Session | Takin | Menempel ke capture & audio session |
| App shell, navigasi, dependency wiring (`AppContainer`) | Zildjian | Baris 4 paling sedikit risiko teknis; cocok sekaligus jadi integrator |
| Demo sintetis (fallback) | Zildjian | Supaya semua orang bisa tes bagiannya sejak awal tanpa menunggu baris 1 |
| Layar Export Preview, Debug Settings, layar izin & error | Zildjian | Lanjutan langsung dari baris 4 / tugas integrator |
| Entity & protocol Domain | **Semua, hari pertama** | Kontrak antar baris harus disepakati dan dibekukan sebelum kerja paralel |

**Catatan beban kerja:** bagian Takin (baris 2–3) paling berat dan ada di jalur kritis (sinkronisasi clock + deteksi pitch realtime). Usulanku: Zildjian pair dengan Takin di bagian clock (PRD §7.1), karena akurasi potongan di baris 4 bergantung di situ.

---

## 5. Kontrak serah-terima antar baris

Ini yang paling sering bikin integrasi gagal kalau tidak disepakati dari awal (detail di PRD §12.2):

- **Ikzaz → Takin:** `PreparedSong`. Segmen menutup seluruh lagu tanpa celah, audio earphone sudah di-transpose.
- **Ikzaz → Zildjian:** instrumental tanpa vokal asli, di-transpose **dengan nilai yang sama**, mulai di t = 0 dengan durasi sama dengan lagu yang di-trim.
- **Takin → Zildjian:** URL video mentah + daftar take LOLOS. Waktu dalam satuan **waktu file video**, sudah dikompensasi latency earphone, termasuk sisa 30 ms di kiri-kanan.

Milestone integrasi yang diusulkan: **M1** kontrak dibekukan → **M2** end-to-end pakai demo sintetis → **M3** end-to-end pakai lagu demo asli → **M4** keputusan go/no-go Track B.

---

## 6. Keputusan baru dari review ini

| Topik | Keputusan |
|---|---|
| Audio → MIDI | **Basic Pitch (CoreML) di vocal stem** + reduksi monofonik; YIN jadi fallback. PRD §3 & §5.3 sudah diupdate. Lisensi model & ekspor CoreML-nya tetap perlu dicek |
| Pekerjaan tanpa pemilik | Pakai usulan di atas, ditandai *(proposed)* di PRD |

---

## 7. Catatan untuk full app (di luar PoC)

Kalau alur ini nanti jadi aplikasi penuh, yang perlu ditambahkan ke board:
- Onboarding + penyimpanan profil (vocal range) di database (mis. SwiftData), bukan `UserDefaults`
- Library proyek: simpan sesi, lanjutkan sesi yang terputus, riwayat cover
- Memilih di antara beberapa take LOLOS, atau rekam ulang segmen yang sudah lulus
- Edit guide nada manual, lirik, efek vokal
