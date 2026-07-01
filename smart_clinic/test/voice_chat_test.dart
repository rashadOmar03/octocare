import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clinic/widgets/voice_mic_button.dart';

void main() {
  test('VoiceMicButton auto-send mode does not require onTranscribed', () {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    final button = VoiceMicButton(
      controller: controller,
      onAutoSend: (text) async {
        expect(text, isNotEmpty);
      },
    );

    expect(button.onAutoSend, isNotNull);
    expect(button.onTranscribed, isNull);
  });
}
