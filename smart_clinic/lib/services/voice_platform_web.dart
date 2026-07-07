import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

JSObject _audioConstraints() {
  return <String, Object>{
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'channelCount': 1,
  }.jsify() as JSObject;
}

class VoicePlatform {
  MediaStream? _stream;
  MediaRecorder? _recorder;
  final List<Blob> _chunks = [];
  HTMLAudioElement? _audio;
  bool isRecording = false;
  String recordingFilename = 'voice.webm';
  String _mimeType = 'audio/webm';

  Future<bool> ensureMicPermission() async {
    try {
      final stream = await window.navigator.mediaDevices
          .getUserMedia(MediaStreamConstraints(audio: _audioConstraints()))
          .toDart;
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
      'audio/mp4',
      'audio/ogg;codecs=opus',
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
    _stream = await window.navigator.mediaDevices
        .getUserMedia(MediaStreamConstraints(audio: _audioConstraints()))
        .toDart;
    _chunks.clear();

    final mime = _pickMimeType();
    _mimeType = mime ?? 'audio/webm';
    recordingFilename = _filenameForMime(_mimeType);
    _recorder = mime != null
        ? MediaRecorder(_stream!, MediaRecorderOptions(mimeType: mime))
        : MediaRecorder(_stream!);

    _recorder!.addEventListener(
      'dataavailable',
      ((Event event) {
        final data = (event as BlobEvent).data;
        if (data.size > 0) {
          _chunks.add(data);
        }
      }).toJS,
    );

    // Timeslice ensures chunks are emitted reliably across browsers.
    _recorder!.start(250);
    isRecording = true;
  }

  Future<Uint8List> stopRecordingBytes() async {
    if (_recorder == null) throw Exception('Not recording');
    final completer = Completer<void>();
    _recorder!.addEventListener('stop', ((Event _) => completer.complete()).toJS);
    try {
      _recorder!.requestData();
    } catch (_) {}
    _recorder!.stop();
    await completer.future;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    isRecording = false;
    _stopStreamTracks();

    if (_chunks.isEmpty) return Uint8List(0);
    final blob = Blob(
      _chunks.map((b) => b as BlobPart).toList().toJS,
      BlobPropertyBag(type: _mimeType),
    );
    if (blob.size < 2500) return Uint8List(0);
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
    reader.addEventListener(
      'loadend',
      ((Event _) {
        final result = reader.result;
        if (result == null) {
          completer.complete(Uint8List(0));
          return;
        }
        completer.complete((result as JSArrayBuffer).toDart.asUint8List());
      }).toJS,
    );
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
