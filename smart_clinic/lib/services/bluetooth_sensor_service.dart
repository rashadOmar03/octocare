import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sensor_line_parser.dart';
import 'sensor_reading.dart';

export 'sensor_reading.dart';

class BluetoothSensorService {
  BluetoothSensorService._();
  static final BluetoothSensorService instance = BluetoothSensorService._();

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<SensorReading>.broadcast();
  final _rawController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  String _buffer = '';
  int _bytesReceived = 0;
  String? _lastRawLine;

  Stream<SensorReading> get readings => _controller.stream;
  Stream<String> get rawLines => _rawController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  int get bytesReceived => _bytesReceived;
  String? get lastRawLine => _lastRawLine;
  bool get isConnected => _connection?.isConnected ?? false;
  String? _connectedName;
  String? get deviceName => _connectedName;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> _ensurePermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<List<BluetoothDevice>> getBondedDevices() async {
    if (!isSupported) return [];
    await _ensurePermissions();
    final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!enabled) {
      await FlutterBluetoothSerial.instance.requestEnable();
    }
    return FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Future<void> connect(BluetoothDevice device) async {
    if (!isSupported) {
      throw Exception('Bluetooth sensors are only supported on Android.');
    }
    await disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _ensurePermissions();
    _connection = await BluetoothConnection.toAddress(device.address);
    _connectedName = device.name ?? device.address;
    _buffer = '';
    _bytesReceived = 0;
    _lastRawLine = null;
    if (_connection!.input == null) {
      await _connection!.close();
      _connection = null;
      throw Exception(
        'Connected to HC-05 but no data channel. Re-pair HC-05 and try again.',
      );
    }
    _subscription = _connection!.input!.listen(
      _onData,
      onError: (e) {
        _controller.addError(e);
        _handleConnectionLost();
      },
      onDone: _handleConnectionLost,
    );
    if (!_connectionController.isClosed) {
      _connectionController.add(true);
    }
  }

  Future<void> _handleConnectionLost() async {
    final wasConnected = _connection != null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    _connectedName = null;
    _buffer = '';
    if (wasConnected && !_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  void _onData(Uint8List data) {
    _bytesReceived += data.length;
    _buffer += utf8.decode(data, allowMalformed: true);
    _buffer = _buffer.replaceAll('\r', '');

    while (_buffer.contains('\n')) {
      final newline = _buffer.indexOf('\n');
      final line = _buffer.substring(0, newline).trim();
      _buffer = _buffer.substring(newline + 1);
      if (line.isEmpty) continue;

      _lastRawLine = line;
      if (!_rawController.isClosed) _rawController.add(line);

      final parsed = SensorLineParser.parseLine(line);
      if (parsed != null) _controller.add(parsed);
    }
  }

  static SensorReading? parseLine(String line) => SensorLineParser.parseLine(line);

  Future<void> disconnect() async {
    await _handleConnectionLost();
    _bytesReceived = 0;
    _lastRawLine = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
    _rawController.close();
    _connectionController.close();
  }
}
