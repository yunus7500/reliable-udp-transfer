// The logic behind splitting a file into chunks and sending it
//
import 'dart:io';
import 'dart:typed_data' as dart_typed_data;
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableSender {
  final InternetAddress targetAddress;
  final int targetPort;
  RawDatagramSocket? _socket;

  // paketleri numaralandırmak için kullanacağımız sayaç
  int _currentSequenceNumber = 0;

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
      }
    } catch (e) {
      debugPrint('gelen paket okunamadı (bozuk olabilir): $e');
    }
  }

  /// belirtilen veriyi bir paket haline getirip karşıya fırlatır
  void sendPayload(dart_typed_data.Uint8List payload) {
    if (_socket == null) {
      debugPrint('hata: soket henüz başlatılmamış! önce start() çağrılmalı');
      return;
    }
    _currentSequenceNumber++;

    // 1: zarfımızı (paketimizi) hazırlıyoruz
    final packet = Packet(
      sequenceNumber: _currentSequenceNumber,
      type: PacketType.data, // İçinde veri olduğunu belirtiyoruz
      payload: payload,
    );

    // 2: zarfı internetten geçebilmesi için 0 ve 1'lere çeviriyoruz
    final bytes = packet.toBytes();

    // 3: UDP soketinden karşı tarafın IP ve Portuna fırlatıyoruz (Piyuuuv!)
    _socket?.send(bytes, targetAddress, targetPort);

    debugPrint(
      'paket fırlatıldı! -> sıra no: $_currentSequenceNumber, boyut: ${bytes.length} byte',
    );
  }

  /// soketi kapatır
  void stop() {
    _socket?.close();
    debugPrint('gönderici durduruldu');
  }
}
