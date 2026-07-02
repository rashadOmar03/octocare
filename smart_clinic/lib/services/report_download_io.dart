import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveReportBytes(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  final xFile = XFile(file.path, mimeType: _mimeTypeForFilename(safeName));
  await Share.shareXFiles([xFile], subject: safeName);
}

String? _mimeTypeForFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.csv')) return 'text/csv';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  return null;
}
