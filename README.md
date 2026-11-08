# Reliable UDP File Transfer

Custom reliable P2P file transfer protocol built on raw UDP sockets (`RawDatagramSocket`) in Dart & Flutter — implementing custom binary framing, CRC32 checksum verification, sliding-window flow control, automatic retransmission, zero-RAM disk streaming, and STUN/NAT hole punching from scratch without relying on TCP.

Bu proje, doğası gereği bağlantı kurmayan ve paket teslimatını garanti etmeyen **UDP (User Datagram Protocol)** üzerine sıfırdan inşa edilmiş **güvenilir bir dosya aktarım protokolü (Reliability Layer)** ve çapraz platform (iOS, Android, macOS) uygulamasıdır.

---

## Temel Özellikler (Key Features)

- **Özel Binary Paket Yapısı (13-Byte Custom Header):**
  - `[4B Sequence Number] + [1B Packet Type] + [4B Payload Length] + [4B CRC32 Checksum] + [Payload (max 1400B)]`
  - Her paket ağdan okunduğunda **CRC32 Checksum** doğrulamasından geçer; bozuk paketler anında reddedilir.
- **Sıfır RAM Yükü ile Disk Streaming (`RandomAccessFile`):**
  - Dosyalar belleğe (RAM) yüklenmez. Gönderici dosyayı diskten `1400 byte`'lık parçalar halinde okur; alıcı ise paket hangi sırayla gelirse gelsin `(sequenceNumber - 1) * 1400` ofsetine (`setPositionSync` + `writeFromSync`) doğrudan diske yazar.
  - Mükerrer paket takibi `Map` yerine bit dizisi (`Uint8List` bitmap) ile yapılır; çoklu GB boyutundaki dosyalarda dahi RAM kullanımı bir-iki MB'ı geçmez.
- **Sliding Window (Kayan Pencere) & Event-Driven ACK:**
  - Stop-and-Wait yavaşlığını önlemek için aynı anda pencere boyutu kadar (`windowSize = 64`) paketi havada (in-flight) tutar.
  - Her paket diske senkron olarak yazıldıktan sonra `ACK` gönderilir; süresi içinde (`300ms`) `ACK` gelmeyen paketler `RetransmitTimer` ile otomatik olarak tekrar fırlatılır.
- **4 Haneli Kod ile Eşleşme + STUN & UDP Hole Punching:**
  - Kullanıcıların karmaşık IP ve Port numaralarıyla uğraşmaması için her cihaz açılışta 4 haneli bir bağlantı kodu üretir.
  - Google STUN (`stun.l.google.com:19302`) üzerinden cihazların dış (Public) `IP:Port` adresleri tespit edilir ve karşılıklı UDP sinyal paketleriyle NAT güvenlik duvarında delik açılarak (UDP Hole Punching) doğrudan P2P bağlantı kurulur.
- **Bağımlılıksız Native Köprü (`MethodChannel`):**
  - Üçüncü parti ağır eklentiler kullanmadan iOS (`UIDocumentPickerViewController`, `UIActivityViewController`, `beginBackgroundTask`) ve Android (`ACTION_OPEN_DOCUMENT`, `MediaStore.Downloads`, `WakeLock` / `WifiLock`) ile doğrudan iletişim kurar.

---

## Nasıl Kullanılır? (How to Run)

1. Projeyi iki cihazda (iOS, Android veya macOS) çalıştırın:
   ```bash
   flutter run
   ```
2. **Alıcı Cihaz:** Uygulama açıldığında ekranda otomatik olarak **4 haneli bir Bağlantı Kodu** (Örn: `4829`) görünür. Alıcı cihazda hiçbir tuşa basmanıza gerek yoktur.
3. **Gönderici Cihaz:** Alıcı ekrandaki 4 haneli kodu kutuya girin ve **"Dosya Seç & Gönder"** butonuna basın.
4. İstediğiniz dosyayı (`PDF`, `MP4`, `JPG`, `PNG`, `DOCX`, `XLSX`, `PPTX`, `ZIP` vb.) seçin.
   - Cihazlar aynı Wi-Fi ağındaysa yerel ağ (LAN) üzerinden, farklı ağlardaysa STUN + NAT Hole Punching üzerinden doğrudan aktarım başlar.
5. Aktarım `%100` olduğunda **Kaydet / Aç** butonuyla dosyayı açabilir veya galeriye/cihaza kaydedebilirsiniz.

---

## Mimari Yapı (Architecture)

```text
lib/
├── core/
│   ├── platform_helper.dart    # Native dosya seçici, kayıt dizini ve arkaplan kilidi
│   ├── retransmit_timer.dart   # Paket bazlı timeout ve yeniden gönderim sayacı
│   ├── signaling_client.dart   # 4 haneli oda kodu ile otomatik adres eşleştirme
│   └── stun_client.dart        # RFC 5389 STUN istemcisi (Public IP:Port tespiti)
├── protocol/
│   ├── checksum.dart           # CRC32 bütünlük hesaplaması
│   ├── constants.dart          # MTU/Payload (1400B), pencere boyutu (64) ve timeout sabitleri
│   ├── file_meta.dart          # Handshake paketinde taşınan dosya adı ve boyut bilgisi
│   ├── packet.dart             # 13-byte binary header encode/decode
│   └── packet_type.dart        # Paket tipleri (handshakeInit, handshakeAck, data, ack, fileEnd)
├── receiver/
│   └── file_receiver.dart      # Bitmap tabanlı, doğrudan diske yazan UDP alıcısı
├── sender/
│   └── file_sender.dart        # Diskten akışlı okuyan kayan pencereli UDP göndericisi
└── screens/
    ├── home_screen.dart        # Ana ekran ve transfer akışı
    └── info_widgets.dart       # Bağlantı kodu kartı ve kullanım rehberi
```
