import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:reliable_udp_transfer/core/platform_helper.dart';
import 'package:reliable_udp_transfer/core/retransmit_timer.dart';
import 'package:reliable_udp_transfer/protocol/constants.dart';
import 'package:reliable_udp_transfer/protocol/file_meta.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableSender {
  final InternetAddress targetAddress;
  final int targetPort;
  final int windowSize;
  final RawDatagramSocket? sharedSocket;
  final void Function(String, {bool isError})? onLog;
  final void Function(int sentBytes, int totalBytes)? onProgress;

  RawDatagramSocket? _socket;
  bool _ownsSocket = false;
  final Map<int, Uint8List> _unackedPackets = {};
  final Map<int, RetransmitTimer> _timers = {};
  Completer<void>? _windowSignal;

  bool _isBroken = false;
  int _ackedDataPackets = 0;
  int _totalChunks = 0;
  int _totalBytes = 0;
  int _lastReportedPercent = -1;

  ReliableSender({
    required this.targetAddress,
    required this.targetPort,
    this.sharedSocket,
    this.windowSize = ProtocolConstants.windowSize,
    this.onLog,
    this.onProgress,
  });

  void _log(String msg, {bool isError = false}) {
    onLog?.call(msg, isError: isError);
  }

  Future<void> start() async {
    if (sharedSocket != null) {
      _socket = sharedSocket;
      _ownsSocket = false;
      return;
    }

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _ownsSocket = true;
    _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket?.receive();
        if (dg != null) _onDatagram(dg.data);
      }
    });
  }

  void _onDatagram(Uint8List data) {
    try {
      final packet = Packet.fromBytes(data);
      if (packet.type == PacketType.ack) {
        handleAck(packet.sequenceNumber);
      }
    } catch (_) {}
  }

  // ack geldiğinde pencereyi kaydırır
  void handleAck(int seq) {
    if (_unackedPackets.containsKey(seq)) {
      _timers[seq]?.stop();
      _timers.remove(seq);
      _unackedPackets.remove(seq);
      if (seq > 0 && seq <= _totalChunks) {
        _ackedDataPackets++;
        _reportProgressIfChanged();
      }

      if (_windowSignal != null && !_windowSignal!.isCompleted) {
        _windowSignal!.complete();
      }
    }
  }

  Future<bool> sendFile(File file, String fileName) async {
    _totalBytes = await file.length();
    _totalChunks = (_totalBytes / ProtocolConstants.maxPayloadSize).ceil();
    _ackedDataPackets = 0;
    _lastReportedPercent = -1;
    _isBroken = false;

    _log(
      'Gönderiliyor: "$fileName" (${PlatformHelper.formatBytes(_totalBytes)})',
    );

    // 0. paket: dosya adı ve boyutu (handshake)
    final meta = FileMeta(fileName: fileName, fileSize: _totalBytes);
    _enqueuePacket(0, PacketType.handshakeInit, meta.toBytes());
    if (!await _waitAllAcked()) return false;

    final raf = await file.open(mode: FileMode.read);
    try {
      for (int seq = 1; seq <= _totalChunks; seq++) {
        while (_unackedPackets.length >= windowSize && !_isBroken) {
          _windowSignal = Completer<void>();
          await _windowSignal!.future;
        }
        if (_isBroken) return false;

        final chunk = await raf.read(ProtocolConstants.maxPayloadSize);
        _enqueuePacket(seq, PacketType.data, chunk);
      }

      if (!await _waitAllAcked()) return false;

      // bitiş paketi
      _enqueuePacket(_totalChunks + 1, PacketType.fileEnd, Uint8List(0));
      if (!await _waitAllAcked()) return false;

      onProgress?.call(_totalBytes, _totalBytes);
      _log('Gönderim tamamlandı: "$fileName" karşı cihaza ulaştı.');
      return true;
    } finally {
      await raf.close();
    }
  }

  void _reportProgressIfChanged() {
    if (_totalChunks == 0) return;
    final percent = (_ackedDataPackets * 100) ~/ _totalChunks;
    if (percent != _lastReportedPercent) {
      _lastReportedPercent = percent;
      final doneBytes = (_ackedDataPackets * ProtocolConstants.maxPayloadSize)
          .clamp(0, _totalBytes);
      onProgress?.call(doneBytes, _totalBytes);
    }
  }

  void _enqueuePacket(int seq, PacketType type, Uint8List payload) {
    final packet = Packet(sequenceNumber: seq, type: type, payload: payload);
    final bytes = packet.toBytes();
    _unackedPackets[seq] = bytes;

    final timer = RetransmitTimer(
      timeout: ProtocolConstants.retransmissionTimeout,
      maxRetries: ProtocolConstants.maxRetries,
      onTimeout: () {
        final raw = _unackedPackets[seq];
        if (raw != null) _socket?.send(raw, targetAddress, targetPort);
      },
      onFail: () {
        _timers.remove(seq);
        _unackedPackets.remove(seq);
        _isBroken = true;
        if (_windowSignal != null && !_windowSignal!.isCompleted) {
          _windowSignal!.complete();
        }
      },
    );

    _timers[seq] = timer;
    timer.start();
    _socket?.send(bytes, targetAddress, targetPort);
  }

  Future<bool> _waitAllAcked() async {
    while (_unackedPackets.isNotEmpty && !_isBroken) {
      _windowSignal = Completer<void>();
      await _windowSignal!.future;
    }
    return !_isBroken;
  }

  void stop() {
    for (final t in _timers.values) {
      t.stop();
    }
    _timers.clear();
    _unackedPackets.clear();
    if (_ownsSocket) {
      _socket?.close();
    }
    _socket = null;
  }
}
