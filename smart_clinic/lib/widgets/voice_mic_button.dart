import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../services/voice_service.dart';
import '../utils/ui_helpers.dart';

class VoiceMicButton extends StatefulWidget {
  final TextEditingController controller;
  final bool appendWithSpace;
  final VoidCallback? onTranscribed;
  /// When set (e.g. AI chat), transcribed text is sent immediately instead of filling the field.
  final Future<void> Function(String text)? onAutoSend;

  const VoiceMicButton({
    super.key,
    required this.controller,
    this.appendWithSpace = true,
    this.onTranscribed,
    this.onAutoSend,
  });

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  final VoiceService _voice = VoiceService.instance;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;

    if (_voice.isRecording) {
      setState(() => _busy = true);
      try {
        final text = await _voice.stopAndTranscribe();
        if (widget.onAutoSend != null) {
          await widget.onAutoSend!(text);
        } else {
          final current = widget.controller.text.trim();
          final separator = widget.appendWithSpace && current.isNotEmpty ? ' ' : '';
          widget.controller.text = '$current$separator$text';
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
          widget.onTranscribed?.call();
        }
      } catch (e) {
        if (mounted) showErrorSnackBar(context, e);
      }
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      await _voice.startRecording();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.tr('voice_listening')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _voice.isRecording;
    return IconButton(
      tooltip: recording ? AppLocalizations.tr('voice_stop') : AppLocalizations.tr('voice_speak'),
      onPressed: _busy ? null : _toggle,
      icon: _busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: recording ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
              ),
            )
          : Icon(
              recording ? Icons.stop_circle_outlined : Icons.mic_none,
              color: recording ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
            ),
    );
  }
}

class VoiceMicSuffix extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTranscribed;
  final Future<void> Function(String text)? onAutoSend;

  const VoiceMicSuffix({
    super.key,
    required this.controller,
    this.onTranscribed,
    this.onAutoSend,
  });

  @override
  Widget build(BuildContext context) {
    return VoiceMicButton(
      controller: controller,
      onTranscribed: onTranscribed,
      onAutoSend: onAutoSend,
    );
  }
}
