import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  static ApiService get instance => _instance;
  ApiService._internal();

  static Future<bool> Function()? onUnauthorized;

  String _token = '';
  String get baseUrl => ApiConfig.url;
  String get currentToken => _token;

  void setToken(String token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<dynamic> get(String endpoint, {bool authenticated = true, bool allowRetry = true}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = authenticated ? _headers : {'Content-Type': 'application/json', 'Accept': 'application/json'};

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 45));
    return _handleResponse(response, retry: allowRetry ? () => get(endpoint, authenticated: authenticated, allowRetry: false) : null);
  }

  Future<dynamic> post(String endpoint, dynamic data, {bool authenticated = true}) async {
    try {
      return await _post(endpoint, data, authenticated: authenticated);
    } on TimeoutException {
      throw ApiException('Connection timed out. Check your internet connection and try again.', 0);
    }
  }

  Future<dynamic> _post(String endpoint, dynamic data, {bool authenticated = true, bool allowRetry = true}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = authenticated ? _headers : {'Content-Type': 'application/json', 'Accept': 'application/json'};

    final response = await http
        .post(url, headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 45));
    return _handleResponse(response, retry: allowRetry ? () => _post(endpoint, data, authenticated: authenticated, allowRetry: false) : null);
  }

  Future<dynamic> put(String endpoint, dynamic data, {bool authenticated = true, bool allowRetry = true}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = authenticated ? _headers : {'Content-Type': 'application/json', 'Accept': 'application/json'};

    final response = await http
        .put(url, headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 45));
    return _handleResponse(response, retry: allowRetry ? () => put(endpoint, data, authenticated: authenticated, allowRetry: false) : null);
  }

  Future<dynamic> patch(String endpoint, dynamic data, {bool authenticated = true, bool allowRetry = true}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = authenticated ? _headers : {'Content-Type': 'application/json', 'Accept': 'application/json'};

    final response = await http
        .patch(url, headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 45));
    return _handleResponse(response, retry: allowRetry ? () => patch(endpoint, data, authenticated: authenticated, allowRetry: false) : null);
  }

  Future<dynamic> delete(String endpoint, {bool authenticated = true, bool allowRetry = true}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = authenticated ? _headers : {'Content-Type': 'application/json', 'Accept': 'application/json'};

    final response = await http.delete(url, headers: headers).timeout(const Duration(seconds: 45));
    if (response.statusCode == 204) return {'success': true};
    return _handleResponse(response, retry: allowRetry ? () => delete(endpoint, authenticated: authenticated, allowRetry: false) : null);
  }

  Future<dynamic> postMultipart(
    String endpoint, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
    Duration timeout = const Duration(seconds: 120),
    bool allowRetry = true,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final request = http.MultipartRequest('POST', url);
    if (_token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(http.MultipartFile.fromBytes(fileField, bytes, filename: filename));
    if (fields != null) {
      request.fields.addAll(fields);
    }
    final streamed = await request.send().timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response, retry: allowRetry ? () => postMultipart(endpoint, fileField: fileField, bytes: bytes, filename: filename, fields: fields, timeout: timeout, allowRetry: false) : null);
  }

  dynamic _handleResponse(http.Response response, {Future<dynamic> Function()? retry}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return json.decode(utf8.decode(response.bodyBytes));
    } else if (response.statusCode == 401) {
      String message = 'Invalid email or password.';
      try {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      if (retry != null && onUnauthorized != null) {
        return onUnauthorized!().then((refreshed) {
          if (refreshed) return retry();
          throw ApiException(message, 401);
        });
      }
      throw ApiException(message, 401);
    } else if (response.statusCode == 403) {
      String message = 'Access denied.';
      try {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw ApiException(message, 403);
    } else if (response.statusCode == 404) {
      String message = 'Resource not found.';
      try {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw ApiException(message, 404);
    } else if (response.statusCode == 422 || response.statusCode == 400) {
      final body = json.decode(utf8.decode(response.bodyBytes));
      String message = 'Validation error';
      if (body is Map) {
        if (body.containsKey('detail')) {
          message = body['detail'].toString();
        } else {
          final errors = <String>[];
          body.forEach((key, value) {
            if (value is List) {
              errors.add('$key: ${value.join(', ')}');
            } else {
              errors.add('$key: $value');
            }
          });
          message = errors.join('\n');
        }
      }
      throw ApiException(message, response.statusCode);
    } else {
      String message = 'Server error (${response.statusCode})';
      try {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw ApiException(message, response.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
