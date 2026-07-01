import 'package:flutter/foundation.dart';
import 'api_config_web.dart' if (dart.library.io) 'api_config_stub.dart' as platform;

class ApiConfig {
  // ─── CLOUD BACKEND URL (set this after Railway deploy) ───────────────
  // Change this to your Railway URL, e.g. 'https://smart-clinic-xxxx.up.railway.app'
  static const String _cloudUrl = 'https://octocare-production.up.railway.app';

  // Set to true once you deploy to Railway
  static const bool useCloud = true;
  // ─────────────────────────────────────────────────────────────────────

  /// Android emulator → backend on your PC
  static const String _emulatorUrl = 'http://10.0.2.2:8000';

  /// Real phone on same Wi-Fi → your PC's local IP
  static const String _physicalPhoneUrl = 'http://10.53.1.239:8000';

  /// Set true when using Android Emulator, false for a real phone
  static const bool useAndroidEmulator = false;

  static const String _localWebUrl = 'http://localhost:8000';

  static String get url {
    if (useCloud) return _cloudUrl;

    if (kIsWeb) {
      final origin = platform.getOrigin();
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return _localWebUrl;
      }
      return origin;
    }
    return useAndroidEmulator ? _emulatorUrl : _physicalPhoneUrl;
  }
}