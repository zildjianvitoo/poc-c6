> **Tambahan baru: PoC persiapan cover.** Lihat [README-PRE.md](README-PRE.md) untuk tab Siapkan, service analisis, dan cara mencoba di iPhone. Keterangan offline di bawah berlaku untuk fitur rehearsal lama.

# Key Rehearsal — iPhone PoC

Native SwiftUI, iOS 17+, tanpa package eksternal. Semua audio diproses lokal.

## Build ke iPhone
1. Buka `KeyRehearsal.xcodeproj` di Xcode.
2. Xcode → Settings → Accounts: tambahkan Apple ID.
3. Pilih target KeyRehearsal → Signing & Capabilities → Team: pilih Personal Team atau tim developer kamu. Ganti Bundle Identifier menjadi unik, misalnya `com.namamu.KeyRehearsal`.
4. Sambungkan iPhone, pilih Trust, aktifkan Settings → Privacy & Security → Developer Mode bila diminta.
5. Pilih iPhone sebagai destination, lalu tekan Run (⌘R). Izinkan mikrofon saat mulai merekam.
6. Jika muncul Untrusted Developer, izinkan profil di Settings → General → VPN & Device Management.

## Coba alur utama
- Tes range: nyanyikan nada rendah dan tinggi yang nyaman selama 10–20 detik.
- Rekam vokal lagu atau impor M4A/WAV/MP3 lewat Files.
- Buka rekaman, lihat rentang dan usulan transpose. Ubah semitone dengan stepper.
- Dengarkan A asli dan B transpose. Gunakan headphone dan coba nyanyikan.
- Rekam take baru; nilai kenyamanannya. Take baru muncul di halaman Latihan, sehingga hasil dapat dibandingkan dengan take sebelumnya.
- Centang cek nada tinggi/rendah serta seluruh lagu, lalu simpan key rehearsal.

## Batas PoC
- Estimasi pitch berbasis autocorrelation untuk vokal monofonik. Instrumen, noise, vibrato, falsetto, dan suara napas dapat menghasilkan salah nada atau oktaf. Rentang adalah persentil 5–95%, bukan semua ekstrem.
- Transpose realtime memakai AVAudioUnitTimePitch, mempertahankan tempo dan menggeser seluruh audio. Belum mengekspor file hasil transpose.
- Deviasi cents adalah jarak ke semitone terdekat, bukan akurasi melodi atau diagnosis fals. Tidak ada target melodi.
- Usulan meminimalkan nada di luar range tes dan besarnya pergeseran. Jika rentang lagu lebih lebar dari range tes, tidak ada key yang menjamin semuanya nyaman.
- Kalender tampil, integrasi akun, sinkronisasi cloud, pemisahan vokal, waveform timeline, dan ekspor belum termasuk. Fokus PoC adalah loop tes → rekam → analisis → transpose → coba ulang.
- Audio dan metadata bertahan setelah app ditutup; penghapusan app menghapus data lokal. Personal Team mungkin perlu signing ulang sesuai ketentuan Apple.

## Validasi
Build simulator dan build arsitektur iPhone (tanpa signing) Xcode 27 berhasil. Uji nada sintetis C3/A3/G4 menghasilkan C3–G4; audio hening ditolak. Pengujian mikrofon, output audio dan signing di iPhone fisik tetap perlu dilakukan di perangkatmu.

Review perbaikan: empat temuan terkait izin mikrofon, interupsi audio, key take baru, dan referensi key tersimpan sudah dinilai resolved untuk handoff PoC. Screenshot light/dark tersedia di Review. Test sintetis mandiri tersedia di Tests/PitchSmokeTest.swift (macOS AVFoundation).
