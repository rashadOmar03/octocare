import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

@JS('console.log')
external void _consoleLog(JSString msg);
@JS('console.warn')
external void _consoleWarn(JSString msg);
@JS('console.error')
external void _consoleError(JSString msg);

void _jsLog(String msg) => _consoleLog(msg.toJS);
void _jsWarn(String msg) => _consoleWarn(msg.toJS);
void _jsError(String msg) => _consoleError(msg.toJS);

/// Web voice capture via browser MediaRecorder (no Flutter `record` plugin).
class VoicePlatform {
  MediaStream? _stream;
  MediaRecorder? _recorder;
  final List<Blob> _chunks = [];
  HTMLAudioElement? _audio;
  bool isRecording = false;
  String recordingFilename = 'voice.webm';
  String _mimeType = 'audio/webm';

  bool get _isAppleBrowser {
    final ua = window.navigator.userAgent.toLowerCase();
    final isApple = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    final isSafari = ua.contains('safari') && !ua.contains('chrome') && !ua.contains('chromium');
    return isApple || (ua.contains('macintosh') && isSafari);
  }

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

  Future<bool> ensureMicPermission() async => true;

  List<String> _mimeCandidates() {
    if (_isAppleBrowser) {
      return const [
        'audio/mp4',
        'audio/aac',
        'audio/webm;codecs=opus',
        'audio/webm',
        'audio/ogg;codecs=opus',
      ];
    }
    return const [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ];
  }

  String? _pickMimeType() {
    for (final mime in _mimeCandidates()) {
      if (MediaRecorder.isTypeSupported(mime)) {
        return mime;
      }
    }
    return null;
  }

  String _filenameForMime(String mime) {
    if (mime.contains('mp4') || mime.contains('aac')) return 'voice.m4a';
    if (mime.contains('ogg')) return 'voice.ogg';
    return 'voice.webm';
  }

  Future<void> startRecording() async {
    if (isRecording) return;
    _chunks.clear();
    _stopStreamTracks();

    try {
      _stream = await _getMicStream();
    } catch (_) {
      throw Exception(
        'Microphone access denied. Click the lock icon in the address bar, allow microphone, then refresh.',
      );
    }
    final audioTracks = _stream!.getAudioTracks().toDart;
    if (audioTracks.isEmpty) {
      _stopStreamTracks();
      throw Exception('No microphone track available.');
    }

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
        _jsLog('[Voice] chunk #${_chunks.length} size=${data.size}');
      }
    }).toJS;

    _recorder!.onerror = ((Event _) {
      _jsError('[Voice] MediaRecorder error');
    }).toJS;

    // Timeslice ensures Chrome/Edge/Firefox emit audio chunks reliably on laptops.
    _recorder!.start(250);
    isRecording = true;
    _jsLog('[Voice] Recording started mime=$_mimeType');
  }

  Future<Uint8List> stopRecordingBytes() async {
    final recorder = _recorder;
    if (recorder == null || !isRecording) {
      _jsWarn('[Voice] stopRecordingBytes: not recording');
      return Uint8List(0);
    }

    isRecording = false;
    final resultCompleter = Completer<Uint8List>();
    final mimeType = _mimeType;

    // Snapshot chunks so far; onstop may fire synchronously.
    final chunksCopy = List<Blob>.from(_chunks);

    recorder.onstop = ((Event _) {
      // Merge any new chunks that arrived between requestData and stop.
      final allChunks = <Blob>[...chunksCopy];
      for (final c in _chunks) {
        if (!allChunks.contains(c)) allChunks.add(c);
      }
      _chunks.clear();

      _jsLog('[Voice] onstop fired, ${allChunks.length} chunks');

      Future<void>.delayed(const Duration(milliseconds: 150)).then((_) async {
        try {
          Uint8List bytes = Uint8List(0);
          if (allChunks.isNotEmpty) {
            final blob = Blob(
              allChunks.map((b) => b as BlobPart).toList().toJS,
              BlobPropertyBag(type: mimeType),
            );
            _jsLog('[Voice] blob size=${blob.size} type=${blob.type}');
            if (blob.size >= 32) {
              bytes = await _blobToBytes(blob);
            }
          }
          _jsLog('[Voice] final bytes=${bytes.length}');
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(bytes);
          }
        } catch (e) {
          _jsError('[Voice] onstop error: $e');
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(Uint8List(0));
          }
        } finally {
          _finalizeRecording();
        }
      });
    }).toJS;

    try {
      recorder.requestData();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      recorder.stop();
    } catch (e) {
      _jsError('[Voice] stop error: $e');
      _finalizeRecording();
      return Uint8List(0);
    }

    try {
      return await resultCompleter.future.timeout(const Duration(seconds: 12));
    } catch (e) {
      _jsError('[Voice] timeout: $e');
      _finalizeRecording();
      return Uint8List(0);
    }
  }

  Future<void> cancelRecording() async {
    if (_recorder != null && isRecording) {
      try {
        _recorder!.stop();
      } catch (_) {}
    }
    isRecording = false;
    _chunks.clear();
    _finalizeRecording();
  }

  void _finalizeRecording() {
    _stopStreamTracks();
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
    reader.onerror = ((Event _) {
      completer.complete(Uint8List(0));
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
