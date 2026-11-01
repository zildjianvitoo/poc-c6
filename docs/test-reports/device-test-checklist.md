# Checklist Tes iPhone — Fase 2

Branch: `integration`. Lagu yang dipakai: **demo sintetis** (3 segmen, 16 detik: frasa 0–6 s, interlude instrumental 6–9 s, frasa 9–16 s). Notnya C4–G4, lalu **ditranspose otomatis sesuai hasil tes vocal range-mu** (langkah 1). Ikuti balok putih di piano roll; nyanyi satu oktaf berbeda dari balok dihitung salah.

Yang dibutuhkan: iPhone (iOS 18+), kabel ke Mac, **earphone kabel** (Lightning/USB-C), AirPods (untuk tes Bluetooth), dan satu orang untuk menelepon (tes interupsi).

Isi kolom **Hasil** dengan ✅ / ❌ + catatan singkat. Kalau ❌, ambil screenshot atau screen recording.

### Belum punya earphone? Pakai mode tes speaker

1. Buka app → ikon slider kanan atas (**Debug Settings**) → scroll ke **Device testing** → nyalakan **Allow recording without earphones** → **Save**.
2. Lagu akan diputar lewat speaker dan layar rekam menampilkan label ungu *"Speaker test mode: scores are not reliable"*.
3. Karena lagu bocor ke mic, melodi panduan ikut "dinyanyikan" oleh speaker:
   - **Untuk tes loop / TRY AGAIN:** kecilkan volume iPhone ke **0**, lalu senandungkan sambil melihat piano roll. Diam di segmen 3 untuk memicu TRY AGAIN.
   - **Untuk tes sinkron (bagian 8):** volume dikeraskan, jangan bernyanyi; melodi dari speaker akan lolos sendiri.
4. Yang **tidak** bisa dites dengan mode ini: 2.2 (colok earphone), 6.1 (cabut earphone), seluruh bagian 7 (AirPods), dan kualitas suara di 4.3. Tes 2.1 dilakukan dengan toggle **mati**.
5. Matikan lagi toggle-nya setelah selesai.

---

## 0. Pasang app ke iPhone

1. Di Mac, ambil branch `integration`:
   ```bash
   git fetch origin && git switch integration && git pull
   ```
2. Buka `poc-c6.xcodeproj` di Xcode.
3. Sambungkan iPhone pakai kabel → pilih **Trust This Computer** di iPhone.
4. Kalau diminta: iPhone → Settings → Privacy & Security → **Developer Mode** → On → restart.
5. Di Xcode pilih iPhone-mu sebagai tujuan (bagian atas jendela), lalu **Run** (⌘R).
   - Kalau ada error signing: target `poc-c6` → Signing & Capabilities → pilih Team-mu.
   - Kalau iPhone bilang *Untrusted Developer*: Settings → General → VPN & Device Management → Trust.

## 1. Izin & alur awal

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 1.1 | Buka app pertama kali | Layar penjelasan izin mikrofon | |
| 1.2 | Continue → Allow | Masuk layar Vocal Range | |
| 1.3 | **Vocal Range Test:** Start → nyanyikan "aaa" di nada **terendah** yang nyaman, tahan ±2 detik | Nama not berubah mengikuti suara, bar "Hold it…" penuh, lalu "Lowest note" + nama not | |
| 1.4 | Next: Highest Note → nyanyikan nada **tertinggi** yang nyaman, tahan ±2 detik | "Your range" + rentang, mis. A2 – E4 | |
| 1.5 | Coba Retry di salah satu langkah, dan coba nyanyi nada tinggi yang sama dengan nada rendah | Retry mengulang langkah itu; nada tinggi yang tidak lebih tinggi ditolak dengan pesan | |
| 1.6 | Save and Continue → Use synthesized demo | Layar Ready: "3 segments · ±N semitones" — N bergantung range-mu (demo aslinya C4–G4) | |
| 1.7 | Tutup app, buka lagi | Tes range tidak ditanya lagi (tersimpan); bisa diulang dari Debug Settings → Re-test Vocal Range | |
| 1.8 | Record | Layar penjelasan izin kamera → Allow | |

## 2. Cek earphone (TK-13)

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 2.1 | **Tanpa earphone**, tekan Record | Layar "Plug in earphones", tidak merekam | |
| 2.2 | Colok earphone kabel → Try Again | Sesi mulai | |

## 3. Sesi lengkap dengan earphone kabel (TK-02, 04, 05, 06, 10, 11)

Pegang iPhone tegak di depan wajah, seperti selfie.

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 3.0 | Tekan Record | Setelah "Getting ready…", hitung mundur 3·2·1 tanpa suara, lalu musik mulai | |
| 3.1 | Lihat layar saat sesi mulai | Kamera depan penuh, **ter-mirror seperti cermin**, bingkai 9:16, piano roll di tengah, top bar "Segment 1 / 3 · Attempt 1" | |
| 3.2 | Dengarkan earphone | Musik demo terdengar **hanya di earphone**, tidak di speaker | |
| 3.3 | Senandungkan not yang lewat garis kuning | Garis trail muncul: **hijau** kalau pas, **merah** kalau meleset, kosong saat diam | |
| 3.4 | Perhatikan kelancaran | Piano roll bergerak halus, tidak patah-patah | |
| 3.5 | Segmen 1 selesai | "Segment 1 passed", **musik tidak berhenti** | |
| 3.6 | Segmen 2 (interlude, tanpa not) | Otomatis lolos | |
| 3.7 | Di segmen 3 **sengaja diam atau nyanyi asal** | Musik berhenti → "TRY AGAIN" + skor + not yang meleset (merah) → hitung mundur 3·2·1 **tanpa suara** → musik mulai 2 detik sebelum segmen 3 → "Attempt 2" | |
| 3.8 | Selama 3.7 | Kamera **tetap jalan**, tidak berhenti atau berkedip | |
| 3.9 | Nyanyikan segmen 3 dengan benar | Lolos → layar "Creating your cover…" → layar Export | |

## 4. Hasil video (ZV-13, comping)

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 4.1 | Lama export | Selesai < 32 detik (2× durasi lagu) | |
| 4.2 | Putar video di layar Export | Tegak (portrait), **ter-mirror**, durasi ±16 detik | |
| 4.3 | Dengarkan | Suaramu + musik **tanpa vokal asli**; suaramu **sinkron** dengan musik (tidak terasa telat atau gema) | |
| 4.4 | Dengarkan di sekitar detik 6, 9 dan saat take diulang | Tidak ada bunyi "klik"/patah di sambungan | |
| 4.5 | Overlay | Piano roll dan tombol **tidak ikut terekam** di video | |
| 4.6 | Save to Photos | Minta izin Photos → video tersimpan di Photos | |
| 4.7 | Share | Share sheet muncul (cukup cek muncul) | |

## 5. Export sebagian (TK-14)

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 5.1 | Start Over → demo → Record, lolos segmen 1, lalu **End Session** | Dialog: "Export 1 of 3" / "Discard" / "Keep Recording" | |
| 5.2 | Keep Recording | Sesi lanjut | |
| 5.3 | End Session → Export 1 of 3 | Video ±6 detik, musik **fade out** di detik terakhir | |
| 5.4 | Ulangi, End Session sebelum segmen 1 lolos | Hanya ada "Discard" | |

## 6. Interupsi (TK-15) — mulai sesi baru untuk tiap baris

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 6.1 | Setelah segmen 1 lolos, **cabut earphone** | Sesi berhenti → "Recording was interrupted" + tombol Export 1 of 3 | |
| 6.2 | Tekan Export 1 of 3 | Video sebagian dibuat dengan benar | |
| 6.3 | Saat merekam, **swipe ke Home**, lalu buka app lagi | Sesi berhenti dengan rapi, ada tawaran export / start over, app tidak crash | |
| 6.4 | Saat merekam, minta orang **menelepon** (telepon biasa atau FaceTime) | Sesi berhenti, take yang lolos aman | |
| 6.5 | Saat merekam, panggil **Siri** | Sesi berhenti dengan rapi | |

## 7. AirPods / Bluetooth (PRD §5.8, §7.2)

| # | Langkah | Yang diharapkan | Hasil |
|---|---|---|---|
| 7.1 | Sambungkan AirPods → Record | Banner oranye "Wired earphones give the best sync" | |
| 7.2 | Selesaikan sesi → putar video | Suara terekam dari **mic iPhone** (bukan mic AirPods: suaranya lebih jernih/"ruangan", bukan suara telepon) | |
| 7.3 | Dengarkan sinkronnya | Kemungkinan suaramu sedikit telat dibanding musik — catat seberapa terasa | |
| 7.4 | Kalau telat: Debug Settings (ikon slider kanan atas, di luar layar rekam) → **Latency calibration** → naikkan 0.05–0.15 s → Save → ulangi | Makin sinkron | |

## 8. Tes sinkron (tes klik, TK-05 / ZV-12)

Tujuannya mengukur selisih waktu antara musik dan rekaman (target < 40 ms, potongan ±1 frame).

1. Pakai **earphone kabel**. Mulai sesi, lalu tempelkan satu earbud ke **mic iPhone di bagian bawah** dan jangan bernyanyi. Mic akan merekam musik dari earbud itu.
2. Biarkan sampai selesai. Musik demo berisi melodi panduan, jadi mic "mendengar" nada yang benar dan semua segmen seharusnya lolos sendiri. Kalau ada TRY AGAIN, dekatkan earbud ke mic dan naikkan volume.
3. Dengarkan hasil video: musik yang "bocor" dari earbud dan musik instrumental harus **menumpuk pas**. Kalau terdengar seperti **gema/dobel**, berarti ada selisih.
4. Catat hasilnya. Pengukuran angka pastinya butuh alat tambahan (lihat catatan di bawah).

> Catatan: untuk angka pasti (ms), aku perlu menambahkan dua alat: tombol debug untuk menyimpan rekaman mentah + log take, dan script Mac untuk menganalisisnya. Lakukan bagian 1–7 dulu.

## 9. Laporan

Kirim ke Claude:
- tabel di atas yang sudah diisi,
- screenshot/screen recording untuk setiap ❌,
- model iPhone + versi iOS, dan earphone yang dipakai.
