import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/custom_text_field.dart';
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
  bool _isLoading = true;
  bool _isSaving = false;
  bool _notificationsEnabled = true;
  bool _smsEnabled = false;
  bool _emailEnabled = true;

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
      _notificationsEnabled = settings['notifications_enabled'] ?? true;
      _smsEnabled = settings['sms_enabled'] ?? false;
      _emailEnabled = settings['email_enabled'] ?? true;
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _service.updateSettings({
        'clinic_name': _clinicNameController.text,
        'address': _addressController.text,
        'phone': _phoneController.text,
        'email': _emailController.text,
        'default_fee': double.tryParse(_feeController.text),
        'working_hours_start': _startHourController.text,
        'working_hours_end': _endHourController.text,
        'notifications_enabled': _notificationsEnabled,
        'sms_enabled': _smsEnabled,
        'email_enabled': _emailEnabled,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('settings_saved')), backgroundColor: const Color(0xFF388E3C)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error));
    }
    setState(() => _isSaving = false);
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
              Row(
                children: [
                  Expanded(child: CustomTextField(controller: _startHourController, label: AppLocalizations.tr('working_hours'))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
                  Expanded(child: CustomTextField(controller: _endHourController, label: '')),
                ],
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.tr('notifications'), style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(title: Text(AppLocalizations.tr('push_notifications')), value: _notificationsEnabled, onChanged: (v) => setState(() => _notificationsEnabled = v)),
              SwitchListTile(title: Text(AppLocalizations.tr('sms')), value: _smsEnabled, onChanged: (v) => setState(() => _smsEnabled = v)),
              SwitchListTile(title: Text(AppLocalizations.tr('email_notifications')), value: _emailEnabled, onChanged: (v) => setState(() => _emailEnabled = v)),
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
