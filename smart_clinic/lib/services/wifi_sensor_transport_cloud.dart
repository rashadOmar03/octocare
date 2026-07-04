import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'wifi_sensor_transport.dart';

/// Polls /sensors/live/latest — reliable on Railway where WebSocket may not upgrade.
class CloudPollWifiSensorTransport implements WifiSensorTransport {
  Timer? _timer;
  bool _connected = false;
  String? _lastLine;

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
    _lastLine = null;

    Future<void> pollOnce({required bool strict}) async {
      if (!_connected) return;
      try {
        final resp = await http.get(Uri.parse(pollUrl)).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) {
          if (strict) {
            throw Exception('Sensor poll failed: HTTP ${resp.statusCode}');
          }
          return;
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final line = data['line']?.toString() ?? '';
        if (line.isEmpty || line == _lastLine) return;
        _lastLine = line;
        onBytes(utf8.encode('$line\n'));
      } catch (e) {
        if (strict) rethrow;
      }
    }

    await pollOnce(strict: true);
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) => pollOnce(strict: false));
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
    _lastLine = null;
  }
}

WifiSensorTransport createCloudWifiSensorTransport() => CloudPollWifiSensorTransport();
