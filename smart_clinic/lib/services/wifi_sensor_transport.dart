abstract class WifiSensorTransport {
  bool get isConnected;

  Future<void> connect({
    required String host,
    required int port,
    String? webSocketUrl,
    required void Function(List<int> data) onBytes,
    required void Function(Object error) onError,
    required void Function() onDone,
  });

  Future<void> dispose();
}
