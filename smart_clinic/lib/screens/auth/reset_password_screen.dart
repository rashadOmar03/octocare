import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/custom_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || int.tryParse(otp) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.tr('invalid_otp')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    if (_passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.tr('password_too_short')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.tr('passwords_dont_match')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }

    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.resetPassword(widget.email, _otpController.text.trim(), _passwordController.text);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
      );
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? AppLocalizations.tr('error')), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _resend() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.resendOtp(widget.email, 'password_reset');
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? AppLocalizations.tr('otp_sent')),
        backgroundColor: result['success'] == true ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('reset_password'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(AppLocalizations.tr('reset_password_desc'), style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(widget.email, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            CustomTextField(
              controller: _otpController,
              label: AppLocalizations.tr('enter_otp'),
              prefixIcon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            CustomTextField(
              controller: _passwordController,
              label: AppLocalizations.tr('new_password'),
              prefixIcon: Icons.lock_outlined,
              obscureText: _obscure,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            CustomTextField(
              controller: _confirmController,
              label: AppLocalizations.tr('confirm_password'),
              prefixIcon: Icons.lock_outlined,
              obscureText: _obscure,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _reset,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.tr('reset_password')),
              ),
            ),
            TextButton(onPressed: _isLoading ? null : _resend, child: Text(AppLocalizations.tr('resend_otp'))),
          ],
        ),
      ),
    );
  }
}
