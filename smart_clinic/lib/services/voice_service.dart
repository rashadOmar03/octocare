import 'dart:convert';

import 'api_service.dart';import 'voice_platform.dart';

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
    if (!await ensureMicPermission()) {
      throw Exception('Microphone permission is required for voice input.');
    }
    await _platform.startRecording();
    _recordingStartedAt = DateTime.now();
  }

  Future<String> stopAndTranscribe({String? language}) async {
    if (!_platform.isRecording) {
      throw Exception('Not recording');
    }

    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;
    if (startedAt != null &&
        DateTime.now().difference(startedAt).inMilliseconds < 900) {
      await _platform.cancelRecording();
      throw Exception('Hold the mic a little longer while you speak, then tap stop.');
    }

    final bytes = await _platform.stopRecordingBytes();
    if (bytes.isEmpty) {
      throw Exception('No audio captured. Check your microphone and try again.');
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
    if (transcript.isEmpty) {
      throw Exception('Could not detect speech. Please try again or type your message.');
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
