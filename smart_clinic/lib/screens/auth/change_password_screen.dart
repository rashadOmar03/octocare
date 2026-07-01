import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../widgets/custom_text_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.changePassword(
      _currentPasswordController.text,
      _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      await auth.refreshProfileComplete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? AppLocalizations.tr('password_changed')),
          backgroundColor: const Color(0xFF388E3C),
        ),
      );
      Navigator.pushReplacementNamed(context, auth.getPostAuthRoute());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? AppLocalizations.tr('error')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('change_password')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.lock_reset, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 32),
              CustomTextField(
                controller: _currentPasswordController,
                label: AppLocalizations.tr('current_password'),
                prefixIcon: Icons.lock_outlined,
                obscureText: _obscureCurrent,
                suffix: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
              ),
              CustomTextField(
                controller: _newPasswordController,
                label: AppLocalizations.tr('new_password'),
                prefixIcon: Icons.lock_outlined,
                obscureText: _obscureNew,
                suffix: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return AppLocalizations.tr('field_required');
                  if (value.length < 8) return AppLocalizations.tr('password_too_short');
                  return null;
                },
              ),
              CustomTextField(
                controller: _confirmPasswordController,
                label: AppLocalizations.tr('confirm_password'),
                prefixIcon: Icons.lock_outlined,
                obscureText: _obscureConfirm,
                suffix: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return AppLocalizations.tr('field_required');
                  if (value != _newPasswordController.text) return AppLocalizations.tr('passwords_dont_match');
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _changePassword,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(AppLocalizations.tr('save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
