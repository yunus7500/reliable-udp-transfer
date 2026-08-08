// Packet header/payload encode-decode

import 'dart:typed_data';
import 'packet_type.dart';
import 'constants.dart';

class Packet {
  final int sequenceNumber; // paket sırası
  final int checksum; // veri bütünlüğü doğrulama kodu

  final PacketType type; // paket tipi( data,ack,handshake vs.)
  final Uint8List payload; // taşıdığı veri(dosya parçası)

  const Packet({
    required this.sequenceNumber,
    required this.type,
    required this.payload,
    this.checksum = 0, // ilk olarak =0,bir sonraki aşamada hesaplanacak
  });

  /// paketi UDP soketinden gönderebilmek için byte dizisine dönüştürür

  Uint8List toBytes() {
    // 1: toplam paket boyutunu hesapla( Header + Payload)
    int totalLength = ProtocolConstants.headerSize + payload.length;

    // 2: bu boyutta bir bellek alanı oluşur
    ByteData byteData = ByteData(totalLength);

    // 3: Header verilerini sırayla belleğe yaz (Endian.big mantığı)
    byteData.setUint32(0, sequenceNumber, Endian.big); // ilk 4 byte
    byteData.setUint8(4, type.value); // sonraki 1 byte
    byteData.setUint32(5, payload.length, Endian.big); // sonraki 4 byte
    byteData.setUint32(9, checksum, Endian.big); // sonraki 4 byte

    // 4: hazırladığımız header'ı Uint8List'e çevir
    Uint8List packetBytes = byteData.buffer.asUint8List();

    // 5: Payload'ı (asıl veriyi) header'ın hemen arkasına (13. byte'tan itibaren) kopyala
    packetBytes.setAll(ProtocolConstants.headerSize, payload);

    return packetBytes;
  }

  // UDP soketinden gelen karmaşık byte dizisini anlamlı Packet nesnesine dönüştürür
  static Packet fromBytes(Uint8List bytes) {
    if (bytes.length < ProtocolConstants.headerSize) {
      throw FormatException('paket çok küçük,header eksik');
    }
    ByteData byteData = ByteData.sublistView(bytes);

    // Header verilerini sırayla oku
    int seq = byteData.getUint32(0, Endian.big);
    int typeValue = byteData.getUint8(4);
    int payloadLength = byteData.getUint32(5, Endian.big);
    int checksum = byteData.getUint32(9, Endian.big);

    // Byte'tan okunan tipi PacketType enum'una çevir
    PacketType type = PacketType.fromValue(typeValue);

    // Payload'ı asıl dizinin içinden kesip al
    Uint8List payload = bytes.sublist(
      ProtocolConstants.headerSize,
      ProtocolConstants.headerSize + payloadLength,
    );
    return Packet(
      sequenceNumber: seq,
      type: type,
      payload: payload,
      checksum: checksum,
    );
  }
}
