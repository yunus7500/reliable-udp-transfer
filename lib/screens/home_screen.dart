import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:reliable_udp_transfer/receiver/file_receiver.dart';
import 'package:reliable_udp_transfer/sender/file_sender.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ReliableReceiver? receiver;
  ReliableSender? sender;

  @override
  void dispose() {
    receiver?.stop();
    sender?.stop();
    super.dispose();
  }

  void _startReceiver() async {
    receiver = ReliableReceiver(listenPort: 5000);
    await receiver?.start();
    setState(() {});
  }

  void _startSenderAndSend() async {
    if (sender == null) {
      sender = ReliableSender(
        targetAddress: InternetAddress.loopbackIPv4,
        targetPort: 5000,
      );
      await sender?.start();
    }
    //
    final messages = [
      "parça 1: merhaba",
      "parça 2: bu güvenilir",
      "parça 3: bir dosya",
      "parça 4: transfer",
      "parça 5: denemesidir!",
    ];

    //
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final messageBytes = Uint8List.fromList(msg.codeUnits);
      debugPrint("\n--- gönderim başlıyor: $msg ---");
      //
      //sistem ACK gelene kadar burada bekleyecek
      bool success = await sender!.sendPayload(messageBytes);
      if (!success) {
        debugPrint(
          'hata: bağlantı tamamen koptu. dosya transferi iptal edildi.',
        );
        break;
      }
    }
    debugPrint("\n dosya transferi tamamlandı!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UDP test ekranı'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: receiver == null ? _startReceiver : null,
              child: const Text('1--alıcıyı başlat (Port 5000)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: receiver != null ? _startSenderAndSend : null,
              child: const Text('2--göndericiyi başlat ve paket fırlat'),
            ),
          ],
        ),
      ),
    );
  }
}
