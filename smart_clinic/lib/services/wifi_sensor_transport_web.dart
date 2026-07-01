import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'wifi_sensor_transport.dart';

class _WebSocketWifiSensorTransport implements WifiSensorTransport {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  @override
  bool get isConnected => _channel != null;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? webSocketUrl,
    required void Function(List<int> data) onBytes,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) async {
    final url = webSocketUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Live sensor WebSocket URL is not configured.');
    }

    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;
    _subscription = _channel!.stream.listen(
      (event) {
        final text = event is String ? event : utf8.decode(event as List<int>);
        onBytes(utf8.encode('$text\n'));
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: true,
    );
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}

WifiSensorTransport createWifiSensorTransport() => _WebSocketWifiSensorTransport();

WifiSensorTransport createCloudWifiSensorTransport() => createWifiSensorTransport();
