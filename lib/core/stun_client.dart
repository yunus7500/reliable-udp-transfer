import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// google stun sunucusu üzerinden cihazın dış (public) ip ve portunu bulur
class StunClient {
  static const String _stunHost = 'stun.l.google.com';
  static const int _stunPort = 19302;
  static const int _magicCookie = 0x2112A442;

  // gelen paketin stun cevabı olup olmadığını kontrol eder
  static bool isStunPacket(Uint8List data) {
    if (data.length < 20) return false;
    final view = ByteData.sublistView(data);
    return view.getUint16(0) == 0x0101 && view.getUint32(4) == _magicCookie;
  }

  // mevcut udp soketi üzerinden stun isteği gönderir
  static Future<void> sendRequest(RawDatagramSocket socket) async {
    try {
      final addresses = await InternetAddress.lookup(_stunHost);
      final ipv4 = addresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );

      final req = ByteData(20);
      req.setUint16(0, 0x0001); // binding request
      req.setUint16(2, 0x0000); // body length
      req.setUint32(4, _magicCookie);

      final rng = Random();
      for (int i = 8; i < 20; i++) {
        req.setUint8(i, rng.nextInt(256));
      }

      socket.send(req.buffer.asUint8List(), ipv4, _stunPort);
    } catch (_) {}
  }

  // stun cevabından dış ip:port bilgisini çözer
  static String? parseResponse(Uint8List data) {
    if (!isStunPacket(data)) return null;
    final view = ByteData.sublistView(data);
    final msgLen = view.getUint16(2);

    int offset = 20;
    while (offset + 4 <= 20 + msgLen && offset + 4 <= data.length) {
      final attrType = view.getUint16(offset);
      final attrLen = view.getUint16(offset + 2);
      final valStart = offset + 4;

      if (valStart + attrLen > data.length) break;

      // 0x0020: XOR-MAPPED-ADDRESS, 0x0001: MAPPED-ADDRESS
      if ((attrType == 0x0020 || attrType == 0x0001) && attrLen >= 8) {
        final family = data[valStart + 1];
        if (family == 0x01) {
          final rawPort = view.getUint16(valStart + 2);
          final port = attrType == 0x0020 ? (rawPort ^ 0x2112) : rawPort;

          final cookieBytes = [0x21, 0x12, 0xA4, 0x42];
          final ipParts = <int>[];
          for (int i = 0; i < 4; i++) {
            final b = data[valStart + 4 + i];
            ipParts.add(attrType == 0x0020 ? (b ^ cookieBytes[i]) : b);
          }
          return '${ipParts.join('.')}:$port';
        }
      }

      // 4 byte hizalama
      offset = valStart + ((attrLen + 3) & ~3);
    }
    return null;
  }

  // "1.2.3.4:5000" veya "1.2.3.4" metnini ip ve porta ayırır
  static (InternetAddress, int)? parseTarget(String input, {int defaultPort = 5000}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length != 2) return null;
      final ip = InternetAddress.tryParse(parts[0].trim());
      final port = int.tryParse(parts[1].trim());
      if (ip == null || port == null || port <= 0 || port > 65535) return null;
      return (ip, port);
    } else {
      final ip = InternetAddress.tryParse(trimmed);
      if (ip == null) return null;
      return (ip, defaultPort);
    }
  }
}

