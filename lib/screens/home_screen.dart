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

  bool isSending = false;
  String localIp = 'yükleniyor...';
  final TextEditingController _ipController = TextEditingController(
    text: '127.0.0.1',
  );
  List<Map<String, dynamic>> systemLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchLocalIp();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          ips.add('${addr.address} (${interface.name})');
        }
      }
      if (mounted) {
        setState(() {
          localIp = ips.isEmpty ? '127.0.0.1' : ips.join(', ');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          localIp = 'alınamadı';
        });
      }
    }
  }

  @override
  void dispose() {
    receiver?.stop();
    sender?.stop();
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String source, String message, {bool isError = false}) {
    setState(() {
      systemLogs.add({
        'source': source,
        'message': message,
        'isError': isError,
      });
    });

    // liste güncellendiğinde otomatik en alta kaydır
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startReceiver() async {
    receiver = ReliableReceiver(
      listenPort: 5000,
      onLog: (msg, {isError = false}) =>
          _addLog('alıcı', msg, isError: isError),
    );
    await receiver?.start();
    setState(() {});
  }

  void _startSenderAndSend() async {
    if (isSending) return;

    final ipText = _ipController.text.trim();
    final parsedIp = InternetAddress.tryParse(ipText);
    if (parsedIp == null) {
      _addLog(
        'sistem',
        'hata: geçersiz IP adresi ($ipText)',
        isError: true,
      );
      return;
    }

    setState(() {
      isSending = true;
    });

    sender?.stop();
    sender = ReliableSender(
      targetAddress: parsedIp,
      targetPort: 5000,
      windowSize: 5,
      onLog: (msg, {isError = false}) =>
          _addLog('gönderici', msg, isError: isError),
    );
    await sender?.start();

    final messages = List.generate(100, (i) => "veri parçası ${i + 1}");

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final messageBytes = Uint8List.fromList(msg.codeUnits);

      // sonsuza kadar beklemez, pencere  dolana kadar gönderip devam eder
      bool success = await sender!.sendPayload(messageBytes);
      if (!success) {
        _addLog(
          'sistem',
          'hata: bağlantı tamamen koptu. dosya transferi iptal edildi.',
          isError: true,
        );
        setState(() {
          isSending = false;
        });
        return;
      }
    }

    // bütün parçalar fırlatıldıktan sonra bitiş paketini fırlat
    //  aynı zamanda "Flush" yapar, yani 100 paketin de ACK'sı gelene kadar bekler
    await sender!.sendFileEnd();
    _addLog('sistem', 'dosya transferi tamamlandı!');
    setState(() {
      isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('udp kayan pencere (sliding window) testi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        'Bu cihazın IP\'si: $localIp',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'IP Yenile',
                      onPressed: _fetchLocalIp,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Hedef (Alıcı) IP Adresi',
                    hintText: 'Örn: 192.168.1.45 veya 127.0.0.1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: receiver == null ? _startReceiver : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade100,
                      ),
                      child: const Text('1--alıcıyı başlat'),
                    ),
                    ElevatedButton(
                      onPressed: (!isSending) ? _startSenderAndSend : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade100,
                      ),
                      child: isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('2--gönderimi başlat'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'sistem logları (canlı izleme)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: systemLogs.length,
              itemBuilder: (context, index) {
                final log = systemLogs[index];
                final source = log['source'];
                final isError = log['isError'];

                Color bgColor = Colors.transparent;
                Color textColor = Colors.black87;

                if (source == 'gönderici') {
                  bgColor = Colors.blue.withValues(alpha: 0.05);
                  textColor = Colors.blue.shade900;
                } else if (source == 'alıcı') {
                  bgColor = Colors.green.withValues(alpha: 0.05);
                  textColor = Colors.green.shade900;
                } else if (source == 'sistem') {
                  bgColor = Colors.orange.withValues(alpha: 0.1);
                  textColor = Colors.orange.shade900;
                }

                if (isError) textColor = Colors.red;

                return Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          '[$source]',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          log['message'],
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
