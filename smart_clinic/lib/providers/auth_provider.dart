import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../config/routes.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  String? _token;
  String? _refreshToken;
  bool _isLoading = false;
  bool _mustChangePassword = false;
  bool _profileComplete = true;
  Completer<bool>? _refreshCompleter;

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _currentUser != null;
  bool get isLoading => _isLoading;
  bool get mustChangePassword => _mustChangePassword;
  bool get profileComplete => _profileComplete;
  String get userRole => _currentUser?.role ?? '';

  Future<void> _persistAuthFlags(SharedPreferences prefs) async {
    await prefs.setBool('must_change_password', _mustChangePassword);
    await prefs.setBool('profile_complete', _profileComplete);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _refreshToken = prefs.getString('refresh_token');
    _mustChangePassword = prefs.getBool('must_change_password') ?? false;
    _profileComplete = prefs.getBool('profile_complete') ?? true;
    final userData = prefs.getString('user_data');
    if (_token != null && userData != null) {
      try {
        _currentUser = User.fromJson(json.decode(userData));
        ApiService.instance.setToken(_token!);
        ApiService.onUnauthorized = refreshTokenMethod;
        _refreshStoredUserPhoto();
      } catch (_) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<void> _refreshStoredUserPhoto() async {
    if (_currentUser == null) return;
    try {
      final response = await ApiService.instance.get('/patients/profile');
      final url = response['photo_url']?.toString();
      if (url != null && url.isNotEmpty) {
        await updateProfilePhoto(url);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> login(String emailOrPhone, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.instance.post('/auth/login', {
        'email_or_phone': emailOrPhone.contains('@') ? normalizeEmail(emailOrPhone) : emailOrPhone.trim(),
        'password': password,
      }, authenticated: false);

      if (response['access_token'] != null) {
        _token = response['access_token'];
        _refreshToken = response['refresh_token'];
        _mustChangePassword = response['must_change_password'] ?? false;
        _profileComplete = response['profile_complete'] ?? false;

        ApiService.instance.setToken(_token!);
        ApiService.onUnauthorized = refreshTokenMethod;

        _currentUser = User(
          id: response['user_id']?.toString(),
          role: response['role'],
          email: response['email'] ?? emailOrPhone,
          firstName: response['first_name'],
          lastName: response['last_name'],
          profilePhoto: response['photo_url']?.toString(),
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        if (_refreshToken != null) {
          await prefs.setString('refresh_token', _refreshToken!);
        }
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
        await _persistAuthFlags(prefs);

        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'role': _currentUser?.role,
          'must_change_password': _mustChangePassword,
          'profile_complete': _profileComplete,
        };
      }

      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': response['detail'] ?? 'Login failed'};
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      final msg = e.toString();
      if (msg.toLowerCase().contains('verify your email')) {
        return {
          'success': false,
          'needs_verification': true,
          'email': emailOrPhone.contains('@') ? emailOrPhone.trim() : '',
          'message': msg,
        };
      }
      return {'success': false, 'message': msg};
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.instance.post('/auth/register', data, authenticated: false);

      if (response['requires_verification'] == true) {
        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'requires_verification': true,
          'email': normalizeEmail(response['email']?.toString() ?? data['email']?.toString() ?? ''),
          'message': response['message'],
        };
      }

      if (response['access_token'] != null) {
        _token = response['access_token'];
        _refreshToken = response['refresh_token'];
        ApiService.instance.setToken(_token!);
        ApiService.onUnauthorized = refreshTokenMethod;

        _currentUser = User(
          id: response['user_id']?.toString(),
          role: response['role'] ?? 'patient',
          email: data['email'] ?? '',
          phone: data['phone'],
          firstName: data['first_name'],
          lastName: data['last_name'],
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        if (_refreshToken != null) {
          await prefs.setString('refresh_token', _refreshToken!);
        }
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));

        _isLoading = false;
        notifyListeners();
        return {'success': true};
      }

      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': response['detail'] ?? 'Registration failed'};
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String otp) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.instance.post('/auth/verify-email', {
        'email': normalizeEmail(email),
        'otp': otp.trim(),
      }, authenticated: false);
      return await _handleAuthResponse(response, fallbackEmail: email);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> resendOtp(String email, String purpose) async {
    try {
      final response = await ApiService.instance.post('/auth/resend-otp', {
        'email': normalizeEmail(email),
        'purpose': purpose,
      }, authenticated: false);
      return {'success': true, 'message': response['message'] ?? 'Code sent'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await ApiService.instance.post('/auth/forgot-password', {
        'email': normalizeEmail(email),
      }, authenticated: false);
      return {'success': true, 'message': response['message'] ?? 'Code sent if email exists'};
    } catch (e) {
      final msg = e.toString();
      if (msg.toLowerCase().contains('not registered')) {
        return {'success': false, 'not_registered': true, 'message': msg};
      }
      return {'success': false, 'message': msg};
    }
  }

  Future<Map<String, dynamic>> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await ApiService.instance.post('/auth/reset-password', {
        'email': normalizeEmail(email),
        'otp': otp.trim(),
        'new_password': newPassword,
      }, authenticated: false);
      return {'success': true, 'message': response['message'] ?? 'Password reset'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleAuthResponse(Map<String, dynamic> response, {String? fallbackEmail}) async {
    if (response['access_token'] != null) {
      _token = response['access_token'];
      _refreshToken = response['refresh_token'];
      _mustChangePassword = response['must_change_password'] ?? false;
      _profileComplete = response['profile_complete'] ?? false;
      ApiService.instance.setToken(_token!);
      ApiService.onUnauthorized = refreshTokenMethod;

      _currentUser = User(
        id: response['user_id']?.toString(),
        role: response['role'],
        email: response['email'] ?? fallbackEmail,
        firstName: response['first_name'],
        lastName: response['last_name'],
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      if (_refreshToken != null) {
        await prefs.setString('refresh_token', _refreshToken!);
      }
      await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
      await _persistAuthFlags(prefs);

      _isLoading = false;
      notifyListeners();
      return {
        'success': true,
        'role': _currentUser?.role,
        'must_change_password': _mustChangePassword,
        'profile_complete': _profileComplete,
      };
    }

    _isLoading = false;
    notifyListeners();
    return {'success': false, 'message': response['detail'] ?? 'Authentication failed'};
  }

  Future<void> logout() async {
    ApiService.onUnauthorized = null;
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    _mustChangePassword = false;
    ApiService.instance.setToken('');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
    await prefs.remove('must_change_password');
    await prefs.remove('profile_complete');

    notifyListeners();
  }

  Future<bool> refreshTokenMethod() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final result = await _doRefresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<bool> _doRefresh() async {
    if (_refreshToken == null) {
      await logout();
      return false;
    }
    try {
      final response = await ApiService.instance.post('/auth/refresh', {
        'refresh_token': _refreshToken,
      }, authenticated: false);

      if (response['access_token'] != null) {
        _token = response['access_token'];
        ApiService.instance.setToken(_token!);
        ApiService.onUnauthorized = refreshTokenMethod;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        return true;
      }
      await logout();
      return false;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<Map<String, dynamic>> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await ApiService.instance.post('/auth/change-password', {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      _mustChangePassword = false;
      final prefs = await SharedPreferences.getInstance();
      await _persistAuthFlags(prefs);
      notifyListeners();
      return {'success': true, 'message': response['message'] ?? 'Password changed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<void> updateProfilePhoto(String photoUrl) async {
    if (_currentUser == null) return;
    _currentUser = User(
      id: _currentUser!.id,
      role: _currentUser!.role,
      email: _currentUser!.email,
      phone: _currentUser!.phone,
      firstName: _currentUser!.firstName,
      middleName: _currentUser!.middleName,
      lastName: _currentUser!.lastName,
      isActive: _currentUser!.isActive,
      profilePhoto: photoUrl,
      profile: _currentUser!.profile,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
    notifyListeners();
  }

  Future<void> completeProfile(Map<String, dynamic> data) async {
    try {
      final response = await ApiService.instance.post('/patients/complete-profile', data);
      if (response != null && _currentUser != null) {
        _currentUser = User(
          id: _currentUser!.id,
          role: _currentUser!.role,
          email: _currentUser!.email,
          phone: response['phone'] ?? _currentUser!.phone,
          firstName: response['first_name'] ?? _currentUser!.firstName,
          middleName: response['middle_name'] ?? _currentUser!.middleName,
          lastName: response['last_name'] ?? _currentUser!.lastName,
          isActive: _currentUser!.isActive,
          profilePhoto: response['photo_url'] ?? _currentUser!.profilePhoto,
          profile: Profile.fromJson(Map<String, dynamic>.from(response)),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
        _profileComplete = response['is_complete'] == true;
        notifyListeners();
      }
    } catch (_) {
      rethrow;
    }
  }

  Future<void> refreshProfileComplete() async {
    if (_currentUser?.role != 'patient') return;
    try {
      final response = await ApiService.instance.get('/patients/profile');
      _profileComplete = response['is_complete'] == true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await ApiService.instance.put('/patients/profile', data);
      if (response != null && _currentUser != null) {
        _currentUser = User(
          id: _currentUser!.id,
          role: _currentUser!.role,
          email: response['email'] ?? _currentUser!.email,
          phone: response['phone'] ?? _currentUser!.phone,
          firstName: response['first_name'] ?? data['first_name'] ?? _currentUser!.firstName,
          middleName: response['middle_name'] ?? data['middle_name'] ?? _currentUser!.middleName,
          lastName: response['last_name'] ?? data['last_name'] ?? _currentUser!.lastName,
          isActive: _currentUser!.isActive,
          profilePhoto: response['photo_url'] ?? response['profile_photo'] ?? _currentUser!.profilePhoto,
          profile: response['profile'] != null ? Profile.fromJson(response['profile']) : _currentUser!.profile,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
        notifyListeners();
      }
    } catch (_) {
      rethrow;
    }
  }

  String getPostAuthRoute() {
    if (_mustChangePassword) return AppRoutes.changePassword;
    if (_currentUser?.role == 'patient' && !_profileComplete) {
      return AppRoutes.profileComplete;
    }
    return getHomeRoute();
  }

  String getHomeRoute() {
    switch (_currentUser?.role) {
      case 'patient':
        return '/patient/home';
      case 'doctor':
        return '/doctor/home';
      case 'receptionist':
        return '/receptionist/home';
      case 'admin':
        return '/admin/home';
      default:
        return '/login';
    }
  }
}
