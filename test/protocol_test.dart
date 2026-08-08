// Unit tests
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

void main() {
  group('packet protocol tests', () {
    test('paket basariyla encode ve decode edilmeli', () {
      // 1: göndermek için rastgele bir veri (payload) oluşturuyoruz
      final payload = Uint8List.fromList([10, 20, 30, 40]);
      //
      // 2: orjinal paketimizi yaratıyoruz (otomatik checksum hesaplanacak)
      final originalPacket = Packet(
        sequenceNumber: 42,
        type: PacketType.data,
        payload: payload,
      );
      //
      // 3: paketi ağdan gidiyormuş gibi 0 ve 1'lere (byte dizisine) çeviriyoruz
      final bytes = originalPacket.toBytes();
      //
      // 4: şimdi o byte dizisini sanki karşı bilgisayar almış gibi geri çözüyoruz
      final decodedPacket = Packet.fromBytes(bytes);
      //
      // 5: test: çözülen veriler orjinaliyle birebir aynı mı?
      expect(decodedPacket.sequenceNumber, 42);
      expect(decodedPacket.type, PacketType.data);
      expect(decodedPacket.payload, payload);
      //
      // checksum değerinin hiç bozulmadan karşıya ulaştığının kanıtı
      expect(decodedPacket.checksum, originalPacket.checksum);
    });
  });
}
