# Reliable UDP Transfer (Kendi TCP'miz)

Custom reliable data transfer protocol built on raw UDP sockets, implementing
sequencing, ACK-based delivery, and retransmission — a from-scratch alternative
to TCP's reliability layer using Flutter/Dart.

Bu proje, doğası gereği güvensiz ve paketin hedefe ulaşıp ulaşmadığını
umursamayan **UDP (User Datagram Protocol)** üzerine inşa edilmiş, veri kaybını
önleyen **güvenilir bir katman (Reliability Layer)** mimarisidir.

Ağ mühendisliğinde TCP'nin (Transmission Control Protocol) arka planda
hayatımızı nasıl kurtardığını anlamak için sıfırdan yazılmış mükemmel bir eğitim
ve test projesidir.

---

## Özellikler (Features)

- **Parçalama ve Birleştirme (Chunking & Reassembly):** Büyük veriler (veya
  metinler) ağın taşıyabileceği küçük Byte paketlerine (Datagram) bölünür ve
  karşı tarafta sırasına göre hatasız bir şekilde geri birleştirilir.
- **Sequence Numbers (Sıra Numaraları):** Havada kaybolan veya sırası karışan
  paketlerin doğru sıraya dizilmesini sağlar.
- **ACK Mekanizması (Acknowledge):** Alıcı, yakaladığı her paket için
  göndericiye "Aldım" (ACK) onayı gönderir.
- **Zamanlayıcı ve Tekrar Gönderim (Retransmission):** Gönderici paketi
  fırlattıktan sonra bir kronometre (RetransmitTimer) başlatır. Eğer ACK
  zamanında gelmezse (veya paket havada kaybolmuşsa), paketi otomatik olarak
  tekrar fırlatır.
- **Sliding Window (Kayan Pencere Mimarisi):** Stop-and-Wait (Gönder-Bekle)
  mantığındaki yavaşlığı çözmek için aynı anda N adet (örn: 5) paketin havaya
  fırlatılmasına izin veren modern bir transfer kontrol algoritması.
- **Canlı Sistem Logları (Real-time UI):** Transfer esnasında fırlatılan
  parçaların, alınan ACK'ların ve zaman aşımlarının Flutter arayüzünde yeşil,
  mavi ve kırmızı renklerle canlı olarak izlenebilmesi.

---

## Nasıl Çalıştırılır?

Projeyi bilgisayarınızda (Emülatör) veya gerçek telefonunuzda test
edebilirsiniz.

### Tek Cihazda Test (Localhost)

1. `lib/screens/home_screen.dart` dosyasını açın.
2. `targetAddress` kısmının `InternetAddress.loopbackIPv4` olduğundan emin olun.
3. Uygulamayı çalıştırın.
4. Ekranda önce **"1--alıcıyı başlat"** butonuna, ardından **"2--gönderimi
   başlat"** butonuna basın.
5. 100 paketin saniyeler içinde fırlatılıp simüle edildiğini log ekranından
   izleyin.

### İki Farklı Cihazda Test (Wireless / Hotspot)

Uygulamayı Mac ve Telefon arasında gerçek bir Wi-Fi ağı üzerinden test
edebilirsiniz!

1. İki cihazı aynı Wi-Fi ağına bağlayın (Veya telefondan Hotspot açıp
   bilgisayarı bağlayın).
2. **Alıcı** olacak cihazın yerel IP adresini öğrenin (Örn: `[IP_ADDRESS]`).
3. `home_screen.dart` dosyasında `targetAddress` kısmını güncelleyin:
   ```dart
   targetAddress: InternetAddress('[IP_ADDRESS]'),
   ```
4. Kodunuzu iki cihazda da çalıştırın. (Not: Android release build için
   `AndroidManifest.xml` içine INTERNET izni zaten eklenmiştir).
5. **Alıcı (Telefon)** cihazında "Alıcıyı Başlat" butonuna basın.
6. **Gönderici (Bilgisayar)** cihazında "Gönderimi Başlat" butonuna basın.
7. Ağ üzerinden uçan paketleri canlı izleyin!

---

## Mimari Detaylar

Proje üç ana modülden oluşmaktadır:

1. **Protocol (`lib/protocol/`)**: Byte dönüştürme işlemleri, Paket başlıkları
   (Sequence No, Type, Payload boyutu) ve `Packet` modeli.
2. **Sender (`lib/sender/`)**: UDP Soketini açan, `RetransmitTimer` kullanarak
   zaman aşımlarını takip eden ve Kayan Pencere (Sliding Window) mekanizmasıyla
   ACK gelene kadar verileri askıda (in-flight) tutan gönderici modülü.
3. **Receiver (`lib/receiver/`)**: Dinleyici UDP Soketini açan, gelen paketleri
   sıra numarasına göre hafızada biriktiren ve "Dosya Bitti" (fileEnd) komutu
   geldiğinde tüm byte'ları asıl veriye dönüştüren alıcı modülü.
