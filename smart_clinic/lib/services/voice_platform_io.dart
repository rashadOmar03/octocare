import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_file_reader.dart';

class VoicePlatform {
  AudioRecorder? _recorder;
  AudioPlayer? _playerInstance;
  bool isRecording = false;
  String recordingFilename = 'voice.m4a';
  String? _recordPath;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();
  AudioPlayer get _audioPlayer => _playerInstance ??= AudioPlayer();

  Future<bool> ensureMicPermission() => _rec.hasPermission();

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
      path: _recordPath!,
    );
    isRecording = true;
  }

  Future<Uint8List> stopRecordingBytes() async {
    if (!isRecording) throw Exception('Not recording');
    final path = await _rec.stop();
    isRecording = false;
    final resolved = path ?? _recordPath;
    if (resolved == null || resolved.isEmpty) {
      return Uint8List(0);
    }
    final bytes = await readRecordingBytes(resolved);
    return Uint8List.fromList(bytes);
  }

  Future<void> cancelRecording() async {
    if (!isRecording) return;
    await _rec.stop();
    isRecording = false;
    _recordPath = null;
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
