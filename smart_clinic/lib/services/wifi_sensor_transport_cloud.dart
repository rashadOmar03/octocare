import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'wifi_sensor_transport.dart';

/// Cloud live sensors: WebSocket when available + fast /live/recent polling.
class CloudPollWifiSensorTransport implements WifiSensorTransport {
  Timer? _timer;
  bool _connected = false;
  int _sinceSeq = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  static String pollUrlFromWs(String? webSocketUrl) {
    if (webSocketUrl == null || webSocketUrl.isEmpty) {
      throw Exception('Live sensor poll URL is not configured.');
    }
    return webSocketUrl
        .replaceFirst('wss://', 'https://')
        .replaceFirst('ws://', 'http://')
        .replaceFirst('/sensors/live/ws', '/sensors/live/latest');
  }

  static String recentUrlFromWs(String? webSocketUrl) {
    return pollUrlFromWs(webSocketUrl).replaceFirst('/latest', '/recent');
  }

  @override
  bool get isConnected => _connected;

  void _emitLine(String line, void Function(List<int> data) onBytes) {
    if (line.isEmpty || !_connected) return;
    onBytes(utf8.encode('$line\n'));
  }

  void _startWebSocket({
    required String? webSocketUrl,
    required void Function(List<int> data) onBytes,
  }) {
    final url = webSocketUrl;
    if (url == null || url.isEmpty) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _wsSub = _channel!.stream.listen(
        (event) {
          if (!_connected) return;
          final text = event is String ? event : utf8.decode(event as List<int>);
          _emitLine(text.trim(), onBytes);
        },
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? webSocketUrl,
    required void Function(List<int> data) onBytes,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) async {
    final recentUrl = recentUrlFromWs(webSocketUrl);
    final latestUrl = pollUrlFromWs(webSocketUrl);
    _connected = true;
    _sinceSeq = 0;

    _startWebSocket(webSocketUrl: webSocketUrl, onBytes: onBytes);

    Future<void> pollRecent() async {
      if (!_connected) return;
      try {
        final uri = Uri.parse(recentUrl).replace(queryParameters: {
          'since': '$_sinceSeq',
          'limit': '200',
        });
        final resp = await http.get(uri).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) return;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final lines = data['lines'];
        if (lines is List && lines.isNotEmpty) {
          for (final raw in lines) {
            _emitLine(raw.toString(), onBytes);
          }
          final seq = data['seq'];
          if (seq is int && seq > _sinceSeq) {
            _sinceSeq = seq;
          }
        }
      } catch (_) {
        if (!_connected) return;
        try {
          final resp = await http.get(Uri.parse(latestUrl)).timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) return;
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final seq = data['seq'];
          if (seq is int && seq > _sinceSeq) _sinceSeq = seq;
          _emitLine(data['line']?.toString() ?? '', onBytes);
        } catch (_) {}
      }
    }

    unawaited(pollRecent());
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => pollRecent());
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _sinceSeq = 0;
  }
}

WifiSensorTransport createCloudWifiSensorTransport() => CloudPollWifiSensorTransport();
