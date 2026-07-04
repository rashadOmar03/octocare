import '../config/api_config.dart';

class PhotoUrlUtils {
  static String ensureUploadFilename(String name, String? extension) {
    final ext = (extension ?? 'jpg').toLowerCase().replaceAll('.', '');
    final normalizedExt = '.$ext';
    if (RegExp(r'\.(jpe?g|png|gif|webp)$', caseSensitive: false).hasMatch(name)) {
      return name;
    }
    return '$name$normalizedExt';
  }

  static String? normalizePath(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static String fullUrl(String path, {int? cacheBust}) {
    final base = ApiConfig.url;
    final normalized = path.startsWith('http') ? path : '$base$path';
    if (cacheBust == null) return normalized;
    final separator = normalized.contains('?') ? '&' : '?';
    return '$normalized${separator}t=$cacheBust';
  }
}
