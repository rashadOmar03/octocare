import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';
import 'report_download_web.dart' if (dart.library.io) 'report_download_io.dart' as saver;

class ReportDownloadService {
  static const formats = ['pdf', 'csv', 'xlsx'];

  static String _acceptHeader(String format) {
    switch (format) {
      case 'csv':
        return 'text/csv';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/pdf';
    }
  }

  static String _defaultFilename(String base, String format) {
    final ext = format == 'pdf' ? 'pdf' : format;
    final stem = base.endsWith('.pdf') ? base.substring(0, base.length - 4) : base.replaceAll(RegExp(r'\.[^.]+$'), '');
    return '$stem.$ext';
  }

  static Future<void> download(
    String path, {
    String filename = 'clinic_report.pdf',
    Map<String, String>? queryParams,
    String format = 'pdf',
  }) async {
    final params = Map<String, String>.from(queryParams ?? {});
    params['format'] = format;

    final base = Uri.parse('${ApiConfig.url}$path');
    final uri = base.replace(queryParameters: params);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${ApiService.instance.currentToken}',
        'Accept': _acceptHeader(format),
      },
    ).timeout(const Duration(seconds: 90));

    final status = response.statusCode;
    if (status != 200) {
      String detail = 'Report download failed ($status)';
      try {
        final body = utf8.decode(response.bodyBytes);
        if (body.isNotEmpty && !body.startsWith('%PDF')) {
          detail = body.length > 200 ? body.substring(0, 200) : body;
        }
      } catch (_) {}
      throw Exception(detail);
    }

    final name = _filenameFromHeaders(response.headers) ?? _defaultFilename(filename, format);
    await saver.saveReportBytes(response.bodyBytes, name);
  }

  static String? _filenameFromHeaders(Map<String, String> headers) {
    final disposition = headers['content-disposition'] ?? headers['Content-Disposition'];
    if (disposition == null) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1);
  }
}
