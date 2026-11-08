class ProtocolConstants {
  // 1500 mtu sınırına takılmamak için 1400 byte güvenli sınır
  static const int maxPayloadSize = 1400;
  static const int headerSize = 13;
  static const int maxPacketSize = headerSize + maxPayloadSize;
  static const int windowSize = 64;
  static const Duration retransmissionTimeout = Duration(milliseconds: 300);
  static const int maxRetries = 10;
}
