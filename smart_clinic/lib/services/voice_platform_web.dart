import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Web voice capture via browser MediaRecorder (no Flutter `record` plugin).
/// The `record` package causes MissingPluginException on web when served from
/// backend/web because record_web is not always registered in that bundle.
class VoicePlatform {
  MediaStream? _stream;
  MediaRecorder? _recorder;
  final List<Blob> _chunks = [];
  HTMLAudioElement? _audio;
  bool isRecording = false;
  String recordingFilename = 'voice.webm';
  String _mimeType = 'audio/webm';
  Completer<void>? _stopCompleter;

  Future<MediaStream> _getMicStream() async {
    final mediaDevices = window.navigator.mediaDevices;
    try {
      final constraints = MediaStreamConstraints(
        audio: <String, Object>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 1,
        }.jsify() as JSObject,
      );
      return await mediaDevices.getUserMedia(constraints).toDart;
    } catch (_) {
      return await mediaDevices
          .getUserMedia(MediaStreamConstraints(audio: true.toJS))
          .toDart;
    }
  }

  Future<bool> ensureMicPermission() async {
    try {
      final stream = await _getMicStream();
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _pickMimeType() {
    const candidates = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ];
    for (final mime in candidates) {
      if (MediaRecorder.isTypeSupported(mime)) {
        return mime;
      }
    }
    return null;
  }

  String _filenameForMime(String mime) {
    if (mime.contains('mp4')) return 'voice.mp4';
    if (mime.contains('ogg')) return 'voice.ogg';
    return 'voice.webm';
  }

  Future<void> startRecording() async {
    if (isRecording) return;
    _chunks.clear();
    _stream = await _getMicStream();

    final mime = _pickMimeType();
    _mimeType = mime ?? 'audio/webm';
    recordingFilename = _filenameForMime(_mimeType);

    _recorder = mime != null
        ? MediaRecorder(_stream!, MediaRecorderOptions(mimeType: mime))
        : MediaRecorder(_stream!);

    _recorder!.ondataavailable = ((BlobEvent event) {
      final data = event.data;
      if (data.size > 0) {
        _chunks.add(data);
      }
    }).toJS;

    _recorder!.onstop = ((Event _) {
      final completer = _stopCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }).toJS;

    // Timeslice keeps Chrome/Edge emitting chunks during recording.
    _recorder!.start(200);
    isRecording = true;
  }

  Future<Uint8List> stopRecordingBytes() async {
    final recorder = _recorder;
    if (recorder == null) return Uint8List(0);

    _stopCompleter = Completer<void>();
    final state = recorder.state;
    if (state == 'recording' || state == 'paused') {
      try {
        recorder.requestData();
      } catch (_) {}
      recorder.stop();
      try {
        await _stopCompleter!.future.timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    isRecording = false;
    _stopStreamTracks();
    _recorder = null;

    if (_chunks.isEmpty) return Uint8List(0);

    final blob = Blob(
      _chunks.map((b) => b as BlobPart).toList().toJS,
      BlobPropertyBag(type: _mimeType),
    );
    _chunks.clear();
    if (blob.size < 100) return Uint8List(0);
    return _blobToBytes(blob);
  }

  Future<void> cancelRecording() async {
    if (_recorder != null && isRecording) {
      try {
        _recorder!.stop();
      } catch (_) {}
    }
    isRecording = false;
    _stopStreamTracks();
    _chunks.clear();
    _recorder = null;
  }

  void _stopStreamTracks() {
    final stream = _stream;
    if (stream == null) return;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
    _stream = null;
  }

  Future<Uint8List> _blobToBytes(Blob blob) async {
    final reader = FileReader();
    final completer = Completer<Uint8List>();
    reader.onloadend = ((Event _) {
      final result = reader.result;
      if (result == null) {
        completer.complete(Uint8List(0));
        return;
      }
      completer.complete((result as JSArrayBuffer).toDart.asUint8List());
    }).toJS;
    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  Future<void> playBytes(Uint8List bytes, {void Function()? onComplete}) async {
    await stopPlayback();
    final blob = Blob(
      [bytes.toJS].toJS,
      BlobPropertyBag(type: 'audio/mpeg'),
    );
    final url = URL.createObjectURL(blob);
    final audio = HTMLAudioElement()..src = url;
    _audio = audio;
    audio.onended = ((Event _) {
      URL.revokeObjectURL(url);
      onComplete?.call();
    }).toJS;
    await audio.play().toDart;
  }

  Future<void> stopPlayback() async {
    final audio = _audio;
    if (audio == null) return;
    audio.pause();
    audio.src = '';
    _audio = null;
  }

  void dispose() {
    cancelRecording();
    stopPlayback();
  }
}
