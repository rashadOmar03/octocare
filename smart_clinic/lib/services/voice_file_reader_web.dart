import 'package:http/http.dart' as http;

Future<List<int>> readRecordingBytes(String path) async {
  final response = await http.get(Uri.parse(path));
  return response.bodyBytes;
}
