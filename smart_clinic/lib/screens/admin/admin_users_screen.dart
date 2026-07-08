import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/ui_helpers.dart';

class AdminUsersScreen extends StatefulWidget {
  final int initialTab;

  const AdminUsersScreen({super.key, this.initialTab = 0});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _service = AdminService();
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _receptionists = [];
  List<Map<String, dynamic>> _admins = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getUsers(role: 'patient'),
        _service.getUsers(role: 'doctor'),
        _service.getUsers(role: 'receptionist'),
        _service.getUsers(role: 'admin'),
      ]);
      _patients = results[0];
      _doctors = results[1];
      _receptionists = results[2];
      _admins = results[3];
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    setState(() => _isLoading = false);
  }

  Map<String, dynamic>? _profileOf(Map<String, dynamic> user) {
    final profile = user['profile'];
    return profile is Map ? Map<String, dynamic>.from(profile) : null;
  }

  Map<String, dynamic>? _doctorInfoOf(Map<String, dynamic> user) {
    final info = user['doctor_info'];
    return info is Map ? Map<String, dynamic>.from(info) : null;
  }

  String _userName(Map<String, dynamic> user) {
    final profile = _profileOf(user);
    final name = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    return name.isNotEmpty ? name : (user['email'] ?? '').toString();
  }

  String? _photoUrl(Map<String, dynamic> user) => _profileOf(user)?['photo_url']?.toString();

  bool _isCurrentUser(Map<String, dynamic> user) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.currentUser?.id == user['id'];
  }

  bool _canManageUser(Map<String, dynamic> user) => !_isCurrentUser(user);

  String _userSubtitle(Map<String, dynamic> user) {
    final email = (user['email'] ?? '').toString();
    if (user['role'] == 'doctor') {
      final specialty = _doctorInfoOf(user)?['specialty_name']?.toString();
      if (specialty != null && specialty.isNotEmpty) return '$email • $specialty';
    }
    return email;
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    if (!_canManageUser(user)) {
      if (mounted) showErrorSnackBar(context, AppLocalizations.tr('cannot_delete_self'));
      return;
    }
    try {
      final isActive = user['is_active'] == true;
      await _service.toggleUserActive(user['id'], !isActive);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (!_canManageUser(user)) {
      if (mounted) showErrorSnackBar(context, AppLocalizations.tr('cannot_delete_self'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('delete')),
        content: Text(AppLocalizations.tr('delete_user_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('no'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.tr('yes'), style: const TextStyle(color: Color(0xFFD32F2F))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteUser(user['id']);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  void _openPatientDetail(Map<String, dynamic> user) {
    Navigator.pushNamed(
      context,
      AppRoutes.adminPatientDetail,
      arguments: {'user_id': user['id']},
    );
  }

  void _onUserTap(Map<String, dynamic> user) {
    if (user['role'] == 'patient') {
      _openPatientDetail(user);
      return;
    }
    _showUserDetails(user);
  }

  void _showUserDetails(Map<String, dynamic> user) {
    final profile = _profileOf(user);
    final doctorInfo = _doctorInfoOf(user);
    final name = _userName(user);
    final photoUrl = _photoUrl(user);
    final isActive = user['is_active'] == true;
    final canManage = _canManageUser(user);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(name: name, photoUrl: photoUrl, radius: 48, loadFromApi: false),
              const SizedBox(height: 16),
              Text(name, style: Theme.of(ctx).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(user['email'] ?? '', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 8),
              RoleBadge(label: user['role']?.toString().toUpperCase() ?? '', color: const Color(0xFF1565C0)),
              const SizedBox(height: 8),
              RoleBadge(
                label: isActive ? AppLocalizations.tr('active') : AppLocalizations.tr('deactivate'),
                color: isActive ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
              ),
              const SizedBox(height: 16),
              if (doctorInfo != null) ...[
                _detailRow(ctx, AppLocalizations.tr('specialty_name'), doctorInfo['specialty_name']),
                _detailRow(ctx, AppLocalizations.tr('qualifications'), doctorInfo['qualifications']),
                _detailRow(ctx, AppLocalizations.tr('bio'), doctorInfo['bio']),
              ],
              if (profile != null) ...[
                _detailRow(ctx, AppLocalizations.tr('phone'), profile['phone'] ?? user['phone']),
                _detailRow(ctx, AppLocalizations.tr('gender'), profile['gender']),
                _detailRow(ctx, AppLocalizations.tr('date_of_birth'), profile['dob']),
                _detailRow(ctx, AppLocalizations.tr('address'), profile['address']),
                _detailRow(ctx, AppLocalizations.tr('blood_type'), profile['blood_type']),
                _detailRow(ctx, AppLocalizations.tr('allergies'), profile['allergies']),
                _detailRow(ctx, AppLocalizations.tr('chronic_diseases'), profile['chronic_diseases']),
                _detailRow(ctx, AppLocalizations.tr('emergency_contact_name'), profile['emergency_contact_name']),
                _detailRow(ctx, AppLocalizations.tr('emergency_contact_phone'), profile['emergency_contact_phone']),
                if (photoUrl != null && photoUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        '${ApiConfig.url}$photoUrl',
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
              if (user['created_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${AppLocalizations.tr('member_since')}: ${user['created_at'].toString().substring(0, 10)}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (user['role'] == 'patient') ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openPatientDetail(user);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(AppLocalizations.tr('view_full_details')),
                  ),
                ),
              ],
              if (canManage) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _toggleStatus(user);
                        },
                        icon: Icon(isActive ? Icons.block : Icons.check_circle),
                        label: Text(isActive ? AppLocalizations.tr('deactivate') : AppLocalizations.tr('activate')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteUser(user);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(AppLocalizations.tr('delete')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value.toString())),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('users')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: '${AppLocalizations.tr('patients')} (${_patients.length})'),
            Tab(text: '${AppLocalizations.tr('doctors')} (${_doctors.length})'),
            Tab(text: '${AppLocalizations.tr('receptionists')} (${_receptionists.length})'),
            Tab(text: '${AppLocalizations.tr('admins')} (${_admins.length})'),
          ],
        ),
        actions: [
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(
                child: Text(AppLocalizations.tr('create_doctor')),
                onTap: () {
                  final nav = Navigator.of(context);
                  Future.microtask(() => nav.pushNamed(AppRoutes.adminCreateDoctor));
                },
              ),
              PopupMenuItem(
                child: Text(AppLocalizations.tr('create_receptionist')),
                onTap: () {
                  final nav = Navigator.of(context);
                  Future.microtask(() => nav.pushNamed(AppRoutes.adminCreateReceptionist));
                },
              ),
              PopupMenuItem(
                child: Text(AppLocalizations.tr('create_admin')),
                onTap: () {
                  final nav = Navigator.of(context);
                  Future.microtask(() => nav.pushNamed(AppRoutes.adminCreateAdmin));
                },
              ),
              PopupMenuItem(
                child: Text(AppLocalizations.tr('register_patient')),
                onTap: () {
                  final nav = Navigator.of(context);
                  Future.microtask(() => nav.pushNamed(AppRoutes.adminCreatePatient));
                },
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.tr('search'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserList(_patients),
                      _buildUserList(_doctors),
                      _buildUserList(_receptionists),
                      _buildUserList(_admins),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 1, role: 'admin'),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, {bool readOnly = false}) {
    final query = _searchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? users
        : users.where((u) {
            final name = _userName(u).toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();
            final specialty = (_doctorInfoOf(u)?['specialty_name'] ?? '').toString().toLowerCase();
            return name.contains(query) || email.contains(query) || specialty.contains(query);
          }).toList();

    if (filtered.isEmpty) return EmptyState(icon: Icons.people, message: AppLocalizations.tr('no_data'));
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
          final u = filtered[i];
          final name = _userName(u);
          final isActive = u['is_active'] == true;
          return Card(
            child: ListTile(
              onTap: () => _onUserTap(u),
              leading: UserAvatar(name: name, photoUrl: _photoUrl(u), radius: 22, loadFromApi: false),
              title: Text(name),
              subtitle: Text(_userSubtitle(u)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoleBadge(
                    label: isActive ? AppLocalizations.tr('active') : AppLocalizations.tr('deactivate'),
                    color: isActive ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
                  ),
                  if (!readOnly && _canManageUser(u))
                    PopupMenuButton(
                      itemBuilder: (ctx) => [
                        if (u['role'] == 'patient')
                          PopupMenuItem(
                            child: Text(AppLocalizations.tr('view_full_details')),
                            onTap: () => Future.microtask(() => _openPatientDetail(u)),
                          ),
                        PopupMenuItem(
                          child: Text(AppLocalizations.tr('user_details')),
                          onTap: () => Future.microtask(() => _showUserDetails(u)),
                        ),
                        PopupMenuItem(
                          child: Text(isActive ? AppLocalizations.tr('deactivate') : AppLocalizations.tr('activate')),
                          onTap: () => Future.microtask(() => _toggleStatus(u)),
                        ),
                        PopupMenuItem(
                          child: Text(AppLocalizations.tr('delete'), style: const TextStyle(color: Color(0xFFD32F2F))),
                          onTap: () => Future.microtask(() => _deleteUser(u)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
