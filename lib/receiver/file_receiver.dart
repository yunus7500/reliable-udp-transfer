// Logic for picking up and sorting/combining chunks
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' as dart_typed_data;
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableReceiver {
  final int listenPort;
  RawDatagramSocket? _socket;
  // gelen parçaları sırasına göre biriktireceğimiz liste
  final Map<int, dart_typed_data.Uint8List> _receivedChunks = {};
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

      if (packet.type == PacketType.data) {
        _receivedChunks[packet.sequenceNumber] = packet.payload;
        debugPrint(
          'Parça başarıyla --yakalandı-- ve --kaydedildi-- sıra no: ${packet.sequenceNumber}',
        );
        _sendAck(packet.sequenceNumber, senderAddress, senderPort);
      } else if (packet.type == PacketType.fileEnd) {
        debugPrint(
          '\n"Dosya Bitti" paketi alındı! Parçalar birleştiriliyor...',
        );
        _assembleFile(); // parçaları birleştiren fonksiyonu çağır
        _sendAck(
          packet.sequenceNumber,
          senderAddress,
          senderPort,
        ); // göndericiye 'bitiş onayını da aldım' de
      }
    } catch (e) {
      debugPrint('alıcı gelen paketi okuyamadı (bozuk olabilir): $e');
    }
  }

  void _assembleFile() {
    if (_receivedChunks.isEmpty) return;
    final sortedKeys = _receivedChunks.keys.toList()..sort();
    final builder = BytesBuilder();
    int totalLength = 0;

    for (var key in sortedKeys) {
      final chunkData = _receivedChunks[key]!;
      builder.add(chunkData);
      totalLength += chunkData.length;
    }
    // birleştirilmiş tam dosyanın byte hali
    final complateFileBytes = builder.takeBytes();
    //test amaçlı: byte ları tekrar okunabilir metne çevirip konsola
    final completeText = String.fromCharCodes(complateFileBytes);

    debugPrint('\n dosya başarıyla birleştirildi');
    debugPrint('toplam boyut: $totalLength byte');
    debugPrint('dosyanın asıl içeriği: $completeText\n');
    _receivedChunks.clear();
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
