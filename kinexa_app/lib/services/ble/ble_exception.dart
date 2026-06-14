class BleException implements Exception {
  BleException(this.message);

  final String message;

  @override
  String toString() => 'BleException: $message';
}
