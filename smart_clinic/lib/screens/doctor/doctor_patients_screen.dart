import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/bottom_nav.dart';
import '../../utils/ui_helpers.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAllPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _mapRow(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString().trim();
    final parts = name.split(' ');
    return {
      'id': row['profile_id'] ?? row['id'],
      'profile_id': row['profile_id'] ?? row['id'],
      'first_name': row['first_name'] ?? (parts.isNotEmpty ? parts.first : name),
      'last_name': row['last_name'] ?? (parts.length > 1 ? parts.sublist(1).join(' ') : ''),
      'email': row['email'],
      'phone': row['phone'],
    };
  }

  Future<void> _loadAllPatients({String query = ''}) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final q = query.trim();
      final endpoint = q.isEmpty
          ? '/appointments/my-patients'
          : '/appointments/my-patients?q=${Uri.encodeQueryComponent(q)}';
      final response = await ApiService.instance.get(endpoint);
      final List<dynamic> data = response is List ? response : [];
      _patients = data.map((e) => _mapRow(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      _loadError = extractApiError(e);
      _patients = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _search(String query) async {
    await _loadAllPatients(query: query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('patients'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.tr('search_patients_hint'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchController.text),
                ),
              ),
              onSubmitted: _search,
              onChanged: (v) {
                if (v.trim().isEmpty) _loadAllPatients();
              },
            ),
          ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _isLoading
                ? const LoadingWidget()
                : _patients.isEmpty
                    ? EmptyState(icon: Icons.people, message: AppLocalizations.tr('no_data'))
                    : RefreshIndicator(
                        onRefresh: () => _loadAllPatients(query: _searchController.text),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _patients.length,
                          itemBuilder: (ctx, i) {
                            final p = _patients[i];
                            final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),
                                title: Text(name),
                                subtitle: Text(
                                  p['phone']?.toString().isNotEmpty == true
                                      ? p['phone'].toString()
                                      : (p['email'] ?? ''),
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () => Navigator.pushNamed(context, AppRoutes.doctorPatientDetail, arguments: p),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 2, role: 'doctor'),
    );
  }
}
