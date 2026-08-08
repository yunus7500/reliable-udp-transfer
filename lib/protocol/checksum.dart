// CRC32 calculation

import 'dart:typed_data';
import 'package:crclib/catalog.dart';

class Checksum {
  // verilen byte dizisinin CRC32(hata kontrol) kodunu hesaplar

  static int calculate(Uint8List data) {
    // crclib paketindeki standart Crc32 algoritması
    final crc = Crc32().convert(data);
    return crc.toBigInt().toInt();
  }
}
