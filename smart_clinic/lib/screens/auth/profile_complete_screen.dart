import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../widgets/custom_text_field.dart';

class ProfileCompleteScreen extends StatefulWidget {
  const ProfileCompleteScreen({super.key});

  @override
  State<ProfileCompleteScreen> createState() => _ProfileCompleteScreenState();
}

class _ProfileCompleteScreenState extends State<ProfileCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _loadingProfile = true;

  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();
  final _conditionsController = TextEditingController();

  String? _gender;
  String? _bloodType;
  String? _storedFirstName;
  String? _storedLastName;
  String? _storedPhone;

  final List<String> _bloodTypes = ['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<String> _stepTitles = ['personal_info', 'contact_info', 'medical_info'];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _dobController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _allergiesController.dispose();
    _chronicController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  bool _isFilled(dynamic value) {
    if (value == null) return false;
    final text = value.toString().trim();
    return text.isNotEmpty && text != 'N/A';
  }

  String _pickNonEmpty(String? primary, String? fallback) {
    for (final value in [primary, fallback]) {
      if (_isFilled(value)) return value!.trim();
    }
    return '';
  }

  Future<void> _loadExistingProfile() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = await ApiService.instance.get('/patients/profile');
      if (data['is_complete'] == true && mounted) {
        auth.refreshProfileComplete();
        Navigator.pushReplacementNamed(context, auth.getPostAuthRoute());
        return;
      }
      if (_isFilled(data['first_name'])) _storedFirstName = data['first_name'].toString();
      if (_isFilled(data['last_name'])) _storedLastName = data['last_name'].toString();
      if (_isFilled(data['phone'])) {
        _storedPhone = data['phone'].toString();
        _phoneController.text = _storedPhone!;
      }
      if (data['dob'] != null) _dobController.text = data['dob'].toString();
      if (_isFilled(data['gender'])) _gender = data['gender'].toString();
      if (_isFilled(data['address'])) _addressController.text = data['address'].toString();
      if (_isFilled(data['emergency_contact_name'])) {
        _emergencyNameController.text = data['emergency_contact_name'].toString();
      }
      if (_isFilled(data['emergency_contact_phone'])) {
        _emergencyPhoneController.text = data['emergency_contact_phone'].toString();
      }
      if (_isFilled(data['blood_type'])) _bloodType = data['blood_type'].toString();
      if (_isFilled(data['allergies'])) _allergiesController.text = data['allergies'].toString();
      if (_isFilled(data['chronic_diseases'])) _chronicController.text = data['chronic_diseases'].toString();
      if (_isFilled(data['existing_conditions'])) {
        _conditionsController.text = data['existing_conditions'].toString();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProfile = false);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobController.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  String? _validatePersonalInfo() {
    if (_dobController.text.trim().isEmpty) return AppLocalizations.tr('field_required');
    if (_gender == null || _gender!.isEmpty) return AppLocalizations.tr('field_required');
    if (_phoneController.text.trim().isEmpty) return AppLocalizations.tr('field_required');
    if (_addressController.text.trim().isEmpty) return AppLocalizations.tr('field_required');
    return null;
  }

  String? _validateContactInfo() => null;

  String? _validateMedicalInfo() => null;

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  Future<void> _save() async {
    final medicalError = _validateMedicalInfo();
    if (medicalError != null) {
      _showValidationError(medicalError);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      await auth.completeProfile({
        'first_name': _pickNonEmpty(_storedFirstName, user?.firstName),
        'last_name': _pickNonEmpty(_storedLastName, user?.lastName),
        'phone': _pickNonEmpty(_phoneController.text, _pickNonEmpty(_storedPhone, user?.phone)),
        'dob': _dobController.text.trim(),
        'gender': _gender,
        'address': _addressController.text.trim(),
        'blood_type': _bloodType ?? 'Unknown',
        'allergies': _allergiesController.text.trim(),
        'chronic_diseases': _chronicController.text.trim(),
        'existing_conditions': _conditionsController.text.trim(),
        'emergency_contact_name': _emergencyNameController.text.trim(),
        'emergency_contact_phone': _emergencyPhoneController.text.trim(),
      });
      if (mounted) {
        Navigator.pushReplacementNamed(context, auth.getPostAuthRoute());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _onNext() {
    if (_currentStep == 0) {
      final error = _validatePersonalInfo();
      if (error != null) {
        _showValidationError('${AppLocalizations.tr('personal_info')}: $error');
        return;
      }
      setState(() => _currentStep = 1);
      return;
    }
    if (_currentStep == 1) {
      final error = _validateContactInfo();
      if (error != null) {
        _showValidationError('${AppLocalizations.tr('contact_info')}: $error');
        return;
      }
      setState(() => _currentStep = 2);
      return;
    }
    _save();
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / _stepTitles.length,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '${AppLocalizations.tr('step')} ${_currentStep + 1} / ${_stepTitles.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.tr(_stepTitles[_currentStep]),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          controller: _dobController,
          label: AppLocalizations.tr('date_of_birth'),
          prefixIcon: Icons.cake_outlined,
          readOnly: true,
          onTap: _selectDate,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _gender,
          decoration: InputDecoration(
            labelText: AppLocalizations.tr('gender'),
            prefixIcon: const Icon(Icons.wc),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            DropdownMenuItem(value: 'male', child: Text(AppLocalizations.tr('male'))),
            DropdownMenuItem(value: 'female', child: Text(AppLocalizations.tr('female'))),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _phoneController,
          label: AppLocalizations.tr('phone'),
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _addressController,
          label: AppLocalizations.tr('address'),
          prefixIcon: Icons.location_on_outlined,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildContactStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          controller: _emergencyNameController,
          label: '${AppLocalizations.tr('emergency_contact_name')} (${AppLocalizations.tr('optional_field')})',
          prefixIcon: Icons.contact_emergency_outlined,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _emergencyPhoneController,
          label: '${AppLocalizations.tr('emergency_contact_phone')} (${AppLocalizations.tr('optional_field')})',
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  Widget _buildMedicalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _bloodType,
          decoration: InputDecoration(
            labelText: '${AppLocalizations.tr('blood_type')} (${AppLocalizations.tr('optional_field')})',
            prefixIcon: const Icon(Icons.bloodtype_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: _bloodTypes.map((t) {
            final label = t == 'Unknown' ? AppLocalizations.tr('blood_type_unknown') : t;
            return DropdownMenuItem(value: t, child: Text(label));
          }).toList(),
          onChanged: (v) => setState(() => _bloodType = v),
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _allergiesController,
          label: '${AppLocalizations.tr('allergies')} (${AppLocalizations.tr('optional_field')})',
          prefixIcon: Icons.warning_amber_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _chronicController,
          label: '${AppLocalizations.tr('chronic_diseases')} (${AppLocalizations.tr('optional_field')})',
          prefixIcon: Icons.medical_services_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _conditionsController,
          label: '${AppLocalizations.tr('existing_conditions')} (${AppLocalizations.tr('optional_field')})',
          prefixIcon: Icons.health_and_safety_outlined,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildContactStep();
      case 2:
        return _buildMedicalStep();
      default:
        return _buildPersonalStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.tr('complete_profile'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isLastStep = _currentStep == _stepTitles.length - 1;

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('complete_profile'))),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildCurrentStepContent(),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton(
                        onPressed: _isLoading ? null : () => setState(() => _currentStep--),
                        child: Text(AppLocalizations.tr('previous')),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _onNext,
                        child: _isLoading && isLastStep
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(isLastStep ? AppLocalizations.tr('save') : AppLocalizations.tr('next')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
