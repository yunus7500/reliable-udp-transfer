// Message type enums

enum PacketType {
  handshakeInit(0x01), // Handshake mektubu
  handshakeAck(0x02),

  data(0x03),
  ack(0x04),
  fileEnd(0x05),
  error(0x06);

  final int value;
  const PacketType(this.value);

  static PacketType fromValue(int value) {
    return PacketType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw ArgumentError('geçersiz paket tipi: $value'),
    );
  }
}
