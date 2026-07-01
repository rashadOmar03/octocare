import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/custom_text_field.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || int.tryParse(otp) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.tr('invalid_otp')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }

    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.verifyEmail(widget.email, otp);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, Provider.of<AuthProvider>(context, listen: false).getPostAuthRoute());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? AppLocalizations.tr('error')), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _resend() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.resendOtp(widget.email, 'signup');
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
      appBar: AppBar(title: Text(AppLocalizations.tr('verify_email'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppLocalizations.tr('verify_email_desc'), style: Theme.of(context).textTheme.bodyLarge),
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
              onChanged: (value) {
                if (value.length == 6) {
                  FocusScope.of(context).unfocus();
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verify,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.tr('verify')),
              ),
            ),
            TextButton(onPressed: _isLoading ? null : _resend, child: Text(AppLocalizations.tr('resend_otp'))),
          ],
        ),
      ),
    );
  }
}
