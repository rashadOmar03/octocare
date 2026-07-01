import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/temp_password_card.dart';

class AdminCreateAdminScreen extends StatefulWidget {
  const AdminCreateAdminScreen({super.key});

  @override
  State<AdminCreateAdminScreen> createState() => _AdminCreateAdminScreenState();
}

class _AdminCreateAdminScreenState extends State<AdminCreateAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminService _service = AdminService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _tempPassword;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final result = await _service.createAdmin({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
      });
      setState(() => _tempPassword = result['temp_password'] ?? result['temporary_password'] ?? result['password']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('account_created')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('create_admin'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tempPassword != null) TempPasswordCard(tempPassword: _tempPassword!),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _firstNameController,
                label: AppLocalizations.tr('first_name'),
                prefixIcon: Icons.person,
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
              ),
              CustomTextField(
                controller: _lastNameController,
                label: AppLocalizations.tr('last_name'),
                prefixIcon: Icons.person,
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
              ),
              CustomTextField(
                controller: _emailController,
                label: AppLocalizations.tr('email'),
                prefixIcon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
              ),
              CustomTextField(
                controller: _phoneController,
                label: AppLocalizations.tr('phone'),
                prefixIcon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _create,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
