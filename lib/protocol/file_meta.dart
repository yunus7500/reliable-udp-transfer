import 'dart:convert';
import 'dart:typed_data';

// ilk pakette (handshake) gidecek dosya adı ve boyutu
class FileMeta {
  final String fileName;
  final int fileSize;

  const FileMeta({required this.fileName, required this.fileSize});

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode('$fileName\n$fileSize'));
  }

  static FileMeta fromBytes(Uint8List bytes) {
    final text = utf8.decode(bytes);
    final parts = text.split('\n');
    if (parts.length < 2) {
      throw const FormatException('bozuk dosya bilgisi');
    }
    return FileMeta(
      fileName: parts.first,
      fileSize: int.parse(parts.last),
    );
  }
}

