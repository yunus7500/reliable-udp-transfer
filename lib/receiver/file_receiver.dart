// Logic for picking up and sorting/combining chunks
import 'dart:io';
import 'dart:typed_data' as dart_typed_data;
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableReceiver {
  final int listenPort;
  RawDatagramSocket? _socket;
  ReliableReceiver({required this.listenPort});

  // soketi başlatır , belirtilen portu dinlemeye başlar
  Future<void> start() async {
    // anyIPv4 diyerek tüm ağ arayüzlerinden gelen verileri dinliyoruz

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, listenPort);
    debugPrint('alıcı başlatıldı, dinlenen port : $listenPort');

    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = _socket?.receive();
        if (datagram != null) {
          // paketi, kimden gedliği bilgisi ile (IP ve port) birlikte işleme al
          _handleIncomingPacket(datagram.data, datagram.address, datagram.port);
        }
      }
    });
  }

  // gelen paketleri işler ve "aldım (ack) cevabı gönderir"
  void _handleIncomingPacket(
    List<int> data,
    InternetAddress senderAddress,
    int senderPort,
  ) {
    try {
      final packet = Packet.fromBytes(data as dart_typed_data.Uint8List);
      // sadece 'data' tipli paketleri al
      if (packet.type == PacketType.data) {
        debugPrint(
          'veri paketi başarıyla yakalandı ,sıra no:${packet.sequenceNumber},boyut:${packet.payload.length} byte',
        );

        // paketi aldık ack demeliyiz
        _sendAck(packet.sequenceNumber, senderAddress, senderPort);
      }
    } catch (e) {
      debugPrint('alıcı gelen paketi okuyamadı (bozuk olabilir): $e');
    }
  }

  void _sendAck(
    int sequenceNumber,
    InternetAddress targetAddress,
    int targetPort,
  ) {
    if (_socket == null) return;

    final ackPacket = Packet(
      sequenceNumber: sequenceNumber,
      type: PacketType.ack,
      payload: dart_typed_data.Uint8List(0),
    );

    _socket?.send(ackPacket.toBytes(), targetAddress, targetPort);

    debugPrint('ack gönderildi! -> sıra no: $sequenceNumber');
  }

  void stop() {
    _socket?.close();
    debugPrint('alıcı durduruldu');
  }
}
