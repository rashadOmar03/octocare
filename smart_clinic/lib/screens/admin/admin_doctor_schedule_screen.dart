import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/time_picker_field.dart';
import '../../widgets/bottom_nav.dart';

class AdminDoctorScheduleScreen extends StatefulWidget {
  const AdminDoctorScheduleScreen({super.key});

  @override
  State<AdminDoctorScheduleScreen> createState() => _AdminDoctorScheduleScreenState();
}

class _AdminDoctorScheduleScreenState extends State<AdminDoctorScheduleScreen> {
  final AdminService _service = AdminService();
  List<Map<String, dynamic>> _doctors = [];
  Map<String, dynamic>? _detail;
  String? _selectedDoctorId;
  bool _loadingList = true;
  bool _loadingDetail = false;
  bool _saving = false;
  final _feeController = TextEditingController();
  final _startHourController = TextEditingController();
  final _endHourController = TextEditingController();
  final Map<int, bool> _dayAvailable = {};
  final Map<int, TextEditingController> _dayStart = {};
  final Map<int, TextEditingController> _dayEnd = {};
  Set<int> _clinicWorkingDays = {5, 6, 0, 1, 2, 3};

  static const _dayOrder = [5, 6, 0, 1, 2, 3, 4];

  String _dayLabel(int day) {
    switch (day) {
      case 0:
        return AppLocalizations.tr('day_mon');
      case 1:
        return AppLocalizations.tr('day_tue');
      case 2:
        return AppLocalizations.tr('day_wed');
      case 3:
        return AppLocalizations.tr('day_thu');
      case 4:
        return AppLocalizations.tr('day_fri');
      case 5:
        return AppLocalizations.tr('day_sat');
      case 6:
        return AppLocalizations.tr('day_sun');
      default:
        return '$day';
    }
  }

  @override
  void initState() {
    super.initState();
    for (final day in _dayOrder) {
      _dayAvailable[day] = {5, 6, 0, 1, 2, 3}.contains(day);
      _dayStart[day] = TextEditingController(text: '09:00');
      _dayEnd[day] = TextEditingController(text: '17:00');
    }
    _loadDoctors();
  }

  @override
  void dispose() {
    _feeController.dispose();
    _startHourController.dispose();
    _endHourController.dispose();
    for (final c in _dayStart.values) {
      c.dispose();
    }
    for (final c in _dayEnd.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    setState(() => _loadingList = true);
    try {
      final users = await _service.getUsers(role: 'doctor');
      _doctors = users
          .where((u) => u['doctor_info'] != null)
          .map((u) => {
                'doctor_id': u['doctor_info']['doctor_id']?.toString(),
                'name': '${u['profile']?['first_name'] ?? ''} ${u['profile']?['last_name'] ?? ''}'.trim(),
                'specialty': u['doctor_info']?['specialty_name']?.toString() ?? '',
              })
          .where((d) => d['doctor_id'] != null)
          .toList();
    } catch (_) {
      _doctors = [];
    }
    if (mounted) setState(() => _loadingList = false);
  }

  Future<void> _loadDetail(String doctorId) async {
    setState(() {
      _selectedDoctorId = doctorId;
      _loadingDetail = true;
    });
    try {
      final detail = await _service.getDoctorManage(doctorId);
      _detail = detail;
      try {
        final clinic = await _service.getSettings();
        final rawDays = clinic['working_days']?.toString() ?? '5,6,0,1,2,3';
        _clinicWorkingDays = rawDays
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toSet();
        if (_clinicWorkingDays.isEmpty) _clinicWorkingDays = {5, 6, 0, 1, 2, 3};
      } catch (_) {}
      final fee = detail['consultation_fee'];
      _feeController.text = fee == null ? '' : '$fee';
      final schedules = (detail['schedules'] as List? ?? []).cast<Map>();
      String start = '09:00';
      String end = '17:00';
      if (schedules.isNotEmpty) {
        start = schedules.first['start_time']?.toString() ?? start;
        end = schedules.first['end_time']?.toString() ?? end;
      } else {
        try {
          final clinic = await _service.getSettings();
          start = clinic['working_hours_start']?.toString() ?? start;
          end = clinic['working_hours_end']?.toString() ?? end;
          final rawDays = (clinic['working_days']?.toString() ?? '5,6,0,1,2,3').split(',');
          for (final part in rawDays) {
            final day = int.tryParse(part.trim());
            if (day != null) _dayAvailable[day] = true;
          }
        } catch (_) {}
      }
      _startHourController.text = start;
      _endHourController.text = end;
      for (final day in _dayOrder) {
        if (!_clinicWorkingDays.contains(day)) {
          _dayAvailable[day] = false;
        } else if (schedules.isNotEmpty) {
          _dayAvailable[day] = false;
        }
      }
      for (final row in schedules) {
        final day = row['day_of_week'] is int ? row['day_of_week'] as int : int.tryParse('${row['day_of_week']}') ?? -1;
        if (day < 0) continue;
        _dayAvailable[day] = row['is_available'] == true;
        _dayStart[day]?.text = row['start_time']?.toString() ?? start;
        _dayEnd[day]?.text = row['end_time']?.toString() ?? end;
      }
    } catch (_) {
      _detail = null;
    }
    if (mounted) setState(() => _loadingDetail = false);
  }

  Future<void> _saveSchedule() async {
    if (_selectedDoctorId == null) return;
    final enabledClinicDays = _dayOrder.where((d) => _dayAvailable[d] == true).length;
    if (enabledClinicDays == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.tr('doctor_hours_not_set')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final schedules = _dayOrder
          .map((day) => {
                'day_of_week': day,
                'start_time': _dayStart[day]?.text.trim() ?? _startHourController.text.trim(),
                'end_time': _dayEnd[day]?.text.trim() ?? _endHourController.text.trim(),
                'is_available': _clinicWorkingDays.contains(day) && _dayAvailable[day] == true,
              })
          .toList();
      _detail = await _service.updateDoctorSchedule(_selectedDoctorId!, {
        'schedules': schedules,
        'working_hours_start': _startHourController.text.trim(),
        'working_hours_end': _endHourController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('settings_saved')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveFee() async {
    if (_selectedDoctorId == null) return;
    setState(() => _saving = true);
    try {
      final text = _feeController.text.trim();
      final fee = text.isEmpty ? null : double.tryParse(text);
      _detail = await _service.updateDoctorFee(_selectedDoctorId!, fee);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('settings_saved')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addTimeOff() async {
    if (_selectedDoctorId == null) return;
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
                  title: Text(start == null ? AppLocalizations.tr('from_date') : '${start!.year}-${start!.month}-${start!.day}'),
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
                  title: Text(end == null ? AppLocalizations.tr('to_date') : '${end!.year}-${end!.month}-${end!.day}'),
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
      await _service.addDoctorTimeOff(_selectedDoctorId!, {
        'start_date': startStr,
        'end_date': endStr,
        'reason': reason.isEmpty ? null : reason,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('settings_saved')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
      await _loadDetail(_selectedDoctorId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _deleteTimeOff(String id) async {
    if (_selectedDoctorId == null) return;
    try {
      await _service.deleteDoctorTimeOff(_selectedDoctorId!, id);
      await _loadDetail(_selectedDoctorId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('doctor_schedules'))),
      body: _loadingList
          ? const LoadingWidget()
          : Row(
              children: [
                SizedBox(
                  width: 280,
                  child: ListView.builder(
                    itemCount: _doctors.length,
                    itemBuilder: (_, i) {
                      final d = _doctors[i];
                      final id = d['doctor_id']?.toString();
                      final selected = id == _selectedDoctorId;
                      return ListTile(
                        selected: selected,
                        title: Text(d['name']?.toString() ?? ''),
                        subtitle: Text(d['specialty']?.toString() ?? ''),
                        onTap: id == null ? null : () => _loadDetail(id),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedDoctorId == null
                      ? Center(child: Text(AppLocalizations.tr('select_patient').replaceAll('patient', 'doctor')))
                      : _loadingDetail
                          ? const LoadingWidget()
                          : _buildDetail(),
                ),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 3, role: 'admin'),
    );
  }

  Widget _buildDetail() {
    final timeOff = (_detail?['time_off'] as List? ?? []).cast<Map>();
    final defaultFee = _detail?['default_fee']?.toString() ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_detail?['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
          if ((_detail?['specialty_name'] ?? '').toString().isNotEmpty)
            Text(_detail!['specialty_name'].toString(), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(AppLocalizations.tr('consultation_fee'), style: Theme.of(context).textTheme.titleMedium),
          CustomTextField(
            controller: _feeController,
            label: '${AppLocalizations.tr('consultation_fee')} (${AppLocalizations.tr('use_clinic_default_fee')}: $defaultFee)',
            prefixIcon: Icons.attach_money,
            keyboardType: TextInputType.number,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(onPressed: _saving ? null : _saveFee, child: Text(AppLocalizations.tr('save'))),
          ),
          const Divider(height: 32),
          Text(AppLocalizations.tr('working_hours'), style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              Expanded(child: TimePickerField(controller: _startHourController, label: AppLocalizations.tr('working_hours'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
              Expanded(child: TimePickerField(controller: _endHourController, label: '')),
            ],
          ),
          const SizedBox(height: 8),
          ..._dayOrder.map((day) {
            final clinicOpen = _clinicWorkingDays.contains(day);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_dayLabel(day)),
                      subtitle: clinicOpen
                          ? null
                          : Text(
                              AppLocalizations.tr('clinic_closed_day'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      value: clinicOpen && _dayAvailable[day] == true,
                      onChanged: clinicOpen ? (v) => setState(() => _dayAvailable[day] = v) : null,
                    ),
                    if (clinicOpen && _dayAvailable[day] == true)
                      Row(
                        children: [
                          Expanded(child: TimePickerField(controller: _dayStart[day]!, label: AppLocalizations.tr('working_hours'))),
                          const SizedBox(width: 8),
                          Expanded(child: TimePickerField(controller: _dayEnd[day]!, label: '')),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveSchedule,
            icon: const Icon(Icons.save),
            label: Text(AppLocalizations.tr('save_settings')),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(child: Text(AppLocalizations.tr('time_off'), style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(onPressed: _addTimeOff, icon: const Icon(Icons.add), label: Text(AppLocalizations.tr('add_time_off'))),
            ],
          ),
          if (timeOff.isEmpty)
            Text(AppLocalizations.tr('no_data'))
          else
            ...timeOff.map((row) {
              final id = row['id']?.toString() ?? '';
              return ListTile(
                title: Text('${row['start_date']} → ${row['end_date']}'),
                subtitle: (row['reason'] ?? '').toString().isNotEmpty ? Text(row['reason'].toString()) : null,
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteTimeOff(id)),
              );
            }),
        ],
      ),
    );
  }
}
