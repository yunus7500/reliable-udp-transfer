// Constants (MTU, timeout period, etc.)
class ProtocolConstants {
  static const int maxPayloadSize = 1024;
  static const int headerSize = 13;
  static const int maxPacketSize = headerSize + maxPayloadSize;
  static const Duration retransmissionTimeout = Duration(milliseconds: 500);
  static const int maxRetries = 5;
}
