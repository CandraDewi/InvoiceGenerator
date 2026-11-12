# InvoiceFlow v4.1 — Pemilik DANA dan BCA terpisah

1. Backup folder aplikasi saat ini.
2. Jalankan ulang file `invoiceflow_v4_migration.sql` di Supabase SQL Editor. Migration aman dijalankan ulang; kolom `dana_holder` ditambahkan jika belum ada.
3. Ganti `index.html` lokal dengan `InvoiceFlow_v4_index.html` (rename menjadi `index.html`).
4. Pastikan `SUPABASE_URL` dan `SUPABASE_ANON_KEY` pada file baru berisi konfigurasi proyek Anda yang sudah berfungsi. Jangan gunakan service_role/secret key.
5. Refresh browser dengan Ctrl+Shift+R.
6. Buka Profil & Pembayaran. Isi nomor DANA, nama pemilik DANA, nomor rekening BCA, dan nama pemilik rekening BCA secara terpisah.
7. Simpan, lalu unduh PDF percobaan untuk memastikan kedua nama tampil pada metode pembayaran yang benar.

Perubahan v4.1: pemilik akun DANA dan pemilik rekening BCA kini merupakan dua kolom berbeda dan dicetak terpisah di PDF.
