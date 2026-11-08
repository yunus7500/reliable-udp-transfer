import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// 4 haneli kod ile iki cihazın ip:port bilgilerini otomatik eşleştirir (mqtt tcp)
class SignalingClient {
  static const List<String> _brokers = [
    'broker.emqx.io',
    'broker.hivemq.com',
  ];
  static const int _port = 1883;

  Socket? _socket;
  Timer? _pingTimer;
  final BytesBuilder _buffer = BytesBuilder();
  void Function(String message)? onMessage;

  Future<bool> connectAndListen(String roomCode) async {
    await disconnect();

    for (final host in _brokers) {
      try {
        _socket = await Socket.connect(
          host,
          _port,
          timeout: const Duration(seconds: 4),
        );
        break;
      } catch (_) {}
    }

    if (_socket == null) return false;

    final clientId = 'rudp_${Random().nextInt(900000) + 100000}';
    _socket!.add(_buildConnectPacket(clientId));
    _socket!.add(_buildSubscribePacket('rudp_v1/$roomCode'));

    _socket!.listen(
      _onData,
      onError: (_) => disconnect(),
      onDone: () => disconnect(),
    );

    // bağlantıyı canlı tutmak için 25 saniyede bir ping
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _socket?.add(Uint8List.fromList([0xC0, 0x00]));
      } catch (_) {}
    });

    return true;
  }

  void publish(String roomCode, String message) {
    if (_socket == null) return;
    try {
      _socket!.add(_buildPublishPacket('rudp_v1/$roomCode', message));
    } catch (_) {}
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    final data = _buffer.toBytes();
    int offset = 0;

    while (offset + 2 <= data.length) {
      final header = data[offset];
      int multiplier = 1;
      int remLen = 0;
      int lenBytes = 0;

      // mqtt değişken uzunluk çözümü
      while (true) {
        if (offset + 1 + lenBytes >= data.length) return;
        final encodedByte = data[offset + 1 + lenBytes];
        remLen += (encodedByte & 127) * multiplier;
        lenBytes++;
        multiplier *= 128;
        if ((encodedByte & 128) == 0) break;
      }

      final packetEnd = offset + 1 + lenBytes + remLen;
      if (packetEnd > data.length) break;

      // 0x30: gelen publish paketi
      if ((header & 0xF0) == 0x30) {
        final bodyStart = offset + 1 + lenBytes;
        final topicLen = (data[bodyStart] << 8) | data[bodyStart + 1];
        final msgStart = bodyStart + 2 + topicLen;
        if (msgStart <= packetEnd) {
          final msg = utf8.decode(
            data.sublist(msgStart, packetEnd),
            allowMalformed: true,
          );
          onMessage?.call(msg);
        }
      }

      offset = packetEnd;
    }

    _buffer.clear();
    if (offset < data.length) {
      _buffer.add(data.sublist(offset));
    }
  }

  Uint8List _buildConnectPacket(String clientId) {
    final idBytes = utf8.encode(clientId);
    final payload = <int>[
      0x00, 0x04, 0x4D, 0x51, 0x54, 0x54, // "MQTT"
      0x04, // seviye 4 (3.1.1)
      0x02, // clean session
      0x00, 0x3C, // keepalive 60sn
      (idBytes.length >> 8) & 0xFF, idBytes.length & 0xFF,
      ...idBytes,
    ];
    return _wrapFixedHeader(0x10, payload);
  }

  Uint8List _buildSubscribePacket(String topic) {
    final tBytes = utf8.encode(topic);
    final payload = <int>[
      0x00, 0x01, // paket id
      (tBytes.length >> 8) & 0xFF, tBytes.length & 0xFF,
      ...tBytes,
      0x00, // qos 0
    ];
    return _wrapFixedHeader(0x82, payload);
  }

  Uint8List _buildPublishPacket(String topic, String message) {
    final tBytes = utf8.encode(topic);
    final mBytes = utf8.encode(message);
    final payload = <int>[
      (tBytes.length >> 8) & 0xFF, tBytes.length & 0xFF,
      ...tBytes,
      ...mBytes,
    ];
    return _wrapFixedHeader(0x30, payload);
  }

  Uint8List _wrapFixedHeader(int type, List<int> body) {
    final out = <int>[type];
    int x = body.length;
    do {
      int encoded = x % 128;
      x = x ~/ 128;
      if (x > 0) encoded |= 128;
      out.add(encoded);
    } while (x > 0);
    out.addAll(body);
    return Uint8List.fromList(out);
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _buffer.clear();
  }
}

