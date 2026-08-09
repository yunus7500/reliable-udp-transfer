// Logic for picking up and sorting/combining chunks
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' as dart_typed_data;
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/protocol/packet.dart';
import 'package:reliable_udp_transfer/protocol/packet_type.dart';

class ReliableReceiver {
  final int listenPort;
  final Function(String, {bool isError})? onLog;
  RawDatagramSocket? _socket;

  // gelen parçaları sırasına göre biriktireceğimiz liste
  final Map<int, dart_typed_data.Uint8List> _receivedChunks = {};

  ReliableReceiver({required this.listenPort, this.onLog});

  void _log(String message, {bool isError = false}) {
    debugPrint(message);
    onLog?.call(message, isError: isError);
  }

  // soketi başlatır, belirtilen portu dinlemeye başlar
  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, listenPort);
    _log('alıcı başlatıldı, dinlenen port: $listenPort');

    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = _socket?.receive();
        if (datagram != null) {
          _handleIncomingPacket(datagram.data, datagram.address, datagram.port);
        }
      }
    });
  }

  // gelen paketleri işler ve "aldım (ack)" cevabı gönderir
  void _handleIncomingPacket(
    List<int> data,
    InternetAddress senderAddress,
    int senderPort,
  ) {
    try {
      final packet = Packet.fromBytes(data as dart_typed_data.Uint8List);

      if (packet.type == PacketType.data) {
        _receivedChunks[packet.sequenceNumber] = packet.payload;
        _log(
          'parça başarıyla yakalandı ve kaydedildi. Sıra no: ${packet.sequenceNumber}',
        );
        _sendAck(packet.sequenceNumber, senderAddress, senderPort);
      } else if (packet.type == PacketType.fileEnd) {
        _log('\n"osya Bitti" paketi alındı! parçalar birleştiriliyor...');
        _assembleFile();
        _sendAck(packet.sequenceNumber, senderAddress, senderPort);
      }
    } catch (e) {
      _log('alıcı gelen paketi okuyamadı (bozuk olabilir): $e', isError: true);
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

    final completeFileBytes = builder.takeBytes();
    final completeText = String.fromCharCodes(completeFileBytes);

    _log('dosya başarıyla birleştirildi');
    _log('toplam boyut: $totalLength byte');
    _log('dosyanın asıl içeriği: $completeText\n');
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
    debugPrint('ACK gönderildi -> sıra no: $sequenceNumber');
  }

  void stop() {
    _socket?.close();
    _log('alıcı durduruldu');
  }
}
