import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import 'voice_file_reader.dart';

class VoicePlatform {
  AudioRecorder? _recorder;
  AudioPlayer? _playerInstance;
  bool isRecording = false;
  String recordingFilename = 'voice.webm';
  AudioEncoder _encoder = AudioEncoder.opus;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();
  AudioPlayer get _audioPlayer => _playerInstance ??= AudioPlayer();

  Future<bool> ensureMicPermission() => _rec.hasPermission();

  Future<AudioEncoder> _pickEncoder() async {
    if (await _rec.isEncoderSupported(AudioEncoder.opus)) {
      recordingFilename = 'voice.webm';
      return AudioEncoder.opus;
    }
    if (await _rec.isEncoderSupported(AudioEncoder.wav)) {
      recordingFilename = 'voice.wav';
      return AudioEncoder.wav;
    }
    recordingFilename = 'voice.webm';
    return AudioEncoder.opus;
  }

  Future<void> startRecording() async {
    if (isRecording) return;
    _encoder = await _pickEncoder();
    await _rec.start(
      RecordConfig(
        encoder: _encoder,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: '',
    );
    isRecording = true;
  }

  Future<Uint8List> stopRecordingBytes() async {
    if (!isRecording) throw Exception('Not recording');
    final url = await _rec.stop();
    isRecording = false;
    if (url == null || url.isEmpty) return Uint8List(0);
    final bytes = await readRecordingBytes(url);
    if (bytes.length < 200) return Uint8List(0);
    return Uint8List.fromList(bytes);
  }

  Future<void> cancelRecording() async {
    if (!isRecording) return;
    await _rec.cancel();
    isRecording = false;
  }

  Future<void> playBytes(Uint8List bytes, {void Function()? onComplete}) async {
    await stopPlayback();
    await _audioPlayer.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    _audioPlayer.onPlayerComplete.first.then((_) => onComplete?.call());
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
  }

  void dispose() {
    _recorder?.dispose();
    _playerInstance?.dispose();
  }
}
