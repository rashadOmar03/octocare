import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/temp_password_card.dart';
import '../../utils/ui_helpers.dart';

class AdminCreatePatientScreen extends StatefulWidget {
  const AdminCreatePatientScreen({super.key});

  @override
  State<AdminCreatePatientScreen> createState() => _AdminCreatePatientScreenState();
}

class _AdminCreatePatientScreenState extends State<AdminCreatePatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminService _service = AdminService();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  String? _gender;
  String? _bloodType;
  bool _isLoading = false;
  String? _tempPassword;
  bool _registrationComplete = false;
  bool _otpSent = true;
  bool _welcomeEmailSent = true;

  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _allergiesController.dispose();
    _chronicController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _dobController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await _service.createPatient({
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'date_of_birth': _dobController.text,
        'gender': _gender,
        'address': _addressController.text.trim(),
        'blood_type': _bloodType ?? 'Unknown',
        'allergies': _allergiesController.text.trim(),
        'chronic_diseases': _chronicController.text.trim(),
        'emergency_contact_name': _emergencyNameController.text.trim(),
        'emergency_contact_phone': _emergencyPhoneController.text.trim(),
      });
      setState(() {
        _tempPassword = response['temp_password'] ?? response['temporary_password'];
        _otpSent = response['otp_sent'] != false;
        _welcomeEmailSent = response['welcome_email_sent'] != false;
        _registrationComplete = true;
      });
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('account_created'));
        if (_otpSent) {
          showSuccessSnackBar(context, AppLocalizations.tr('otp_sent_to_patient'));
        } else {
          showErrorSnackBar(context, AppLocalizations.tr('otp_send_failed'));
        }
        if (!_welcomeEmailSent) {
          showErrorSnackBar(context, AppLocalizations.tr('welcome_email_failed'));
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('register_patient'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_registrationComplete && _tempPassword != null)
                TempPasswordCard(
                  tempPassword: _tempPassword!,
                  subtitle: '${AppLocalizations.tr('login_blocked_until_verified')}\n\n'
                      '${_otpSent ? AppLocalizations.tr('otp_sent_to_patient') : AppLocalizations.tr('otp_send_failed')}\n\n'
                      '${AppLocalizations.tr('patient_must_verify_email')}',
                ),
              if (!_registrationComplete) ...[
                CustomTextField(controller: _firstNameController, label: AppLocalizations.tr('first_name'), prefixIcon: Icons.person, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
                CustomTextField(controller: _middleNameController, label: AppLocalizations.tr('middle_name'), prefixIcon: Icons.person),
                CustomTextField(controller: _lastNameController, label: AppLocalizations.tr('last_name'), prefixIcon: Icons.person, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
                CustomTextField(controller: _emailController, label: AppLocalizations.tr('email'), prefixIcon: Icons.email, keyboardType: TextInputType.emailAddress, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
                CustomTextField(controller: _phoneController, label: AppLocalizations.tr('phone'), prefixIcon: Icons.phone, keyboardType: TextInputType.phone, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
                CustomTextField(controller: _dobController, label: AppLocalizations.tr('date_of_birth'), prefixIcon: Icons.cake, readOnly: true, onTap: _selectDate, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: InputDecoration(labelText: AppLocalizations.tr('gender'), prefixIcon: const Icon(Icons.wc)),
                  items: [
                    DropdownMenuItem(value: 'male', child: Text(AppLocalizations.tr('male'))),
                    DropdownMenuItem(value: 'female', child: Text(AppLocalizations.tr('female'))),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                  validator: (v) => v == null ? AppLocalizations.tr('field_required') : null,
                ),
                CustomTextField(controller: _addressController, label: AppLocalizations.tr('address'), prefixIcon: Icons.location_on, maxLines: 2, validator: (v) => v == null || v.trim().isEmpty ? AppLocalizations.tr('field_required') : null),
                CustomTextField(controller: _emergencyNameController, label: '${AppLocalizations.tr('emergency_contact_name')} (${AppLocalizations.tr('optional_field')})', prefixIcon: Icons.contact_emergency),
                CustomTextField(controller: _emergencyPhoneController, label: '${AppLocalizations.tr('emergency_contact_phone')} (${AppLocalizations.tr('optional_field')})', prefixIcon: Icons.phone, keyboardType: TextInputType.phone),
                DropdownButtonFormField<String>(
                  initialValue: _bloodType,
                  decoration: InputDecoration(labelText: AppLocalizations.tr('blood_type'), prefixIcon: const Icon(Icons.bloodtype)),
                  items: _bloodTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _bloodType = v),
                ),
                CustomTextField(controller: _allergiesController, label: AppLocalizations.tr('allergies'), prefixIcon: Icons.warning_amber, maxLines: 2),
                CustomTextField(controller: _chronicController, label: AppLocalizations.tr('chronic_diseases'), prefixIcon: Icons.medical_services, maxLines: 2),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(AppLocalizations.tr('save')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
