import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddressCard extends StatelessWidget {
  final String roomCode;

  const AddressCard({
    super.key,
    required this.roomCode,
  });

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bağlantı kodu kopyalandı: $text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Senin Bağlantı Kodun (Dosya alacaksan karşıya söyle)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  roomCode,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _copy(context, roomCode),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Kopyala'),
          ),
        ],
      ),
    );
  }
}

class UsageGuide {
  static const List<String> steps = [
    'NASIL KULLANILIR?',
    '1. Dosya Alacak Cihaz: Hiçbir şeye basmanıza gerek yok. Üstteki 4 haneli Bağlantı Kodunu göndericiye söyleyin.',
    '2. Dosya Gönderecek Cihaz: Karşı cihazın 4 haneli kodunu kutuya yazıp "Dosya Seç & Gönder" butonuna basın.',
    '3. Kaydetme: Aktarım %100 olduğunda çıkan "Kaydet / Aç" butonuyla dosyayı telefonunuza kaydedin.',
  ];

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Nasıl Dosya Gönderilir?',
          style: TextStyle(fontSize: 16),
        ),
        content: Text(
          steps.skip(1).join('\n\n'),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
