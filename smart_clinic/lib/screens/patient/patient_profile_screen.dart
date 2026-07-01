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

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  Map<String, dynamic> _profileData = {};

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  String? _gender;
  String? _bloodType;
  String? _dob;

  bool get _needsProfileCompletion => _profileData['is_complete'] != true;

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
    _allergiesController.dispose();
    _chronicController.dispose();
    _medicationsController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
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
      _profileData = {};
      _loadError = e.toString();
    }
    setState(() => _isLoading = false);
  }

  void _populateFields() {
    _firstNameController.text = _profileData['first_name'] ?? '';
    _lastNameController.text = _profileData['last_name'] ?? '';
    _phoneController.text = _profileData['phone'] ?? '';
    _addressController.text = _profileData['address'] ?? '';
    _allergiesController.text = _profileData['allergies'] ?? '';
    _chronicController.text = _profileData['chronic_diseases'] ?? '';
    _medicationsController.text = _profileData['existing_conditions'] ?? '';
    _emergencyNameController.text = _profileData['emergency_contact_name'] ?? '';
    _emergencyPhoneController.text = _profileData['emergency_contact_phone'] ?? '';
    _gender = _profileData['gender'];
    _bloodType = _profileData['blood_type'];
    _dob = _profileData['dob'];
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final data = {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'chronic_diseases': _chronicController.text.trim(),
        'existing_conditions': _medicationsController.text.trim(),
        'emergency_contact_name': _emergencyNameController.text.trim(),
        'emergency_contact_phone': _emergencyPhoneController.text.trim(),
        'gender': _gender,
        'blood_type': _bloodType,
        'dob': _dob,
      };
      data.removeWhere((_, v) => v == null);
      await ApiService.instance.put('/patients/profile', data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('profile_updated')), backgroundColor: const Color(0xFF388E3C)),
        );
        setState(() => _isEditing = false);
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob != null ? DateTime.tryParse(_dob!) ?? DateTime(1990) : DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dob = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final locale = Provider.of<LocaleProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('profile')),
        actions: [
          if (!_isLoading && !_needsProfileCompletion)
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit),
              onPressed: () => setState(() {
                if (_isEditing) _populateFields();
                _isEditing = !_isEditing;
              }),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadProfile, child: Text(AppLocalizations.tr('retry'))),
                    ],
                  ),
                )
              : _needsProfileCompletion
                  ? _buildNoProfile()
                  : _isEditing
                  ? _buildEditForm()
                  : _buildProfileView(user, theme, locale, auth),
      bottomNavigationBar: const BottomNav(currentIndex: 4, role: 'patient'),
    );
  }

  Widget _buildNoProfile() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(AppLocalizations.tr('complete_profile_message')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.profileComplete),
            child: Text(AppLocalizations.tr('complete_profile')),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView(dynamic user, ThemeProvider theme, LocaleProvider locale, AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                ProfileAvatar(
                  photoUrl: _profileData['photo_url'],
                  name: _profileData['first_name'],
                  onPhotoChanged: _loadProfile,
                ),
                const SizedBox(height: 12),
                Text('${_profileData['first_name'] ?? ''} ${_profileData['last_name'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                Text(user?.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(AppLocalizations.tr('personal_info')),
        Card(
          child: Column(
            children: [
              _buildInfoTile(Icons.phone, AppLocalizations.tr('phone'), _profileData['phone'] ?? '-'),
              _buildInfoTile(Icons.cake, AppLocalizations.tr('date_of_birth'), _profileData['dob'] ?? '-'),
              _buildInfoTile(Icons.wc, AppLocalizations.tr('gender'), AppLocalizations.trValue(_profileData['gender'])),
              _buildInfoTile(Icons.location_on, AppLocalizations.tr('address'), _profileData['address'] ?? '-'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(AppLocalizations.tr('medical_info')),
        Card(
          child: Column(
            children: [
              _buildInfoTile(Icons.bloodtype, AppLocalizations.tr('blood_type'), _profileData['blood_type'] ?? '-'),
              _buildInfoTile(Icons.warning_amber, AppLocalizations.tr('allergies'), _profileData['allergies'] ?? '-'),
              _buildInfoTile(Icons.medical_services, AppLocalizations.tr('chronic_diseases'), _profileData['chronic_diseases'] ?? '-'),
              _buildInfoTile(Icons.medication, AppLocalizations.tr('medications'), _profileData['existing_conditions'] ?? '-'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(AppLocalizations.tr('emergency_contact')),
        Card(
          child: Column(
            children: [
              _buildInfoTile(Icons.person, AppLocalizations.tr('contact_name'), _profileData['emergency_contact_name'] ?? '-'),
              _buildInfoTile(Icons.phone, AppLocalizations.tr('contact_phone'), _profileData['emergency_contact_phone'] ?? '-'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(AppLocalizations.tr('settings')),
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
            if (!mounted) return;
            Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('personal_info'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(controller: _firstNameController, decoration: InputDecoration(labelText: AppLocalizations.tr('first_name'))),
                const SizedBox(height: 12),
                TextField(controller: _lastNameController, decoration: InputDecoration(labelText: AppLocalizations.tr('last_name'))),
                const SizedBox(height: 12),
                TextField(controller: _phoneController, decoration: InputDecoration(labelText: AppLocalizations.tr('phone')), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: _addressController, decoration: InputDecoration(labelText: AppLocalizations.tr('address'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: InputDecoration(labelText: AppLocalizations.tr('gender')),
                  items: ['male', 'female'].map((g) => DropdownMenuItem(value: g, child: Text(AppLocalizations.tr(g)))).toList(),
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.tr('date_of_birth')),
                  subtitle: Text(_dob ?? '-'),
                  trailing: IconButton(icon: const Icon(Icons.calendar_today), onPressed: _selectDate),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('medical_info'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _bloodType,
                  decoration: InputDecoration(labelText: AppLocalizations.tr('blood_type')),
                  items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _bloodType = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: _allergiesController, decoration: InputDecoration(labelText: AppLocalizations.tr('allergies')), maxLines: 2),
                const SizedBox(height: 12),
                TextField(controller: _chronicController, decoration: InputDecoration(labelText: AppLocalizations.tr('chronic_diseases')), maxLines: 2),
                const SizedBox(height: 12),
                TextField(controller: _medicationsController, decoration: InputDecoration(labelText: AppLocalizations.tr('medications')), maxLines: 2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('emergency_contact'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(controller: _emergencyNameController, decoration: InputDecoration(labelText: AppLocalizations.tr('contact_name'))),
                const SizedBox(height: 12),
                TextField(controller: _emergencyPhoneController, decoration: InputDecoration(labelText: AppLocalizations.tr('contact_phone')), keyboardType: TextInputType.phone),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(AppLocalizations.tr('save')),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
