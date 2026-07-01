import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/custom_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _countryCode = '+966';

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.register({
      'first_name': _firstNameController.text.trim(),
      'middle_name': _middleNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': AuthProvider.normalizeEmail(_emailController.text),
      'phone': '$_countryCode${_phoneController.text.trim()}',
      'password': _passwordController.text,
    });

    if (!mounted) return;

    if (result['success'] == true) {
      if (result['requires_verification'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? AppLocalizations.tr('otp_sent')),
            backgroundColor: const Color(0xFF388E3C),
          ),
        );
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.verifyEmail,
          arguments: {'email': result['email'] ?? _emailController.text.trim()},
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.tr('registration_success')),
          backgroundColor: const Color(0xFF388E3C),
        ),
      );
      Navigator.pushReplacementNamed(context, Provider.of<AuthProvider>(context, listen: false).getPostAuthRoute());
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
    final auth = Provider.of<AuthProvider>(context);

    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('create_account')),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LangChip(
                  label: 'EN',
                  selected: !localeProvider.isArabic,
                  onTap: () => localeProvider.setLocale('en'),
                ),
                _LangChip(
                  label: 'عربي',
                  selected: localeProvider.isArabic,
                  onTap: () => localeProvider.setLocale('ar'),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => themeProvider.toggleTheme(),
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            tooltip: themeProvider.isDarkMode
                ? AppLocalizations.tr('light_mode')
                : AppLocalizations.tr('dark_mode'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _firstNameController,
                  label: AppLocalizations.tr('first_name'),
                  prefixIcon: Icons.person_outlined,
                  validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
                ),
                CustomTextField(
                  controller: _middleNameController,
                  label: AppLocalizations.tr('middle_name'),
                  prefixIcon: Icons.person_outlined,
                ),
                CustomTextField(
                  controller: _lastNameController,
                  label: AppLocalizations.tr('last_name'),
                  prefixIcon: Icons.person_outlined,
                  validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
                ),
                CustomTextField(
                  controller: _emailController,
                  label: AppLocalizations.tr('email'),
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return AppLocalizations.tr('field_required');
                    if (!value.contains('@')) return AppLocalizations.tr('invalid_email');
                    return null;
                  },
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        initialValue: _countryCode,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.tr('code'),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        items: const [
                          DropdownMenuItem(value: '+966', child: Text('+966')),
                          DropdownMenuItem(value: '+971', child: Text('+971')),
                          DropdownMenuItem(value: '+20', child: Text('+20')),
                          DropdownMenuItem(value: '+962', child: Text('+962')),
                          DropdownMenuItem(value: '+965', child: Text('+965')),
                          DropdownMenuItem(value: '+968', child: Text('+968')),
                          DropdownMenuItem(value: '+973', child: Text('+973')),
                          DropdownMenuItem(value: '+1', child: Text('+1')),
                          DropdownMenuItem(value: '+44', child: Text('+44')),
                          DropdownMenuItem(value: '+91', child: Text('+91')),
                        ],
                        onChanged: (v) => setState(() => _countryCode = v ?? '+966'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CustomTextField(
                        controller: _phoneController,
                        label: AppLocalizations.tr('phone'),
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null,
                      ),
                    ),
                  ],
                ),
                CustomTextField(
                  controller: _passwordController,
                  label: AppLocalizations.tr('password'),
                  prefixIcon: Icons.lock_outlined,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                    if (value != _passwordController.text) return AppLocalizations.tr('passwords_dont_match');
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _register,
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(AppLocalizations.tr('register')),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppLocalizations.tr('already_have_account')),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.tr('sign_in')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
