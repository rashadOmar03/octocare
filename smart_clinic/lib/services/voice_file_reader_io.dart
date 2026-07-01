import 'dart:io';

Future<List<int>> readRecordingBytes(String path) {
  return File(path).readAsBytes();
}
