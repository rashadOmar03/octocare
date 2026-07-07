import 'dart:convert';

import 'package:flutter/services.dart';

import 'api_service.dart';
import 'voice_platform.dart';

const _whisperHallucinations = {
  'you',
  'you.',
  'thank you',
  'thank you.',
  'thanks',
  'thanks.',
  'thanks for watching',
  'thank you for watching',
  'subscribe',
  'bye',
  'bye bye',
  'the end',
  '...',
  'mm',
  'hmm',
  'uh',
  'um',
  'okay',
  'ok',
  'شكرا',
  'شكراً',
  'مرحبا',
  'مرحباً',
};

bool _isLowQualityTranscript(String transcript, int audioBytes) {
  final cleaned = transcript.trim().toLowerCase().replaceAll(RegExp(r'[.,!?]+$'), '');
  if (cleaned.isEmpty) return true;
  if (_whisperHallucinations.contains(cleaned) && audioBytes < 16000) return true;
  if (cleaned.length <= 4 && audioBytes < 10000) return true;
  if (cleaned.split(RegExp(r'\s+')).length <= 1 && audioBytes < 6000) return true;
  return false;
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

  Future<void> startRecording() async {
    if (_platform.isRecording) return;
    try {
      final permitted = await _platform.ensureMicPermission();
      if (!permitted) {
        throw Exception(
          'Microphone access is blocked. Allow the microphone for this site in your browser settings, then refresh.',
        );
      }
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
        DateTime.now().difference(startedAt).inMilliseconds < 1200) {
      await _platform.cancelRecording();
      throw Exception('Hold the mic for at least 2 seconds while you speak, then tap stop.');
    }

    final bytes = await _platform.stopRecordingBytes();
    if (bytes.isEmpty) {
      throw Exception(
        'No audio captured. Click the mic once to start (red stop icon), speak for 2–3 seconds, then tap stop. '
        'Allow microphone access when the browser asks, and check your laptop or phone mic is not muted.',
      );
    }

    final filename = _platform.recordingFilename;
    final response = await ApiService.instance.postMultipart(
      '/ai/transcribe',
      fileField: 'file',
      bytes: bytes,
      filename: filename,
      fields: {
        if (language != null && (language == 'ar' || language == 'en')) 'language': language,
      },
      timeout: const Duration(seconds: 180),
    );

    final transcript = (response['transcript'] ?? '').toString().trim();
    if (transcript.isEmpty || _isLowQualityTranscript(transcript, bytes.length)) {
      throw Exception(
        'Could not detect clear speech. Speak for 2–3 seconds in a quiet place, then tap stop.',
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

    final response = await ApiService.instance.post('/ai/speak', {
      'text': cleaned,
      'language': language ?? 'en',
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
