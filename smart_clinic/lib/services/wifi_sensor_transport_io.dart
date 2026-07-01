import 'dart:async';
import 'dart:io';

import 'wifi_sensor_transport.dart';

class _TcpWifiSensorTransport implements WifiSensorTransport {
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? webSocketUrl,
    required void Function(List<int> data) onBytes,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) async {
    _socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 12),
    );
    _socket!.setOption(SocketOption.tcpNoDelay, true);
    _subscription = _socket!.listen(
      onBytes,
      onError: onError,
      onDone: onDone,
      cancelOnError: true,
    );
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

WifiSensorTransport createWifiSensorTransport() => _TcpWifiSensorTransport();
