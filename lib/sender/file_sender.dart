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
  RawDatagramSocket? _socket;

  // paketleri numaralandırmak için kullanacağımız sayaç
  int _currentSequenceNumber = 0;
  // ack gelmemiş paketlerin byte halleri ve zamanlayıcıları
  final Map<int, dart_typed_data.Uint8List> _unackedPackets = {};
  final Map<int, RetransmitTimer> _timers = {};
  Completer<bool>? _ackCompleter;

  ReliableSender({required this.targetAddress, required this.targetPort});

  // soketi başlatır ve gelen cevapları (ACK) dinlemeye başlar
  Future<void> start() async {
    // 0 portu, işletim sisteminin bizim için rastgele boş bir port bulmasını sağlar
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    debugPrint('gönderici başlatıldı. yerel port: ${_socket?.port}');
    // karşı taraftan (receiver) gelecek cevapları dinliyoruz
    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = _socket?.receive();
        if (datagram != null) {
          _handleIncomingPacket(datagram.data);
        }
      }
    });
  }

  // karşıdan gelen cevapları (ACK paketlerini) işler
  void _handleIncomingPacket(List<int> data) {
    try {
      final packet = Packet.fromBytes(data as dart_typed_data.Uint8List);

      if (packet.type == PacketType.ack) {
        debugPrint('ACK alındı! sıra no: ${packet.sequenceNumber}');
        final seqNum = packet.sequenceNumber;
        if (_timers.containsKey(seqNum)) {
          _timers[seqNum]?.stop();
          _timers.remove(seqNum);
          _unackedPackets.remove(seqNum);
          debugPrint(
            'sıra No: $seqNum başarıyla teslim edildi. zamanlayıcı durduruldu.',
          );
        }

        if (!(_ackCompleter?.isCompleted ?? true)) {
          _ackCompleter?.complete(true);
        }
      }
    } catch (e) {
      debugPrint('gelen paket okunamadı (bozuk olabilir): $e');
    }
  }

  /// belirtilen veriyi bir paket haline getirip karşıya fırlatır
  Future<bool> sendPayload(dart_typed_data.Uint8List payload) async {
    if (_socket == null) {
      debugPrint('hata: soket henüz başlatılmamış');
      return false;
    }
    // her yeni paket gönderiminde yeni bir bekleyici (Completer) oluştur
    _ackCompleter = Completer<bool>();
    _currentSequenceNumber++;

    //  zarfımızı (paketimizi) hazırlıyoruz
    final packet = Packet(
      sequenceNumber: _currentSequenceNumber,
      type: PacketType.data, // İçinde veri olduğunu belirtiyoruz
      payload: payload,
    );

    //  zarfı internetten geçebilmesi için 0 ve 1'lere çeviriyoruz
    final bytes = packet.toBytes();
    //paketin byte halini hafızaya al(tekrar gödermek için gerekir)
    final seqNum = _currentSequenceNumber;
    _unackedPackets[seqNum] = bytes;

    //bu pakete özel kronometre başlat
    final timer = RetransmitTimer(
      timeout: ProtocolConstants.retransmissionTimeout,
      maxRetries: ProtocolConstants.maxRetries,
      onTimeout: () {
        if (_unackedPackets.containsKey(seqNum)) {
          _socket?.send(_unackedPackets[seqNum]!, targetAddress, targetPort);
        }
      },
      onFail: () {
        debugPrint('bağlantı koptu.sıra no: $seqNum karşıya iletilemiyor.');
        _timers.remove(seqNum);
        _unackedPackets.remove(seqNum);
        // eğer 5 denemede bile gitmezse işlemi başarısız (false) olarak sonlandır
        if (!(_ackCompleter?.isCompleted ?? true)) {
          _ackCompleter?.complete(
            false,
          ); // ACK geldi, beklemeyi başarıyla (true) bitir!
        }
      },
    );
    _timers[seqNum] = timer;
    timer.start();
    // udp soketinden karşı tarafın IP ve portuna ilk kez fırlatıyoruz
    _socket?.send(bytes, targetAddress, targetPort);
    debugPrint(
      'paket fırlatıldı! -> sıra no: $_currentSequenceNumber, boyut: ${bytes.length} byte',
    );
    return _ackCompleter!.future;
  }

  /// soketi kapatır
  void stop() {
    _socket?.close();
    debugPrint('gönderici durduruldu');
  }

  /// bütün parçalar başarıyla gönderildikten sonra karşıya "sosya bitti" paketini fırlatır
  Future<bool> sendFileEnd() async {
    if (_socket == null) return false;

    _ackCompleter = Completer<bool>();
    _currentSequenceNumber++;

    // zarfın tipini 'fileEnd' yapıyoruz, içi (payload) boş kalır
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
        debugPrint('bitiş paketi iletilemedi!');
        _timers.remove(seqNum);
        _unackedPackets.remove(seqNum);
        if (!(_ackCompleter?.isCompleted ?? true)) {
          _ackCompleter?.complete(false);
        }
      },
    );
    _timers[seqNum] = timer;
    timer.start();
    _socket?.send(bytes, targetAddress, targetPort);

    debugPrint(
      'dosya bitiş (fileEnd) paketi fırlatıldı! -> sıra no: $_currentSequenceNumber',
    );
    return _ackCompleter!.future;
  }
}
