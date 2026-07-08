import 'package:flutter/material.dart';

import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/loading_widget.dart';

class DoctorVacationScreen extends StatefulWidget {
  const DoctorVacationScreen({super.key});

  @override
  State<DoctorVacationScreen> createState() => _DoctorVacationScreenState();
}

class _DoctorVacationScreenState extends State<DoctorVacationScreen> {
  List<Map<String, dynamic>> _timeOff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.get('/doctors/me/time-off');
      final list = data is List ? data : (data is Map ? (data['items'] as List? ?? []) : []);
      if (!mounted) return;
      setState(() {
        _timeOff = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnackBar(context, e);
    }
  }

  Future<void> _addTimeOff() async {
    DateTime? start;
    DateTime? end;
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.tr('add_time_off')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    start == null
                        ? AppLocalizations.tr('from_date')
                        : '${start!.year}-${start!.month}-${start!.day}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => start = picked);
                  },
                ),
                ListTile(
                  title: Text(
                    end == null
                        ? AppLocalizations.tr('to_date')
                        : '${end!.year}-${end!.month}-${end!.day}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: start ?? DateTime.now(),
                      firstDate: start ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => end = picked);
                  },
                ),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(labelText: AppLocalizations.tr('vacation_reason')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('save'))),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (ok != true || start == null || end == null) return;

    final startStr = '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}';
    final endStr = '${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}';
    try {
      await ApiService.instance.post('/doctors/me/time-off', {
        'start_date': startStr,
        'end_date': endStr,
        if (reason.isNotEmpty) 'reason': reason,
      });
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('settings_saved'));
      }
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _deleteTimeOff(String id) async {
    try {
      await ApiService.instance.delete('/doctors/me/time-off/$id');
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('settings_saved'));
      }
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('time_off'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTimeOff,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.tr('add_time_off')),
      ),
      body: _loading
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: _load,
              child: _timeOff.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(AppLocalizations.tr('no_data'))),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      itemCount: _timeOff.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final row = _timeOff[i];
                        final id = row['id']?.toString() ?? '';
                        return Card(
                          child: ListTile(
                            title: Text('${row['start_date']} → ${row['end_date']}'),
                            subtitle: (row['reason'] ?? '').toString().isNotEmpty
                                ? Text(row['reason'].toString())
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: id.isEmpty ? null : () => _deleteTimeOff(id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 4, role: 'doctor'),
    );
  }
}
