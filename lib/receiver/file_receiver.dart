import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:reliable_udp_transfer/core/platform_helper.dart';
import 'package:reliable_udp_transfer/core/stun_client.dart';
import 'package:reliable_udp_transfer/protocol/constants.dart';
import 'package:reliable_udp_transfer/protocol/file_meta.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableReceiver {
  final int listenPort;
  final String saveDir;
  final void Function(String, {bool isError})? onLog;
  final void Function(int receivedBytes, int totalBytes)? onProgress;
  final void Function(String publicAddr)? onPublicAddress;
  final void Function(String filePath)? onFileSaved;

  // gönderici aynı soketi kullandığında gelen ack paketlerini iletmek için
  void Function(int seq)? onAckReceived;
  void Function(InternetAddress addr, int port)? onPeerVerified;

  RawDatagramSocket? _socket;
  RandomAccessFile? _raf;
  Uint8List? _receivedBitmap;
  String? _currentFilePath;
  int _expectedSize = 0;
  int _receivedBytes = 0;
  int _lastPercent = -1;

  ReliableReceiver({
    required this.listenPort,
    required this.saveDir,
    this.onLog,
    this.onProgress,
    this.onPublicAddress,
    this.onFileSaved,
  });

  RawDatagramSocket? get socket => _socket;
  int get activePort => _socket?.port ?? listenPort;

  void _log(String msg, {bool isError = false}) {
    onLog?.call(msg, isError: isError);
  }

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, listenPort);
    } catch (_) {
      // 5000 portu doluysa boş bir port al
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }

    _log('Cihaz hazır, dosya gönderimi veya alımı bekleniyor.');

    _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket?.receive();
        if (dg != null) {
          _handleDatagram(dg.data, dg.address, dg.port);
        }
      }
    });

    await refreshPublicAddress();
  }

  Future<void> refreshPublicAddress() async {
    if (_socket != null) {
      await StunClient.sendRequest(_socket!);
    }
  }

  // verilen aday adreslere nat deliği açmak için sinyal paketleri gönderir
  Future<void> punchCandidates(List<(InternetAddress, int)> targets) async {
    if (_socket == null || targets.isEmpty) return;
    final probe = Packet(
      sequenceNumber: 1,
      type: PacketType.handshakeAck,
      payload: Uint8List(0),
    ).toBytes();

    for (int i = 0; i < 6; i++) {
      for (final t in targets) {
        _socket?.send(probe, t.$1, t.$2);
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _handleDatagram(Uint8List data, InternetAddress addr, int port) {
    // 1. stun sunucusundan gelen dış ip cevabı mı?
    if (StunClient.isStunPacket(data)) {
      final pub = StunClient.parseResponse(data);
      if (pub != null) {
        onPublicAddress?.call(pub);
      }
      return;
    }

    // 2. kendi protokol paketimiz
    try {
      final packet = Packet.fromBytes(data);

      if (packet.type == PacketType.ack) {
        onAckReceived?.call(packet.sequenceNumber);
      } else if (packet.type == PacketType.handshakeAck) {
        // seq 1 ise karşıya "aldım" cevabı (seq 2) dön
        if (packet.sequenceNumber == 1) {
          final reply = Packet(
            sequenceNumber: 2,
            type: PacketType.handshakeAck,
            payload: Uint8List(0),
          ).toBytes();
          _socket?.send(reply, addr, port);
        }
        onPeerVerified?.call(addr, port);
      } else if (packet.type == PacketType.handshakeInit) {
        _onHandshake(packet.payload);
        _sendAck(packet.sequenceNumber, addr, port);
      } else if (packet.type == PacketType.data) {
        _onData(packet.sequenceNumber, packet.payload);
        _sendAck(packet.sequenceNumber, addr, port);
      } else if (packet.type == PacketType.fileEnd) {
        _sendAck(packet.sequenceNumber, addr, port);
        _onFileEnd();
      }
    } catch (_) {}
  }

  void _onHandshake(Uint8List payload) {
    if (_raf != null) return;

    final meta = FileMeta.fromBytes(payload);
    final safeName = meta.fileName.replaceAll(RegExp(r'[/\\]'), '_');
    _currentFilePath = '$saveDir${Platform.pathSeparator}$safeName';
    _expectedSize = meta.fileSize;
    _receivedBytes = 0;
    _lastPercent = -1;

    final totalChunks = (_expectedSize / ProtocolConstants.maxPayloadSize).ceil();
    _receivedBitmap = Uint8List((totalChunks + 7) >> 3);

    try {
      _raf = File(_currentFilePath!).openSync(mode: FileMode.write);
    } catch (_) {
      _currentFilePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}$safeName';
      _raf = File(_currentFilePath!).openSync(mode: FileMode.write);
    }
    _log(
      'Dosya alınıyor: "$safeName" (${PlatformHelper.formatBytes(meta.fileSize)})',
    );
    onProgress?.call(0, _expectedSize);
  }

  void _onData(int seq, Uint8List payload) {
    if (_raf == null || _receivedBitmap == null || seq < 1) return;

    final index = seq - 1;
    final byteIdx = index >> 3;
    final bitMask = 1 << (index & 7);

    if (byteIdx < _receivedBitmap!.length &&
        (_receivedBitmap![byteIdx] & bitMask) == 0) {
      _receivedBitmap![byteIdx] |= bitMask;

      final offset = index * ProtocolConstants.maxPayloadSize;
      _raf!.setPositionSync(offset);
      _raf!.writeFromSync(payload);

      _receivedBytes += payload.length;
      if (_expectedSize > 0) {
        final percent = (_receivedBytes * 100) ~/ _expectedSize;
        if (percent != _lastPercent) {
          _lastPercent = percent;
          onProgress?.call(_receivedBytes, _expectedSize);
        }
      }
    }
  }

  void _onFileEnd() {
    if (_raf == null) return;
    _raf!.flushSync();
    _raf!.closeSync();
    _raf = null;
    _receivedBitmap = null;

    onProgress?.call(_expectedSize, _expectedSize);
    final fileName = _currentFilePath?.split(Platform.pathSeparator).last ?? '';
    _log('İndirme tamamlandı: "$fileName" cihaza kaydedildi.');
    if (_currentFilePath != null) {
      onFileSaved?.call(_currentFilePath!);
    }
  }

  void _sendAck(int seq, InternetAddress addr, int port) {
    final ack = Packet(
      sequenceNumber: seq,
      type: PacketType.ack,
      payload: Uint8List(0),
    );
    _socket?.send(ack.toBytes(), addr, port);
  }

  void stop() {
    _raf?.closeSync();
    _raf = null;
    _socket?.close();
    _socket = null;
  }
}
