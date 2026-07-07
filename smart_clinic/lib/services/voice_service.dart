import 'dart:convert';

import 'package:flutter/services.dart';

import 'api_service.dart';
import 'voice_platform.dart';
import '../l10n/localization.dart';

final _arabicScript = RegExp(r'[\u0600-\u06FF]');
final _latinLetters = RegExp(r'[A-Za-z]');

const _englishGarbagePhrases = {
  'paternity or pregnant',
  'paternity',
  'pregnant',
  'thank you for watching',
  'thanks for watching',
  'like and subscribe',
  'subtitles by the amara.org community',
};

bool _looksLikeArabicUiGarbageEnglish(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return true;
  final lower = trimmed.toLowerCase();
  if (_englishGarbagePhrases.contains(lower)) return true;
  for (final phrase in _englishGarbagePhrases) {
    if (lower.contains(phrase) && lower.length < 80) return true;
  }
  if (_arabicScript.hasMatch(trimmed)) return false;
  final latinCount = _latinLetters.allMatches(trimmed).length;
  final letterCount = trimmed.replaceAll(RegExp(r'[^A-Za-z\u0600-\u06FF]'), '').length;
  if (letterCount == 0) return true;
  return latinCount / letterCount > 0.85;
}

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final VoicePlatform _platform = VoicePlatform();
  int? _speakingMessageIndex;
  DateTime? _recordingStartedAt;

  bool get isRecording => _platform.isRecording;
  int? get speakingMessageIndex => _speakingMessageIndex;

  Future<bool> ensureMicPermission() => _platform.ensureMicPermission();

  String _uiLanguage() {
    final locale = AppLocalizations.currentLocale.toLowerCase();
    return locale.startsWith('ar') ? 'ar' : 'en';
  }

  Future<void> startRecording() async {
    if (_platform.isRecording) return;
    try {
      await _platform.startRecording();
      _recordingStartedAt = DateTime.now();
    } on MissingPluginException {
      throw Exception(
        'Voice input is not available on this device. Refresh the page or update the app, then try again.',
      );
    }
  }

  Future<String> stopAndTranscribe({String? language}) async {
    if (!_platform.isRecording) {
      throw Exception('Not recording');
    }

    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;
    if (startedAt != null &&
        DateTime.now().difference(startedAt).inMilliseconds < 800) {
      await _platform.cancelRecording();
      throw Exception('Hold the mic for at least 1 second while you speak, then tap stop.');
    }

    final bytes = await _platform.stopRecordingBytes();
    if (bytes.isEmpty) {
      throw Exception(
        'No audio captured. Tap mic (red stop icon), speak clearly for 2–3 seconds, tap stop. Allow microphone access.',
      );
    }

    final lang = language ?? _uiLanguage();
    final filename = _platform.recordingFilename;
    final response = await ApiService.instance.postMultipart(
      '/ai/transcribe',
      fileField: 'file',
      bytes: bytes,
      filename: filename,
      fields: {'language': lang},
      timeout: const Duration(seconds: 180),
    );

    final transcript = (response['transcript'] ?? '').toString().trim();
    if (transcript.isEmpty) {
      throw Exception(
        'Could not detect speech. Speak clearly in Arabic or English for 2–3 seconds, then tap stop.',
      );
    }

    if (lang == 'ar' && _looksLikeArabicUiGarbageEnglish(transcript)) {
      throw Exception(
        'Voice was not recognized in Arabic. Speak clearly in Arabic for 2–3 seconds, then tap stop. '
        'Check that your app language is Arabic and the microphone is not muted.',
      );
    }

    return transcript;
  }

  Future<void> cancelRecording() => _platform.cancelRecording();

  Future<void> speakText(String text, {String? language, int? messageIndex}) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    await _platform.stopPlayback();
    _speakingMessageIndex = messageIndex;

    final lang = language ?? _uiLanguage();
    final response = await ApiService.instance.post('/ai/speak', {
      'text': cleaned,
      'language': lang,
    });
    final audioBase64 = (response['audio_base64'] ?? '').toString();
    if (audioBase64.isEmpty) {
      _speakingMessageIndex = null;
      throw Exception('Speech synthesis failed');
    }

    final bytes = base64Decode(audioBase64);
    await _platform.playBytes(
      bytes,
      onComplete: () {
        _speakingMessageIndex = null;
      },
    );
  }

  Future<void> stopSpeaking() async {
    await _platform.stopPlayback();
    _speakingMessageIndex = null;
  }

  void dispose() => _platform.dispose();
}
