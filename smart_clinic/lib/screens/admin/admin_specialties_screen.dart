import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/custom_text_field.dart';

class AdminSpecialtiesScreen extends StatefulWidget {
  const AdminSpecialtiesScreen({super.key});

  @override
  State<AdminSpecialtiesScreen> createState() => _AdminSpecialtiesScreenState();
}

class _AdminSpecialtiesScreenState extends State<AdminSpecialtiesScreen> {
  final AdminService _service = AdminService();
  List<Map<String, dynamic>> _specialties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _specialties = await _service.getSpecialties();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  void _showAddEditDialog({Map<String, dynamic>? specialty}) {
    final nameController = TextEditingController(text: specialty?['name'] ?? '');
    final descController = TextEditingController(text: specialty?['description'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(specialty == null ? AppLocalizations.tr('add_specialty') : AppLocalizations.tr('edit_specialty')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(controller: nameController, label: AppLocalizations.tr('specialty_name')),
            CustomTextField(controller: descController, label: AppLocalizations.tr('description'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.tr('required'))),
                );
                return;
              }
              try {
                if (specialty == null) {
                  await _service.createSpecialty({'name': nameController.text.trim(), 'description': descController.text.trim()});
                } else {
                  await _service.updateSpecialty(specialty['id'], {'name': nameController.text.trim(), 'description': descController.text.trim()});
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text(AppLocalizations.tr('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('confirm_delete')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('no'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('yes'))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _service.deleteSpecialty(id);
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('specialties'))),
      body: _isLoading
          ? const LoadingWidget()
          : _specialties.isEmpty
              ? EmptyState(icon: Icons.category, message: AppLocalizations.tr('no_data'), actionLabel: AppLocalizations.tr('add_specialty'), onAction: () => _showAddEditDialog())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _specialties.length,
                    itemBuilder: (ctx, i) {
                      final s = _specialties[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), child: Icon(Icons.category, color: Theme.of(context).colorScheme.primary)),
                          title: Text(s['name'] ?? ''),
                          subtitle: Text(s['description'] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (s['doctor_count'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Chip(label: Text('${s['doctor_count']} ${AppLocalizations.tr('doctors')}')),
                                ),
                              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showAddEditDialog(specialty: s)),
                              IconButton(icon: const Icon(Icons.delete, size: 20, color: Color(0xFFD32F2F)), onPressed: () => _delete(s['id'])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showAddEditDialog(), child: const Icon(Icons.add)),
    );
  }
}
