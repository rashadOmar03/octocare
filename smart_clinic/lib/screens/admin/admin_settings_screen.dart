import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../config/routes.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/time_picker_field.dart';
import '../../widgets/bottom_nav.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final AdminService _service = AdminService();
  final _formKey = GlobalKey<FormState>();
  final _clinicNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _feeController = TextEditingController();
  final _startHourController = TextEditingController();
  final _endHourController = TextEditingController();
  final _durationController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPurging = false;
  final Set<int> _workingDays = {5, 6, 0, 1, 2, 3};

  static const _allDays = [5, 6, 0, 1, 2, 3, 4];

  String _dayLabel(int day) {
    switch (day) {
      case 0:
        return AppLocalizations.tr('day_mon');
      case 1:
        return AppLocalizations.tr('day_tue');
      case 2:
        return AppLocalizations.tr('day_wed');
      case 3:
        return AppLocalizations.tr('day_thu');
      case 4:
        return AppLocalizations.tr('day_fri');
      case 5:
        return AppLocalizations.tr('day_sat');
      case 6:
        return AppLocalizations.tr('day_sun');
      default:
        return '$day';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _service.getSettings();
      _clinicNameController.text = settings['clinic_name'] ?? '';
      _addressController.text = settings['address'] ?? '';
      _phoneController.text = settings['phone'] ?? '';
      _emailController.text = settings['email'] ?? '';
      _feeController.text = settings['default_fee']?.toString() ?? '';
      _startHourController.text = settings['working_hours_start'] ?? '09:00';
      _endHourController.text = settings['working_hours_end'] ?? '17:00';
      _durationController.text = settings['appointment_duration']?.toString() ?? '30';
      final rawDays = settings['working_days']?.toString() ?? '5,6,0,1,2,3';
      _workingDays
        ..clear()
        ..addAll(rawDays.split(',').map((e) => int.tryParse(e.trim())).whereType<int>());
      if (_workingDays.isEmpty) _workingDays.addAll([5, 6, 0, 1, 2, 3]);
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final days = _workingDays.toList()..sort();
      await _service.updateSettings({
        'clinic_name': _clinicNameController.text,
        'address': _addressController.text,
        'phone': _phoneController.text,
        'email': _emailController.text,
        'default_fee': double.tryParse(_feeController.text),
        'working_hours_start': _startHourController.text,
        'working_hours_end': _endHourController.text,
        'working_days': days.join(','),
        'appointment_duration': int.tryParse(_durationController.text) ?? 30,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('settings_saved')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  String? _validateTime(String? v) {
    if (v == null || v.trim().isEmpty) return AppLocalizations.tr('required');
    if (!RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(v.trim())) {
      return AppLocalizations.tr('invalid_time');
    }
    return null;
  }

  Future<void> _purgeAllPatients() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('purge_patients_title')),
        content: Text(AppLocalizations.tr('purge_patients_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.tr('purge_patients_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(AppLocalizations.tr('purge_patients_type_title')),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'DELETE_ALL_PATIENTS',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(AppLocalizations.tr('confirm')),
            ),
          ],
        );
      },
    );
    if (typed != 'DELETE_ALL_PATIENTS' || !mounted) return;

    setState(() => _isPurging = true);
    try {
      final result = await _service.purgeAllPatients();
      final stats = Map<String, dynamic>.from(result['stats'] as Map? ?? {});
      if (mounted) {
        showSuccessSnackBar(
          context,
          AppLocalizations.tr('purge_patients_success')
              .replaceAll('{count}', '${stats['patients_deleted'] ?? 0}'),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isPurging = false);
  }

  @override
  void dispose() {
    _clinicNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _feeController.dispose();
    _startHourController.dispose();
    _endHourController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(appBar: AppBar(title: Text(AppLocalizations.tr('settings'))), body: const LoadingWidget());

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('clinic_settings'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppLocalizations.tr('clinic_settings'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              CustomTextField(controller: _clinicNameController, label: AppLocalizations.tr('clinic_name'), prefixIcon: Icons.business, validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.tr('required') : null),
              CustomTextField(controller: _addressController, label: AppLocalizations.tr('clinic_address'), prefixIcon: Icons.location_on, maxLines: 2),
              CustomTextField(controller: _phoneController, label: AppLocalizations.tr('clinic_phone'), prefixIcon: Icons.phone, keyboardType: TextInputType.phone, validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.tr('required') : null),
              CustomTextField(controller: _emailController, label: AppLocalizations.tr('clinic_email'), prefixIcon: Icons.email, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              Text(AppLocalizations.tr('appointments'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              CustomTextField(controller: _feeController, label: AppLocalizations.tr('default_fee'), prefixIcon: Icons.attach_money, keyboardType: TextInputType.number),
              CustomTextField(controller: _durationController, label: AppLocalizations.tr('appointment_duration'), prefixIcon: Icons.timer, keyboardType: TextInputType.number),
              Row(
                children: [
                  Expanded(child: TimePickerField(controller: _startHourController, label: AppLocalizations.tr('working_hours'))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
                  Expanded(child: TimePickerField(controller: _endHourController, label: '')),
                ],
              ),
              const SizedBox(height: 8),
              Text(AppLocalizations.tr('working_days'), style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: _allDays.map((day) {
                  final selected = _workingDays.contains(day);
                  return FilterChip(
                    label: Text(_dayLabel(day)),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _workingDays.add(day);
                      } else {
                        _workingDays.remove(day);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.adminDoctorSchedules),
                icon: const Icon(Icons.medical_services_outlined),
                label: Text(AppLocalizations.tr('manage_doctor_schedules')),
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.tr('notifications'), style: Theme.of(context).textTheme.titleMedium),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(AppLocalizations.tr('in_app_notifications_info'))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(AppLocalizations.tr('danger_zone'), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(AppLocalizations.tr('purge_patients_hint')),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isPurging ? null : _purgeAllPatients,
                        icon: _isPurging
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.delete_forever),
                        label: Text(AppLocalizations.tr('purge_patients_button')),
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: const Icon(Icons.save),
                label: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(AppLocalizations.tr('save_settings')),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3, role: 'admin'),
    );
  }
}
