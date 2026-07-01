import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/temp_password_card.dart';

class AdminCreateDoctorScreen extends StatefulWidget {
  const AdminCreateDoctorScreen({super.key});

  @override
  State<AdminCreateDoctorScreen> createState() => _AdminCreateDoctorScreenState();
}

class _AdminCreateDoctorScreenState extends State<AdminCreateDoctorScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminService _service = AdminService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _qualificationsController = TextEditingController();
  dynamic _selectedSpecialtyId;
  List<Map<String, dynamic>> _specialties = [];
  bool _isLoading = false;
  String? _tempPassword;

  @override
  void initState() {
    super.initState();
    _loadSpecialties();
  }

  Future<void> _loadSpecialties() async {
    try {
      _specialties = await _service.getSpecialties();
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _qualificationsController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final result = await _service.createDoctor({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'specialty_id': _selectedSpecialtyId,
        'qualifications': _qualificationsController.text.trim(),
      });
      setState(() => _tempPassword = result['temp_password'] ?? result['temporary_password'] ?? result['password']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('account_created')), backgroundColor: const Color(0xFF388E3C)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('create_doctor'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tempPassword != null)
                TempPasswordCard(tempPassword: _tempPassword!),
              const SizedBox(height: 16),
              CustomTextField(controller: _firstNameController, label: AppLocalizations.tr('first_name'), prefixIcon: Icons.person, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
              CustomTextField(controller: _lastNameController, label: AppLocalizations.tr('last_name'), prefixIcon: Icons.person, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
              CustomTextField(controller: _emailController, label: AppLocalizations.tr('email'), prefixIcon: Icons.email, keyboardType: TextInputType.emailAddress, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
              CustomTextField(controller: _phoneController, label: AppLocalizations.tr('phone'), prefixIcon: Icons.phone, keyboardType: TextInputType.phone, validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
              DropdownButtonFormField<dynamic>(
                initialValue: _selectedSpecialtyId,
                decoration: InputDecoration(labelText: AppLocalizations.tr('specialty'), prefixIcon: const Icon(Icons.category)),
                items: _specialties.map((s) => DropdownMenuItem<dynamic>(value: s['id'], child: Text(s['name'] ?? ''))).toList(),
                onChanged: (v) => setState(() => _selectedSpecialtyId = v),
                validator: (v) => v == null ? AppLocalizations.tr('field_required') : null,
              ),
              const SizedBox(height: 16),
              CustomTextField(controller: _qualificationsController, label: AppLocalizations.tr('qualifications'), prefixIcon: Icons.school, maxLines: 2),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _create,
                child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(AppLocalizations.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
