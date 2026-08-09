//  Resend timer if no ACK is received.
import 'dart:async';
import 'package:flutter/material.dart';

class RetransmitTimer {
  final Duration timeout;
  final int maxRetries;
  final Function() onTimeout; // süre dolduğunda çalışır.
  final Function() onFail; // maksimum denemeye ulaşıldığında çalışır.

  Timer? _timer;
  int _retryCount = 0;

  RetransmitTimer({
    required this.timeout,
    required this.maxRetries,
    required this.onTimeout,
    required this.onFail,
  });

  void start() {
    _retryCount = 0;
    _startInternal();
  }

  void _startInternal() {
    _timer?.cancel();

    _timer = Timer(timeout, () {
      _retryCount++;

      if (_retryCount > maxRetries) {
        debugPrint('maksimum deneme sayısına ulaşıldı,pes ediliyor');
        onFail();
      } else {
        debugPrint(
          'zaman aşımı. paket kaybolmuş olabilir,tekrar fırlatılıyor.deneme:$_retryCount',
        );
        onTimeout();
        _startInternal(); // tekrar fırlatıldığı için sayacı yeniden başlat
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
