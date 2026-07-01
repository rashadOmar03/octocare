import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'sensor_line_parser.dart';
import 'sensor_reading.dart';
import 'wifi_sensor_transport.dart';
import 'wifi_sensor_transport_stub.dart'
    if (dart.library.io) 'wifi_sensor_transport_io.dart'
    if (dart.library.html) 'wifi_sensor_transport_web.dart';

class WifiSensorService {
  WifiSensorService._();
  static final WifiSensorService instance = WifiSensorService._();

  static const String prefHostKey = 'esp32_sensor_host';
  static const String prefPortKey = 'esp32_sensor_port';
  static const int defaultPort = 5000;

  final _controller = StreamController<SensorReading>.broadcast();
  final _rawController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  WifiSensorTransport? _transport;
  String _buffer = '';
  int _bytesReceived = 0;
  String? _lastRawLine;
  String? _lastEmittedLine;
  String? _connectedLabel;
  final _utf8Decoder = Utf8Decoder(allowMalformed: true);

  Stream<SensorReading> get readings => _controller.stream;
  Stream<String> get rawLines => _rawController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  int get bytesReceived => _bytesReceived;
  String? get lastRawLine => _lastRawLine;
  bool get isConnected => _transport?.isConnected ?? false;
  String? get connectionLabel => _connectedLabel;

  Future<String?> loadSavedHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefHostKey);
  }

  Future<int> loadSavedPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(prefPortKey) ?? defaultPort;
  }

  Future<void> saveConnectionSettings({required String host, required int port}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefHostKey, host.trim());
    await prefs.setInt(prefPortKey, port);
  }

  static String liveWebSocketUrl() {
    final base = Uri.parse(ApiConfig.url);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final portPart = base.hasPort && base.port != 80 && base.port != 443 ? ':${base.port}' : '';
    return '$scheme://${base.host}$portPart/sensors/live/ws';
  }

  Future<void> connect({required String host, int port = defaultPort}) async {
    await disconnect();
    final trimmedHost = host.trim();
    if (!kIsWeb && trimmedHost.isEmpty) {
      throw Exception('Enter the ESP32 IP address from its Serial Monitor.');
    }

    await saveConnectionSettings(host: trimmedHost, port: port);

    _transport = createWifiSensorTransport();
    _buffer = '';
    _bytesReceived = 0;
    _lastRawLine = null;
    _lastEmittedLine = null;

    if (kIsWeb) {
      _connectedLabel = 'WebSocket (${Uri.parse(ApiConfig.url).host})';
      await _transport!.connect(
        host: trimmedHost,
        port: port,
        webSocketUrl: liveWebSocketUrl(),
        onBytes: _onBytes,
        onError: _handleConnectionLost,
        onDone: _handleConnectionLost,
      );
    } else {
      _connectedLabel = '$trimmedHost:$port';
      await _transport!.connect(
        host: trimmedHost,
        port: port,
        onBytes: _onBytes,
        onError: _handleConnectionLost,
        onDone: _handleConnectionLost,
      );
    }

    if (!_connectionController.isClosed) {
      _connectionController.add(true);
    }
  }

  void _onBytes(List<int> data) {
    _bytesReceived += data.length;
    _buffer += _utf8Decoder.convert(data);
    _buffer = _buffer.replaceAll('\r', '');

    while (_buffer.contains('\n')) {
      final newline = _buffer.indexOf('\n');
      final line = _buffer.substring(0, newline).trim();
      _buffer = _buffer.substring(newline + 1);
      if (line.isEmpty) continue;

      _lastRawLine = line;
      if (!_rawController.isClosed) _rawController.add(line);

      if (line == _lastEmittedLine) continue;
      _lastEmittedLine = line;

      final parsed = SensorLineParser.parseLine(line);
      if (parsed != null && !_controller.isClosed) {
        _controller.add(parsed);
      }
    }
  }

  Future<void> _handleConnectionLost([Object? _]) async {
    final wasConnected = _transport != null;
    await _transport?.dispose();
    _transport = null;
    _connectedLabel = null;
    _buffer = '';
    if (wasConnected && !_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  Future<void> disconnect() async {
    await _handleConnectionLost();
    _bytesReceived = 0;
    _lastRawLine = null;
    _lastEmittedLine = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
    _rawController.close();
    _connectionController.close();
  }
}
