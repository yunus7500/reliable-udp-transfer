import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reliable_udp_transfer/core/platform_helper.dart';
import 'package:reliable_udp_transfer/core/signaling_client.dart';
import 'package:reliable_udp_transfer/core/stun_client.dart';
import 'package:reliable_udp_transfer/receiver/file_receiver.dart';
import 'package:reliable_udp_transfer/screens/info_widgets.dart';
import 'package:reliable_udp_transfer/sender/file_sender.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ReliableReceiver? _receiver;
  ReliableSender? _sender;
  final SignalingClient _roomListener = SignalingClient();

  final TextEditingController _targetController = TextEditingController();
  final List<String> _logs = [];

  late final String _myCode = (Random().nextInt(9000) + 1000).toString();
  String _localIp = '...';
  String _publicAddr = '';
  String _saveDir = '';
  String? _lastSavedFile;
  bool _isSending = false;
  int _doneBytes = 0;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    final ip = await PlatformHelper.getLocalIp();
    final dir = await PlatformHelper.getSaveDir();
    if (!mounted) return;
    setState(() {
      _localIp = ip;
      _saveDir = dir;
    });
    await _startReceiver();
    await _startSignalingListener();
  }

  @override
  void dispose() {
    _roomListener.disconnect();
    _receiver?.stop();
    _sender?.stop();
    _targetController.dispose();
    super.dispose();
  }

  void _log(String text) {
    if (!mounted) return;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    setState(() => _logs.add('[$hh:$mm] $text'));
  }

  void _updateProgress(int done, int total) {
    if (!mounted) return;
    setState(() {
      _doneBytes = done;
      _totalBytes = total;
    });
  }

  Future<void> _pasteTarget() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _targetController.text = data!.text!.trim());
    }
  }

  Future<void> _startReceiver() async {
    if (_receiver != null) return;
    await PlatformHelper.setBackgroundActive(true);
    _receiver = ReliableReceiver(
      listenPort: 5000,
      saveDir: _saveDir,
      onLog: (msg, {isError = false}) => _log(msg),
      onProgress: _updateProgress,
      onPublicAddress: (pub) {
        if (mounted) setState(() => _publicAddr = pub);
      },
      onFileSaved: (path) {
        if (mounted) setState(() => _lastSavedFile = path);
        if (Platform.isAndroid) {
          PlatformHelper.shareFile(path);
        }
      },
    );
    await _receiver!.start();
    if (mounted) setState(() {});
  }

  // alıcı olarak kendi 4 haneli odamızı dinler, istek gelince otomatik delik açar
  Future<void> _startSignalingListener() async {
    _roomListener.onMessage = (msg) {
      if (!msg.startsWith('REQ|')) return;
      final parts = msg.split('|');
      if (parts.length < 3) return;

      final senderLocal = StunClient.parseTarget(parts[1]);
      final senderPub = StunClient.parseTarget(parts[2]);

      final port = _receiver?.activePort ?? 5000;
      _roomListener.publish(_myCode, 'RES|$_localIp:$port|$_publicAddr');
      _log('Karşı cihaz bağlandı, dosya alımı hazırlanıyor...');

      final candidates = <(InternetAddress, int)>[?senderLocal, ?senderPub];
      _receiver?.punchCandidates(candidates);
    };

    await _roomListener.connectAndListen(_myCode);
  }

  // 4 haneli kodu veya doğrudan yazılan ip adresini gerçek udp hedefine çevirir
  Future<(InternetAddress, int)?> _resolveTarget(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    if (input.contains('.')) {
      return StunClient.parseTarget(input);
    }

    if (input == _myCode) {
      _log(
        'Hata: Kendi cihaz kodunuzu yazdınız. Lütfen karşı cihazdaki kodu girin.',
      );
      return null;
    }

    _log('$input kodlu cihaza bağlanılıyor...');
    await _receiver?.refreshPublicAddress();

    final sig = SignalingClient();
    final resCompleter = Completer<(String, String)?>();

    sig.onMessage = (msg) {
      if (msg.startsWith('RES|') && !resCompleter.isCompleted) {
        final parts = msg.split('|');
        if (parts.length >= 3) {
          resCompleter.complete((parts[1], parts[2]));
        }
      }
    };

    final connected = await sig.connectAndListen(input);
    if (!connected) {
      _log('Hata: İnternet bağlantısı kurulamadı.');
      return null;
    }

    final myPort = _receiver?.activePort ?? 5000;
    for (int i = 0; i < 4 && !resCompleter.isCompleted; i++) {
      sig.publish(input, 'REQ|$_localIp:$myPort|$_publicAddr');
      await Future.any([
        resCompleter.future,
        Future.delayed(const Duration(seconds: 1)),
      ]);
    }
    await sig.disconnect();

    if (!resCompleter.isCompleted) {
      _log(
        'Hata: $input kodlu cihaza ulaşılamadı. Karşı cihazda uygulamanın açık olduğundan emin olun.',
      );
      return null;
    }

    final addrs = await resCompleter.future;
    final recLocal = StunClient.parseTarget(addrs!.$1);
    final recPub = StunClient.parseTarget(addrs.$2);

    final candidates = <(InternetAddress, int)>[?recLocal, ?recPub];
    if (candidates.isEmpty) return null;

    final udpVerified = Completer<(InternetAddress, int)>();
    _receiver?.onPeerVerified = (addr, port) {
      if (!udpVerified.isCompleted) {
        udpVerified.complete((addr, port));
      }
    };

    _receiver?.punchCandidates(candidates);

    final chosen = await Future.any([
      udpVerified.future,
      Future.delayed(
        const Duration(milliseconds: 1800),
        () => recPub ?? recLocal!,
      ),
    ]);
    _receiver?.onPeerVerified = null;
    _log('Bağlantı kuruldu, aktarım başlıyor...');
    return chosen;
  }

  Future<void> _pickAndSendFile() async {
    if (_isSending) return;

    final rawTarget = _targetController.text.trim();
    if (rawTarget.isEmpty) {
      _log('Lütfen önce karşı cihazda yazan 4 haneli kodu kutuya girin.');
      return;
    }

    final picked = await PlatformHelper.pickFile();
    if (picked == null) return;

    await _startReceiver();
    setState(() {
      _isSending = true;
      _doneBytes = 0;
      _totalBytes = picked.size;
    });

    final target = await _resolveTarget(rawTarget);
    if (target == null) {
      if (mounted) setState(() => _isSending = false);
      return;
    }

    await PlatformHelper.setBackgroundActive(true);
    _sender?.stop();
    _sender = ReliableSender(
      targetAddress: target.$1,
      targetPort: target.$2,
      sharedSocket: _receiver?.socket,
      onLog: (msg, {isError = false}) => _log(msg),
      onProgress: _updateProgress,
    );
    _receiver?.onAckReceived = _sender!.handleAck;

    await _sender!.start();
    final ok = await _sender!.sendFile(File(picked.path), picked.name);
    if (!ok) {
      _log(
        'Hata: Bağlantı kesildi, dosya gönderilemedi. Lütfen tekrar deneyin.',
      );
    }

    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalBytes > 0
        ? (_doneBytes / _totalBytes).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).toInt();
    final displayLines = _logs.length <= 1
        ? [...UsageGuide.steps, '', ..._logs]
        : _logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UDP Dosya Transferi',
          style: TextStyle(fontSize: 18),
        ),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () => UsageGuide.show(context),
            child: const Text('Nasıl Kullanılır?'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AddressCard(roomCode: _myCode),
              const SizedBox(height: 12),
              TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                ),
                decoration: InputDecoration(
                  labelText: 'Karşı Cihazın 4 Haneli Kodu',
                  hintText: 'Örn: 4829',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  suffixIcon: TextButton(
                    onPressed: _pasteTarget,
                    child: const Text('Yapıştır'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _isSending ? null : _pickAndSendFile,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    _isSending ? 'Gönderiliyor...' : 'Dosya Seç & Gönder',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              if (_lastSavedFile != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () => PlatformHelper.shareFile(_lastSavedFile!),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      'Kaydet / Aç: ${_lastSavedFile!.split(Platform.pathSeparator).last}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '%$percent',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${PlatformHelper.formatBytes(_doneBytes)} / ${PlatformHelper.formatBytes(_totalBytes)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress, minHeight: 8),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView.builder(
                    itemCount: displayLines.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        displayLines[i],
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
