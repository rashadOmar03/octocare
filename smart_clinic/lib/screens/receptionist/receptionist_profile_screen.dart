import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/ui_helpers.dart';

class ReceptionistProfileScreen extends StatefulWidget {
  const ReceptionistProfileScreen({super.key});

  @override
  State<ReceptionistProfileScreen> createState() => _ReceptionistProfileScreenState();
}

class _ReceptionistProfileScreenState extends State<ReceptionistProfileScreen> {
  Map<String, dynamic> _profileData = {};
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _loadError;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

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
    super.dispose();
  }

  void _populateFields() {
    _firstNameController.text = (_profileData['first_name'] ?? '').toString();
    _lastNameController.text = (_profileData['last_name'] ?? '').toString();
    _phoneController.text = (_profileData['phone'] ?? '').toString();
    _addressController.text = (_profileData['address'] ?? '').toString();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ApiService.instance.get('/patients/profile');
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

  String _displayPhone(AuthProvider auth) {
    final fromProfile = _profileData['phone']?.toString().trim();
    if (fromProfile != null && fromProfile.isNotEmpty && fromProfile != 'N/A') return fromProfile;
    return auth.currentUser?.phone ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final locale = Provider.of<LocaleProvider>(context);
    final user = auth.currentUser;

    return ReceptionistScaffold(
      title: AppLocalizations.tr('profile'),
      bottomNavIndex: 4,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
              ? _buildEditForm()
              : _buildView(auth, theme, locale, user),
    );
  }

  Widget _buildView(AuthProvider auth, ThemeProvider theme, LocaleProvider locale, dynamic user) {
    return ListView(
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
                Text(user?.fullName ?? '', style: Theme.of(context).textTheme.titleLarge),
                Text(user?.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone),
                title: Text(AppLocalizations.tr('phone')),
                subtitle: Text(_displayPhone(auth)),
              ),
              ListTile(
                leading: const Icon(Icons.email),
                title: Text(AppLocalizations.tr('email')),
                subtitle: Text(user?.email ?? '-'),
              ),
              if (_profileData['address'] != null && _profileData['address'].toString().trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(AppLocalizations.tr('address')),
                  subtitle: Text(_profileData['address'].toString()),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(AppLocalizations.tr('dark_mode')),
                secondary: const Icon(Icons.dark_mode),
                value: theme.isDarkMode,
                onChanged: (_) => theme.toggleTheme(),
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(AppLocalizations.tr('language')),
                trailing: Text(locale.isArabic ? AppLocalizations.tr('arabic') : AppLocalizations.tr('english')),
                onTap: () => locale.toggleLocale(),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(AppLocalizations.tr('change_password')),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.pushNamed(context, AppRoutes.changePassword),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            await auth.logout();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
            }
          },
          icon: const Icon(Icons.logout),
          label: Text(AppLocalizations.tr('logout')),
          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(AppLocalizations.tr('personal_info'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _firstNameController,
          label: AppLocalizations.tr('first_name'),
          prefixIcon: Icons.person,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _lastNameController,
          label: AppLocalizations.tr('last_name'),
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _phoneController,
          label: AppLocalizations.tr('phone'),
          prefixIcon: Icons.phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _addressController,
          label: AppLocalizations.tr('address'),
          prefixIcon: Icons.location_on,
          maxLines: 2,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProfile,
          child: _isSaving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(AppLocalizations.tr('save')),
        ),
      ],
    );
  }
}
