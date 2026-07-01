import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../config/routes.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/role_badge.dart';
import '../../utils/time_format.dart';

class AdminPatientDetailScreen extends StatefulWidget {
  const AdminPatientDetailScreen({super.key});

  @override
  State<AdminPatientDetailScreen> createState() => _AdminPatientDetailScreenState();
}

class _AdminPatientDetailScreenState extends State<AdminPatientDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _service = AdminService();
  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _userId = args['user_id']?.toString() ?? args['id']?.toString();
      }
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);
    try {
      _detail = await _service.getPatientDetail(_userId!);
    } catch (_) {
      _detail = null;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Map<String, dynamic>? get _user => _detail?['user'] is Map ? Map<String, dynamic>.from(_detail!['user']) : null;
  Map<String, dynamic>? get _profile {
    final profile = _user?['profile'];
    return profile is Map ? Map<String, dynamic>.from(profile) : null;
  }

  Map<String, dynamic>? get _stats => _detail?['stats'] is Map ? Map<String, dynamic>.from(_detail!['stats']) : null;

  List<Map<String, dynamic>> _list(String key) {
    final raw = _detail?[key];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _name() {
    final profile = _profile;
    final name = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    return name.isNotEmpty ? name : (_user?['email'] ?? '').toString();
  }

  Widget _infoRow(String label, dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value.toString())),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overviewTab() {
    final profile = _profile;
    final stats = _stats;
    final photoUrl = profile?['photo_url']?.toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              UserAvatar(name: _name(), photoUrl: photoUrl, radius: 48, loadFromApi: false),
              const SizedBox(height: 12),
              Text(_name(), style: Theme.of(context).textTheme.titleLarge),
              Text(_user?['email'] ?? ''),
              const SizedBox(height: 8),
              RoleBadge(
                label: (_user?['is_active'] == true) ? AppLocalizations.tr('active') : AppLocalizations.tr('deactivate'),
                color: (_user?['is_active'] == true) ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
              ),
            ],
          ),
        ),
        if (photoUrl != null && photoUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network('${ApiConfig.url}$photoUrl', height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
        if (stats != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _statCard(AppLocalizations.tr('appointments'), '${stats['total_appointments'] ?? 0}'),
              const SizedBox(width: 8),
              _statCard(AppLocalizations.tr('records'), '${stats['total_records'] ?? 0}'),
              const SizedBox(width: 8),
              _statCard(AppLocalizations.tr('prescriptions'), '${stats['total_prescriptions'] ?? 0}'),
            ],
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('account_info'), style: Theme.of(context).textTheme.titleMedium),
                _infoRow(AppLocalizations.tr('phone'), profile?['phone'] ?? _user?['phone']),
                _infoRow(AppLocalizations.tr('gender'), profile?['gender']),
                _infoRow(AppLocalizations.tr('date_of_birth'), profile?['dob']),
                _infoRow(AppLocalizations.tr('address'), profile?['address']),
                _infoRow(AppLocalizations.tr('blood_type'), profile?['blood_type']),
                _infoRow(AppLocalizations.tr('member_since'), _user?['created_at']?.toString().substring(0, 10)),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('medical_history'), style: Theme.of(context).textTheme.titleMedium),
                _infoRow(AppLocalizations.tr('allergies'), profile?['allergies']),
                _infoRow(AppLocalizations.tr('chronic_diseases'), profile?['chronic_diseases']),
                _infoRow(AppLocalizations.tr('existing_conditions'), profile?['existing_conditions']),
                _infoRow(AppLocalizations.tr('emergency_contact_name'), profile?['emergency_contact_name']),
                _infoRow(AppLocalizations.tr('emergency_contact_phone'), profile?['emergency_contact_phone']),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _appointmentsTab() {
    final items = _list('appointments');
    if (items.isEmpty) return EmptyState(icon: Icons.calendar_today, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final a = items[i];
        return Card(
          child: ListTile(
            title: Text('${a['doctor_name'] ?? AppLocalizations.tr('doctor')} • ${a['specialty_name'] ?? ''}'),
            subtitle: Text('${a['date'] ?? ''} • ${TimeFormat.format24To12(a['time_slot']?.toString())}\n${a['status'] ?? ''}'),
            isThreeLine: true,
            trailing: a['is_paid'] == true ? const Icon(Icons.paid, color: Color(0xFF388E3C)) : null,
          ),
        );
      },
    );
  }

  Widget _recordsTab() {
    final items = _list('records');
    if (items.isEmpty) return EmptyState(icon: Icons.medical_information, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final r = items[i];
        return Card(
          child: ExpansionTile(
            title: Text(r['diagnosis']?.toString() ?? AppLocalizations.tr('records')),
            subtitle: Text('${r['doctor_name'] ?? ''} • ${r['created_at']?.toString().substring(0, 10) ?? ''}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(AppLocalizations.tr('chief_complaint'), r['chief_complaint']),
                    _infoRow(AppLocalizations.tr('symptoms'), r['symptoms']),
                    _infoRow(AppLocalizations.tr('severity'), r['severity']),
                    _infoRow(AppLocalizations.tr('treatment_plan'), r['treatment_plan']),
                    _infoRow(AppLocalizations.tr('notes'), r['notes']),
                    _infoRow('SOAP S', r['soap_subjective']),
                    _infoRow('SOAP O', r['soap_objective']),
                    _infoRow('SOAP A', r['soap_assessment']),
                    _infoRow('SOAP P', r['soap_plan']),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _prescriptionsTab() {
    final items = _list('prescriptions');
    if (items.isEmpty) return EmptyState(icon: Icons.medication, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final p = items[i];
        final itemsRaw = p['items'];
        final meds = itemsRaw is List ? itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
        return Card(
          child: ListTile(
            onTap: p['id'] != null
                ? () => Navigator.pushNamed(context, AppRoutes.adminPrescriptionDetail, arguments: {'id': p['id']})
                : null,
            title: Text(meds.map((m) => m['medication_name'] ?? '').where((n) => n.toString().isNotEmpty).join(', ')),
            subtitle: Text('${p['status'] ?? ''} • ${p['created_at']?.toString().substring(0, 10) ?? ''}'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _paymentsTab() {
    final items = _list('payments');
    if (items.isEmpty) return EmptyState(icon: Icons.payment, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final p = items[i];
        return Card(
          child: ListTile(
            title: Text('${p['amount'] ?? ''} • ${p['payment_status'] ?? ''}'),
            subtitle: Text('${p['doctor_name'] ?? ''} • ${p['appointment_date'] ?? ''} ${p['time_slot'] ?? ''}'),
            trailing: Text(p['payment_method']?.toString() ?? ''),
          ),
        );
      },
    );
  }

  Widget _documentsTab() {
    final items = _list('documents');
    if (items.isEmpty) return EmptyState(icon: Icons.folder, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final d = items[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: Text(d['file_name']?.toString() ?? AppLocalizations.tr('documents')),
            subtitle: Text('${d['category'] ?? ''} • ${d['upload_date']?.toString().substring(0, 10) ?? ''}'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('patient_full_details')),
        bottom: _isLoading || _detail == null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  Tab(text: AppLocalizations.tr('overview')),
                  Tab(text: AppLocalizations.tr('appointments')),
                  Tab(text: AppLocalizations.tr('records')),
                  Tab(text: AppLocalizations.tr('prescriptions')),
                  Tab(text: AppLocalizations.tr('payments')),
                  Tab(text: AppLocalizations.tr('documents')),
                ],
              ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _detail == null
              ? EmptyState(icon: Icons.error_outline, message: AppLocalizations.tr('load_failed'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _overviewTab(),
                    _appointmentsTab(),
                    _recordsTab(),
                    _prescriptionsTab(),
                    _paymentsTab(),
                    _documentsTab(),
                  ],
                ),
    );
  }
}
