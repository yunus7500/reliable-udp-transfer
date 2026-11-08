import 'dart:io';
import 'package:flutter/services.dart';

class PickedFileInfo {
  final String path;
  final String name;
  final int size;

  const PickedFileInfo({
    required this.path,
    required this.name,
    required this.size,
  });
}

class PlatformHelper {
  static const _channel = MethodChannel('udp_transfer/platform');

  // yerel ağdaki tek bir ipv4 adresini (öncelikle wifi/lan) döndürür
  static Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('172.')) {
            return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  // işletim sisteminin kendi dosya seçicisini açar
  static Future<PickedFileInfo?> pickFile() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickFile');
    if (result == null) return null;

    final path = result['path'] as String?;
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    final size = await file.length();
    final name =
        (result['name'] as String?) ?? path.split(Platform.pathSeparator).last;

    return PickedFileInfo(path: path, name: name, size: size);
  }

  // alınan dosyaların kaydedileceği klasör
  static Future<String> getSaveDir() async {
    try {
      final dir = await _channel.invokeMethod<String>('getSaveDir');
      if (dir != null && dir.isNotEmpty) {
        // klasöre yazma izni var mı kontrol et (android scoped storage için)
        final testFile = File('$dir${Platform.pathSeparator}.write_test');
        await testFile.writeAsBytes([1]);
        await testFile.delete();
        return dir;
      }
    } catch (_) {}
    return Directory.systemTemp.path;
  }

  // alınan dosyayı galeriye/indirilenlere kaydetmek veya açmak için
  static Future<void> shareFile(String path) async {
    try {
      await _channel.invokeMethod('shareFile', {'path': path});
    } catch (_) {}
  }

  // transfer sırasında arkaplanda uyku modunu engeller
  static Future<void> setBackgroundActive(bool active) async {
    try {
      await _channel.invokeMethod('setBackgroundActive', {'active': active});
    } catch (_) {}
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
