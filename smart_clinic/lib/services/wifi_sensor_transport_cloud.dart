import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'wifi_sensor_transport.dart';

/// Polls /sensors/live/latest — reliable on Railway where WebSocket may not upgrade.
class CloudPollWifiSensorTransport implements WifiSensorTransport {
  Timer? _timer;
  bool _connected = false;

  static String pollUrlFromWs(String? webSocketUrl) {
    if (webSocketUrl == null || webSocketUrl.isEmpty) {
      throw Exception('Live sensor poll URL is not configured.');
    }
    return webSocketUrl
        .replaceFirst('wss://', 'https://')
        .replaceFirst('ws://', 'http://')
        .replaceFirst('/sensors/live/ws', '/sensors/live/latest');
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? webSocketUrl,
    required void Function(List<int> data) onBytes,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) async {
    final pollUrl = pollUrlFromWs(webSocketUrl);
    _connected = true;

    Future<void> pollOnce() async {
      if (!_connected) return;
      try {
        final resp = await http.get(Uri.parse(pollUrl)).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) return;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final line = data['line']?.toString() ?? '';
        if (line.isEmpty) return;
        onBytes(utf8.encode('$line\n'));
      } catch (_) {
        // Ignore transient poll errors — connection stays open.
      }
    }

    // Do not block connect on the first poll (avoids TimeoutException on cold start).
    unawaited(pollOnce());
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => pollOnce());
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
  }
}

WifiSensorTransport createCloudWifiSensorTransport() => CloudPollWifiSensorTransport();
