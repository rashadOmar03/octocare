import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart';

Future<List<int>> readRecordingBytes(String path) async {
  if (path.startsWith('blob:')) {
    try {
      final response = await window.fetch(path.toJS).toDart;
      if (!response.ok) return [];
      final buffer = await response.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } catch (_) {
      return [];
    }
  }
  try {
    final response = await http.get(Uri.parse(path));
    return response.bodyBytes;
  } catch (_) {
    return [];
  }
}
