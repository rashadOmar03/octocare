import 'package:flutter/material.dart';

import '../utils/time_format.dart';

/// Clinic hour field: stores 24h HH:mm in [controller], shows 12h AM/PM to the user.
class TimePickerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const TimePickerField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
  });

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeFormat.parseToTimeOfDay(controller.text),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) {
      controller.text = TimeFormat.formatTimeOfDay24(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      validator: validator,
      builder: (field) {
        return InkWell(
          onTap: () async {
            await _pickTime(context);
            field.didChange(controller.text);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: const Icon(Icons.access_time),
              errorText: field.errorText,
            ),
            child: Text(
              TimeFormat.format24To12(controller.text.isEmpty ? null : controller.text),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        );
      },
    );
  }
}
