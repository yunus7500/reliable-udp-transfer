// The logic behind splitting a file into chunks and sending it
//
import 'dart:io';
import 'dart:async';
import 'dart:typed_data' as dart_typed_data;
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';
import 'package:reliable_udp_transfer/protocol/constants.dart';
import 'package:reliable_udp_transfer/core/retransmit_timer.dart';

class ReliableSender {
  final InternetAddress targetAddress;
  final int targetPort;
  final Function(String, {bool isError})? onLog;
  final int windowSize;

  RawDatagramSocket? _socket;
  int _currentSequenceNumber = 0;

  // ack gelmemiş paketlerin byte halleri ve zamanlayıcıları
  final Map<int, dart_typed_data.Uint8List> _unackedPackets = {};
  final Map<int, RetransmitTimer> _timers = {};

  // eğer ardı ardına 5 kez (maxRetry) ACK gelmezse bağlantı kopmuş sayılır
  bool _isConnectionBroken = false;

  ReliableSender({
    required this.targetAddress,
    required this.targetPort,
    this.onLog,
    this.windowSize = 5,
  });

  void _log(String message, {bool isError = false}) {
    debugPrint(message);
    onLog?.call(message, isError: isError);
  }

  // soketi başlatır ve gelen cevapları (ACK) dinlemeye başlar
  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _log('gönderici başlatıldı. yerel port: ${_socket?.port}');

    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = _socket?.receive();
        if (datagram != null) {
          _handleIncomingPacket(datagram.data);
        }
      }
    });
  }

  // karşıdan gelen cevapları (ack paketlerini) işler
  void _handleIncomingPacket(List<int> data) {
    try {
      final packet = Packet.fromBytes(data as dart_typed_data.Uint8List);

      if (packet.type == PacketType.ack) {
        final seqNum = packet.sequenceNumber;
        if (_timers.containsKey(seqNum)) {
          _timers[seqNum]?.stop();
          _timers.remove(seqNum);
          _unackedPackets.remove(seqNum);
          _log('ACK alındı -> sıra no: $seqNum (pencerede yer açıldı!)');
        }
      }
    } catch (e) {
      _log('gelen paket okunamadı: $e', isError: true);
    }
  }

  /// kayan pencerede yer açılana kadar (ACK gelene kadar) sistemi bekletir
  Future<void> _waitForWindow() async {
    while (_unackedPackets.length >= windowSize && !_isConnectionBroken) {
      await Future.delayed(
        const Duration(milliseconds: 5),
      ); // 5ms'de bir kontrol et
    }
    if (_isConnectionBroken) {
      throw Exception('Bağlantı koptuğu için işlem durduruldu.');
    }
  }

  /// havada (in-flight) olan tüm paketlerin ack'sı gelene kadar bekler
  Future<void> flush() async {
    while (_unackedPackets.isNotEmpty && !_isConnectionBroken) {
      await Future.delayed(const Duration(milliseconds: 5));
    }
    if (_isConnectionBroken) {
      throw Exception('Bağlantı koptuğu için işlem durduruldu.');
    }
  }

  /// belirtilen veriyi bir paket haline getirip karşıya fırlatır (Sliding Window)
  Future<bool> sendPayload(dart_typed_data.Uint8List payload) async {
    if (_socket == null) {
      _log('hata: soket henüz başlatılmamış', isError: true);
      return false;
    }

    try {
      // pencerede yer yoksa yer açılmasını bekle
      await _waitForWindow();
    } catch (e) {
      _log(e.toString(), isError: true);
      return false;
    }

    _currentSequenceNumber++;
    final packet = Packet(
      sequenceNumber: _currentSequenceNumber,
      type: PacketType.data,
      payload: payload,
    );

    final bytes = packet.toBytes();
    final seqNum = _currentSequenceNumber;
    _unackedPackets[seqNum] = bytes;

    final timer = RetransmitTimer(
      timeout: ProtocolConstants.retransmissionTimeout,
      maxRetries: ProtocolConstants.maxRetries,
      onTimeout: () {
        if (_unackedPackets.containsKey(seqNum)) {
          _socket?.send(_unackedPackets[seqNum]!, targetAddress, targetPort);
          _log('zaman aşımı. paket tekrar fırlatılıyor -> sıra no: $seqNum');
        }
      },
      onFail: () {
        _log(
          'bağlantı koptu. sıra no: $seqNum karşıya iletilemiyor.',
          isError: true,
        );
        _timers.remove(seqNum);
        _unackedPackets.remove(seqNum);
        _isConnectionBroken = true;
      },
    );

    _timers[seqNum] = timer;
    timer.start();
    _socket?.send(bytes, targetAddress, targetPort);

    _log('paket fırlatıldı -> sıra no: $seqNum');
    //  sliding window olduğu için beklemeyip true dönüyoruz.
    return true;
  }

  /// bütün parçalar başarıyla gönderildikten sonra karşıya "dosya bitti" paketini fırlatır
  Future<bool> sendFileEnd() async {
    if (_socket == null) return false;

    try {
      await _waitForWindow();
    } catch (e) {
      return false;
    }

    _currentSequenceNumber++;
    final packet = Packet(
      sequenceNumber: _currentSequenceNumber,
      type: PacketType.fileEnd,
      payload: dart_typed_data.Uint8List(0),
    );

    final bytes = packet.toBytes();
    final seqNum = _currentSequenceNumber;
    _unackedPackets[seqNum] = bytes;

    final timer = RetransmitTimer(
      timeout: ProtocolConstants.retransmissionTimeout,
      maxRetries: ProtocolConstants.maxRetries,
      onTimeout: () {
        if (_unackedPackets.containsKey(seqNum)) {
          _socket?.send(_unackedPackets[seqNum]!, targetAddress, targetPort);
        }
      },
      onFail: () {
        _log('bitiş paketi iletilemedi!', isError: true);
        _timers.remove(seqNum);
        _unackedPackets.remove(seqNum);
        _isConnectionBroken = true;
      },
    );

    _timers[seqNum] = timer;
    timer.start();
    _socket?.send(bytes, targetAddress, targetPort);

    _log('dosya bitiş (fileEnd) paketi fırlatıldı! -> sıra no: $seqNum');

    try {
      // gönderici sistemin tamamen kapanabilmesi için bitiş paketinin de ACK'sının gelmesini bekle
      await flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// soketi kapatır
  void stop() {
    _socket?.close();
    _log('gönderici durduruldu');
  }
}
