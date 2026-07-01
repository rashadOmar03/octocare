import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/ui_helpers.dart';

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key});

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  Map<String, dynamic> _profileData = {};
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _loadError;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _qualificationsController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _qualificationsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _populateFields() {
    _firstNameController.text = (_profileData['first_name'] ?? '').toString();
    _lastNameController.text = (_profileData['last_name'] ?? '').toString();
    _phoneController.text = (_profileData['phone'] ?? '').toString();
    _addressController.text = (_profileData['address'] ?? '').toString();
    _qualificationsController.text = (_profileData['qualifications'] ?? '').toString();
    _bioController.text = (_profileData['bio'] ?? '').toString();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ApiService.instance.get('/doctors/me');
      _profileData = Map<String, dynamic>.from(response);
      _populateFields();
    } catch (e) {
      _loadError = extractApiError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (_firstNameController.text.trim().isEmpty || _lastNameController.text.trim().isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('field_required'));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ApiService.instance.put('/doctors/me', {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'qualifications': _qualificationsController.text.trim(),
        'bio': _bioController.text.trim(),
      });

      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.updateProfile({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
      });

      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('profile_updated'));
        setState(() => _isEditing = false);
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final locale = Provider.of<LocaleProvider>(context);
    final user = auth.currentUser;
    final displayName = '${_profileData['first_name'] ?? user?.firstName ?? ''} ${_profileData['last_name'] ?? user?.lastName ?? ''}'.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('profile')),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit),
              tooltip: AppLocalizations.tr('edit'),
              onPressed: () => setState(() {
                if (_isEditing) _populateFields();
                _isEditing = !_isEditing;
              }),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        ProfileAvatar(
                          photoUrl: _profileData['photo_url'],
                          name: _profileData['first_name']?.toString() ?? user?.firstName,
                          onPhotoChanged: _loadProfile,
                        ),
                        const SizedBox(height: 12),
                        if (_isEditing) ...[
                          CustomTextField(controller: _firstNameController, label: AppLocalizations.tr('first_name')),
                          CustomTextField(controller: _lastNameController, label: AppLocalizations.tr('last_name')),
                          CustomTextField(controller: _qualificationsController, label: AppLocalizations.tr('qualifications'), maxLines: 2),
                          CustomTextField(controller: _bioController, label: AppLocalizations.tr('bio'), maxLines: 3),
                        ] else ...[
                          Text('Dr. $displayName', style: Theme.of(context).textTheme.titleLarge),
                          if (_profileData['specialty'] != null)
                            Text(_profileData['specialty'].toString(), style: Theme.of(context).textTheme.bodyMedium),
                          if (_profileData['qualifications']?.toString().isNotEmpty == true)
                            Text(_profileData['qualifications'].toString(), style: Theme.of(context).textTheme.bodySmall),
                          if (_profileData['bio']?.toString().isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_profileData['bio'].toString(), style: Theme.of(context).textTheme.bodySmall),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(leading: const Icon(Icons.email), title: Text(AppLocalizations.tr('email')), subtitle: Text(_profileData['email']?.toString() ?? user?.email ?? '-')),
                      if (_isEditing)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: CustomTextField(controller: _phoneController, label: AppLocalizations.tr('phone')),
                        )
                      else
                        ListTile(leading: const Icon(Icons.phone), title: Text(AppLocalizations.tr('phone')), subtitle: Text(_profileData['phone']?.toString() ?? user?.phone ?? '-')),
                      if (_isEditing)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: CustomTextField(controller: _addressController, label: AppLocalizations.tr('address'), maxLines: 2),
                        )
                      else if (_profileData['address']?.toString().isNotEmpty == true)
                        ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(AppLocalizations.tr('address')), subtitle: Text(_profileData['address'].toString())),
                    ],
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(AppLocalizations.tr('save')),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(title: Text(AppLocalizations.tr('dark_mode')), secondary: const Icon(Icons.dark_mode), value: theme.isDarkMode, onChanged: (_) => theme.toggleTheme()),
                      ListTile(leading: const Icon(Icons.language), title: Text(AppLocalizations.tr('language')), trailing: Text(locale.isArabic ? AppLocalizations.tr('arabic') : AppLocalizations.tr('english')), onTap: () => locale.toggleLocale()),
                      ListTile(leading: const Icon(Icons.lock_outline), title: Text(AppLocalizations.tr('change_password')), trailing: const Icon(Icons.arrow_forward_ios, size: 16), onTap: () => Navigator.pushNamed(context, AppRoutes.changePassword)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    await auth.logout();
                    if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(AppLocalizations.tr('logout')),
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 4, role: 'doctor'),
    );
  }
}
